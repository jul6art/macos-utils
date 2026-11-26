"""Builds Visage's faces (spec, § 8.1): one .glb per preset, a MakeHuman head with its eyes, brows, lashes,
teeth, tongue and hair, carrying the 52 ARKit shapes as morph targets named as ARKit names them; and beside
it, one texture per part, named as its node (`<face>.<part>.jpg` or `.png`), for the realistic end of the
hologram (§ 8.3).

Run by tools/faces/build.sh, inside Blender, without its interface:
    blender -b --factory-startup --python build_faces.py -- presets.json <output directory> [<face id>…]

Needs Blender's MPFB extension and MakeHuman's CC0 packs: system assets and faceunits01.
"""

import json
import os
import sys

import math

import addon_utils
import bmesh
import bpy
import numpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService  # noqa: E402
from bl_ext.user_default.mpfb.services.targetservice import TargetService  # noqa: E402

# The order of Sources/FaceAnimation/FaceShape.swift.
SHAPES = """browDownLeft browDownRight browInnerUp browOuterUpLeft browOuterUpRight cheekPuff cheekSquintLeft
cheekSquintRight eyeBlinkLeft eyeBlinkRight eyeLookDownLeft eyeLookDownRight eyeLookInLeft eyeLookInRight
eyeLookOutLeft eyeLookOutRight eyeLookUpLeft eyeLookUpRight eyeSquintLeft eyeSquintRight eyeWideLeft eyeWideRight
jawForward jawLeft jawOpen jawRight mouthClose mouthDimpleLeft mouthDimpleRight mouthFrownLeft mouthFrownRight
mouthFunnel mouthLeft mouthLowerDownLeft mouthLowerDownRight mouthPressLeft mouthPressRight mouthPucker mouthRight
mouthRollLower mouthRollUpper mouthShrugLower mouthShrugUpper mouthSmileLeft mouthSmileRight mouthStretchLeft
mouthStretchRight mouthUpperUpLeft mouthUpperUpRight noseSneerLeft noseSneerRight tongueOut""".split()

# Head and neck: the top 25 cm of a body about 1.7 m tall, above the shoulders.
HEAD_AND_NECK = 0.25

# Where the face is seen from: the viewer in front of it, up to 70 degrees to either side and 35 above or
# below (the head turns, the camera's parallax). In Blender's axes, the face looks towards -Y.
VIEWS = [
    Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    for yaw in (math.radians(d) for d in range(-70, 71, 10))
    for pitch in (math.radians(d) for d in range(-35, 36, 10))
]


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:]
    presets = json.load(open(arguments[0], encoding="utf-8"))
    output = arguments[1]
    if arguments[2:]:
        presets = [preset for preset in presets if preset["id"] in arguments[2:]]
    os.makedirs(output, exist_ok=True)
    data = LocationService.get_user_data()
    for preset in presets:
        clear_scene()
        path = os.path.join(output, preset["id"] + ".glb")
        skin_box = build(preset, data, path)
        write_textures(preset, data, output, skin_box)
        print(f"FACE {preset['id']} {os.path.getsize(path) / 1e6:.2f} MB")


# Per part: the texture's size in the app (its height, for the skin's cropped one), and whether it keeps
# its transparency (PNG) or not (JPEG).
TEXTURES = {
    "head": (2048, False), "eyes": (256, True), "eyebrows": (256, True), "eyelashes": (256, True),
    "teeth": (512, True), "tongue": (256, False), "hair": (1024, True),
}


# MakeHuman's "brown" iris is a deep, saturated red (hue 7°, saturation 0.99): on a face it reads burgundy.
# Its iris turns to a natural brown, the hue and the share of its saturation kept below; the white, grey,
# stays as it is.
IRIS = {"brown": (24 / 360, 0.7)}

def colour_like(image, colour, contrast=0.85):
    """Hair or brows in `colour` (« #rrggbb »): each pixel keeps its brightness relative to the texture's
    average (where it is opaque), softened by `contrast`, so that strands and curls still show; its
    transparency is untouched. MakeHuman's hair comes in few colours, its brows all near black."""
    width, height = image.size
    pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(-1, 4)
    luminance = pixels[:, :3] @ numpy.array([0.299, 0.587, 0.114], dtype=numpy.float32)
    opaque = pixels[:, 3] > 0.5
    average = max(float(luminance[opaque].mean()) if opaque.any() else 0.5, 1e-3)
    target = numpy.array([int(colour[k:k + 2], 16) / 255 for k in (1, 3, 5)], dtype=numpy.float32)
    # Capped: the texture's highlights, three times its average, turned a chestnut into copper.
    relative = numpy.minimum(numpy.power(numpy.maximum(luminance / average, 0), contrast), 1.5)[:, None]
    pixels[:, :3] = numpy.clip(target * relative, 0, 1)
    image.pixels.foreach_set(pixels.ravel())

def recolour_iris(image, hue, keep):
    """The saturated pixels of an eye texture (the iris) to `hue`, `keep` of their saturation, same value."""
    width, height = image.size
    pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(-1, 4)
    rgb = pixels[:, :3]
    value = rgb.max(1)
    saturation = numpy.where(value > 0, (value - rgb.min(1)) / numpy.maximum(value, 1e-6), 0)
    iris = numpy.clip((saturation - 0.25) / 0.2, 0, 1)[:, None]
    chroma = value * saturation * keep
    sector = hue * 6
    second = chroma * (1 - abs(sector % 2 - 1))
    zero = numpy.zeros_like(chroma)
    order = [(chroma, second, zero), (second, chroma, zero), (zero, chroma, second),
             (zero, second, chroma), (second, zero, chroma), (chroma, zero, second)][int(sector) % 6]
    recoloured = numpy.stack(order, 1) + (value - chroma)[:, None]
    pixels[:, :3] = rgb * (1 - iris) + recoloured * iris
    image.pixels.foreach_set(pixels.ravel())


def skin_folder(preset):
    """MakeHuman's skins come by age, origin and gender: the nearest to the preset."""
    age = "young" if preset["age"] < 35 else "middleage" if preset["age"] < 55 else "old"
    origin = ["asian", "caucasian", "african"][max(range(3), key=lambda index: preset["race"][index])]
    return os.path.join("skins", f"{age}_{origin}_{'female' if preset['gender'] < 0.5 else 'male'}")


def diffuse(material):
    """The diffuse texture a MakeHuman material (.mhmat) names, beside it."""
    for line in open(material, encoding="utf-8"):
        if line.startswith("diffuseTexture "):
            return os.path.join(os.path.dirname(material), line.split(maxsplit=1)[1].strip())
    raise ValueError(f"no diffuse texture in {material}")


def fit_uvs(obj, margin=0.01):
    """The skin texture is the whole body's, and the head fills a third of it: only that third ships, the
    head's UVs stretched to fill it. Returns the box it was, in the texture's UVs."""
    uvs = obj.data.uv_layers.active.data
    us = [loop.uv.x for loop in uvs]
    vs = [loop.uv.y for loop in uvs]
    u0, u1 = max(min(us) - margin, 0.0), min(max(us) + margin, 1.0)
    v0, v1 = max(min(vs) - margin, 0.0), min(max(vs) + margin, 1.0)
    for loop in uvs:
        loop.uv.x = (loop.uv.x - u0) / (u1 - u0)
        loop.uv.y = (loop.uv.y - v0) / (v1 - v0)
    return u0, v0, u1, v1


def crop(image, box, height):
    """The part of `image` within `box` (UVs, origin bottom left, as Blender's pixels), `height` tall."""
    width, full = image.size
    pixels = numpy.empty(width * full * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    u0, v0, u1, v1 = box
    x0, x1, y0, y1 = int(u0 * width), int(u1 * width), int(v0 * full), int(v1 * full)
    part = pixels.reshape(full, width, 4)[y0:y1, x0:x1]
    cropped = bpy.data.images.new(image.name + ".crop", x1 - x0, y1 - y0, alpha=True)
    cropped.pixels.foreach_set(numpy.ascontiguousarray(part).ravel())
    cropped.scale(round(height * (x1 - x0) / (y1 - y0)), height)
    return cropped


def write_textures(preset, data, output, skin_box):
    folders = {
        "head": os.path.join("skins", preset["skin"]) if "skin" in preset else skin_folder(preset),
        "eyes": os.path.join("eyes", "materials", preset["eyes"] + ".mhmat"),
        "eyebrows": os.path.join("eyebrows", preset["eyebrows"]),
        "eyelashes": os.path.join("eyelashes", preset["eyelashes"]),
        "teeth": os.path.join("teeth", "teeth_base"),
        "tongue": os.path.join("tongue", "tongue01"),
        "hair": os.path.join("hair", preset["hair"]),
    }
    for part, (size, alpha) in TEXTURES.items():
        source = os.path.join(data, folders[part])
        material = source if source.endswith(".mhmat") else next(
            os.path.join(source, name) for name in sorted(os.listdir(source)) if name.endswith(".mhmat"))
        image = bpy.data.images.load(diffuse(material))
        if part == "head":
            whole, image = image, crop(image, skin_box, size)
            bpy.data.images.remove(whole)
        else:
            image.scale(size, size)
        if part == "eyes" and preset["eyes"] in IRIS:
            recolour_iris(image, *IRIS[preset["eyes"]])
        if part == "hair" and "hairColour" in preset:
            colour_like(image, preset["hairColour"])
        if part == "eyebrows" and "browColour" in preset:
            colour_like(image, preset["browColour"], contrast=0.6)
        target = os.path.join(output, f"{preset['id']}.{part}.{'png' if alpha else 'jpg'}")
        settings = bpy.context.scene.render.image_settings
        settings.file_format = "PNG" if alpha else "JPEG"
        settings.color_mode = "RGBA" if alpha else "RGB"
        settings.quality = 85
        settings.compression = 90
        image.save_render(target)
        bpy.data.images.remove(image)


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)


def phenotype(preset):
    macro = TargetService.get_default_macro_info_dict()
    macro["gender"] = preset["gender"]
    # MakeHuman's age: 0.5 is 25 years, 1.0 is 90.
    macro["age"] = min(max(0.5 + (preset["age"] - 25) / 65 * 0.5, 0.0), 1.0)
    macro["weight"] = preset["weight"]
    macro["muscle"] = preset["muscle"]
    # MakeHuman's « proportions »: 0.5 is the average body, 1 the idealised one.
    macro["proportions"] = preset.get("proportions", 0.5)
    asian, caucasian, african = preset["race"]
    macro["race"] = {"asian": asian, "caucasian": caucasian, "african": african}
    return macro


def build(preset, data, path):
    human = HumanService.create_human(detailed_helpers=False, macro_detail_dict=phenotype(preset))
    # The face's own features: MakeHuman's modifiers (nose, lips, cheekbones, chin…), by their target's
    # path under MPFB's targets, each with its weight, baked with the morphology.
    for name, weight in preset.get("features", {}).items():
        TargetService.load_target(
            human, LocationService.get_mpfb_data(os.path.join("targets", name + ".target.gz")), weight=weight,
            name="feature-" + name.replace("/", "-"))
    # The morphology (age, gender, origins) arrives as shape keys: baked into the base, so that only the
    # 52 ARKit shapes leave as morph targets.
    TargetService.bake_targets(human)

    parts = []
    for asset_type, folder, name in [
        ("Eyes", "eyes", "high-poly"), ("Eyebrows", "eyebrows", preset["eyebrows"]),
        ("Eyelashes", "eyelashes", preset["eyelashes"]), ("Teeth", "teeth", "teeth_base"),
        ("Tongue", "tongue", "tongue01"), ("Hair", "hair", preset["hair"]),
    ]:
        mhclo = os.path.join(data, folder, name, name + ".mhclo")
        part = HumanService.add_mhclo_asset(
            mhclo, human, asset_type=asset_type, subdiv_levels=0, set_up_rigging=False,
            interpolate_weights=False, import_subrig=False, import_weights=False)
        part.name = f"{preset['id']}.{folder}"
        parts.append(part)

    for shape in SHAPES:
        TargetService.load_target(human, os.path.join(data, "targets", "faceunits", shape + ".target"),
                                  weight=0.0, name=shape)

    # The parts follow the head by refitting, not by shape keys: each shape is refitted once and recorded
    # on them as a shape key of their own.
    keys = human.data.shape_keys.key_blocks
    HumanService.refit(human)
    for part in parts:
        part.shape_key_add(name="Basis", from_mix=False)
    for shape in SHAPES:
        keys[shape].value = 1.0
        HumanService.refit(human)
        recorded = {part.name: [vertex.co.copy() for vertex in part.data.vertices] for part in parts}
        keys[shape].value = 0.0
        HumanService.refit(human)
        for part in parts:
            key = part.shape_key_add(name=shape, from_mix=False)
            for index, position in enumerate(recorded[part.name]):
                key.data[index].co = position

    top = max(vertex.co.z for vertex in human.data.vertices)
    cut = top - HEAD_AND_NECK
    keep_head(human, cut)
    for part in parts:
        cut_below(part, cut - 0.05)
    for modifier in list(human.modifiers):
        human.modifiers.remove(modifier)
    human.name = f"{preset['id']}.head"
    eyes = next(part for part in parts if part.name.endswith(".eyes"))
    hair = next(part for part in parts if part.name.endswith(".hair"))
    tidy_hair(hair, human, eyes, cut)
    keep_seen(human, [human, eyes])
    skin_box = fit_uvs(human)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in [human] + parts:
        if len(obj.data.vertices) > 0:
            obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
        export_materials="NONE", export_texcoords=True, export_normals=True, export_morph=True,
        export_morph_normal=False, export_morph_tangent=False, export_try_sparse_sk=True,
        export_try_omit_sparse_sk=True)
    return skin_box


def keep_head(human, cut):
    """Only the body's own vertices (not the helpers'), above the cut. Shape keys survive bmesh."""
    group = human.vertex_groups["body"].index
    mesh = human.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    deform = bm.verts.layers.deform.active
    doomed = [v for v in bm.verts if group not in v[deform] or v.co.z < cut]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()


def tidy_hair(hair, human, eyes, cut):
    """The hair never covers the face below the brows (a strand of one style crossed it from temple to
    chin), and nothing hangs behind a neck that is no longer there (a ponytail showed under the chin).
    Runs while the head is whole, before keep_seen."""
    world = bmesh.new()
    world.from_mesh(human.data)
    world.transform(human.matrix_world)
    tree = BVHTree.FromBMesh(world)
    back = sum(vertex.co.y for vertex in world.verts) / len(world.verts)
    world.free()
    brows = sum((eyes.matrix_world @ vertex.co).z for vertex in eyes.data.vertices) / len(eyes.data.vertices) + 0.015
    backwards = Vector((0, 1, 0))

    bm = bmesh.new()
    bm.from_mesh(hair.data)
    matrix = hair.matrix_world
    doomed = set()
    crossing = []
    for face in bm.faces:
        centre = matrix @ face.calc_center_median()
        if abs(centre.x) < 0.055 and centre.z < brows and tree.ray_cast(centre, backwards, 0.1)[0] is not None:
            crossing.append(face)
        elif centre.z < cut and centre.y > back:
            doomed.add(face)
    # A strand that crosses the face goes whole when it is a piece of its own: cut at the brows, it left a
    # notch above the eye (Hélène's, Mei's fringes). Part of the cap, only what crosses goes.
    for face in crossing:
        if face in doomed:
            continue
        strand = island(face)
        doomed.update(strand if len(strand) < len(bm.faces) * 0.2 else [face])
    doomed = list(doomed)
    bmesh.ops.delete(bm, geom=doomed, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(hair.data)
    bm.free()
    print(f"TIDY {hair.name}: {len(doomed)} faces removed")


def island(face):
    """The faces joined to `face` by their edges: one strand or card of a hair mesh."""
    seen = {face}
    todo = [face]
    while todo:
        for edge in todo.pop().edges:
            for other in edge.link_faces:
                if other not in seen:
                    seen.add(other)
                    todo.append(other)
    return seen


def keep_seen(obj, occluders):
    """Only the faces seen from somewhere in front: the hologram's light goes through everything, and the
    hidden ones (the inside of the mouth, the orbits behind the eyeballs, the lids' inner side) would show
    through the face. A face is seen when, from its centre, a ray towards one of the VIEWS meets nothing."""
    world = bmesh.new()
    for occluder in occluders:
        mesh = occluder.data.copy()
        mesh.transform(occluder.matrix_world)
        world.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    tree = BVHTree.FromBMesh(world)
    world.free()

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    matrix = obj.matrix_world
    rotation = matrix.to_3x3()
    hidden = []
    for face in bm.faces:
        normal = (rotation @ face.normal).normalized()
        # A millimetre off the face: the centre of a quad that is not flat lies under its own surface where
        # the skin bulges, and a ray from there would hit the face itself.
        origin = matrix @ face.calc_center_median() + normal * 0.001
        seen = any(normal.dot(view) > 0 and tree.ray_cast(origin, view, 1.0)[0] is None for view in VIEWS)
        if not seen:
            hidden.append(face)
    bmesh.ops.delete(bm, geom=hidden, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    print(f"SEEN {obj.name}: {len(hidden)} hidden faces removed")


def cut_below(part, cut):
    mesh = part.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < cut], context="VERTS")
    bm.to_mesh(mesh)
    bm.free()


main()
