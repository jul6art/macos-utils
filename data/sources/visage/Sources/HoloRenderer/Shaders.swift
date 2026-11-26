/// The Metal shaders, as source compiled at launch (`makeLibrary(source:)`): no Metal toolchain from Xcode,
/// no resource bundle to sign (spec, § 10.2).
enum HoloShaders {
    static let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct GPUPoint { float4 position; float4 normal; };
        struct Uniforms {
            float4x4 viewProjection;
            float4x4 model;
            float4 colour;
            float2 viewport;
            float time;
            float glow;
            float flicker;
            float pointScale;
            float glitch;
            float projector;
            float realism;
            float halo;
            float scanlines;
            float4 background;
        };

        // 1. The points: round, larger and brighter towards the rim (the Fresnel light, § 8.2).
        struct PointOut { float4 position [[position]]; float size [[point_size]]; float light; };

        vertex PointOut pointVertex(uint id [[vertex_id]], const device GPUPoint* points [[buffer(0)]],
                                    constant Uniforms& u [[buffer(1)]]) {
            GPUPoint p = points[id];
            float4 world = u.model * float4(p.position.xyz, 1.0);
            float3 n = normalize((u.model * float4(p.normal.xyz, 0.0)).xyz);
            // Tested against the occluders a hair's breadth towards the camera, about 1.5 mm: a point on
            // the skin is not hidden by the skin it sits on.
            float4 tested = world + float4(0.0, 0.0, 0.015, 0.0);
            float rim = 1.0 - saturate(n.z);
            // Points turned away (the back of the head, the far side of an eyeball) fade out, as on a
            // surface lit from the front: the cloud reads as a face, not as a tangle.
            float facing = smoothstep(-0.35, 0.15, n.z);
            PointOut out;
            out.position = u.viewProjection * world;
            out.position.z = (u.viewProjection * tested).z / (u.viewProjection * tested).w * out.position.w;
            out.size = max(p.position.w * u.pointScale * (0.75 + 1.1 * rim * rim) * (0.4 + 0.6 * facing), 0.0);
            out.light = p.normal.w * (0.55 + 0.65 * rim * facing) * (0.8 + 0.4 * u.glow) * facing
                * (1.0 - u.realism);
            return out;
        }

        // 0. What hides: the skin and the eyeballs, into the depth buffer only, from the same points.
        vertex float4 occluderVertex(uint id [[vertex_id]], const device GPUPoint* points [[buffer(0)]],
                                     constant Uniforms& u [[buffer(1)]]) {
            return u.viewProjection * (u.model * float4(points[id].position.xyz, 1.0));
        }

        // 0'. The face as a surface, for the realistic end (§ 8.3): textured, lit by a key light from above
        // and the left, a fill from the right and a rim; tinted like the hologram while it is faint.
        // Invariant: the depth pass and the colour pass must land on exactly the same depth.
        struct SurfaceOut { float4 position [[position, invariant]]; float3 normal; float2 uv; float height; };
        struct SurfaceLook { float shine; float sharpness; float warmth; float opacity; };

        vertex SurfaceOut surfaceVertex(uint id [[vertex_id]], const device GPUPoint* points [[buffer(0)]],
                                        constant Uniforms& u [[buffer(1)]], const device float2* uvs [[buffer(2)]]) {
            SurfaceOut out;
            out.position = u.viewProjection * (u.model * float4(points[id].position.xyz, 1.0));
            out.normal = (u.model * float4(points[id].normal.xyz, 0.0)).xyz;
            out.uv = uvs[id];
            out.height = points[id].position.y;
            return out;
        }

        fragment float4 surfaceFragment(SurfaceOut in [[stage_in]], texture2d<float> albedo [[texture(0)]],
                                        constant Uniforms& u [[buffer(1)]], constant SurfaceLook& look [[buffer(2)]]) {
            constexpr sampler s(filter::linear, mip_filter::linear, address::repeat);
            float4 texel = albedo.sample(s, in.uv);
            if (texel.a < 0.5) discard_fragment();
            float3 n = normalize(in.normal);
            if (n.z < 0.0) n = -n;  // cards and folds are seen from either side
            float3 key = normalize(float3(-0.45, 0.5, 0.75));
            float3 fill = normalize(float3(0.7, 0.05, 0.45));
            float3 albedoLinear = texel.rgb * texel.rgb;
            float wrapped = saturate((dot(n, key) + look.warmth) / (1.0 + look.warmth));
            float3 lit = albedoLinear * (0.2 + 0.95 * wrapped + 0.3 * saturate(dot(n, fill)));
            // Light through the skin: warm where light turns to shade.
            lit += albedoLinear * float3(0.5, 0.12, 0.05) * look.warmth * wrapped * (1.0 - wrapped);
            lit += pow(saturate(dot(n, normalize(key + float3(0.0, 0.0, 1.0)))), look.sharpness) * look.shine;
            lit += pow(1.0 - saturate(n.z), 3.0) * 0.12;
            float3 colour = sqrt(saturate(lit));
            float3 tinted = u.colour.rgb * dot(colour, float3(0.299, 0.587, 0.114)) * 1.4;
            float3 rgb = mix(tinted, colour, smoothstep(0.15, 0.9, u.realism));
            // The neck, cut short, fades out rather than ending on a jagged edge.
            float opacity = look.opacity * smoothstep(-1.3, -0.85, in.height);
            return float4(rgb * opacity, opacity);
        }

        fragment float4 pointFragment(PointOut in [[stage_in]], float2 coord [[point_coord]],
                                      constant Uniforms& u [[buffer(1)]]) {
            float d = length(coord - 0.5) * 2.0;
            if (d > 1.0) discard_fragment();
            float a = smoothstep(1.0, 0.4, d) * in.light;
            return float4(u.colour.rgb * a, a);
        }

        // 2. The hologram: halo, scanlines, the sweeping band, flicker, the rare glitch, the projector.
        struct FullOut { float4 position [[position]]; float2 uv; };

        vertex FullOut fullscreenVertex(uint id [[vertex_id]]) {
            float2 corner = float2((id << 1) & 2, id & 2);
            FullOut out;
            out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
            out.uv = float2(corner.x, 1.0 - corner.y);
            return out;
        }

        static float hash(float n) { return fract(sin(n) * 43758.5453); }

        fragment float4 compositeFragment(FullOut in [[stage_in]], texture2d<float> scene [[texture(0)]],
                                          constant Uniforms& u [[buffer(1)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_zero);
            float2 uv = in.uv;
            float slice = floor(uv.y * 28.0);
            float jump = step(0.75, hash(slice * 7.13 + floor(u.time * 24.0))) * (hash(slice + u.time) - 0.5);
            uv.x += u.glitch * jump * 0.06;
            float4 c = scene.sample(s, uv);
            if (u.glitch > 0.01) {
                c.r = scene.sample(s, uv + float2(0.007 * u.glitch, 0.0)).r;
                c.b = scene.sample(s, uv - float2(0.007 * u.glitch, 0.0)).b;
            }
            float4 halo = float4(0.0);
            float2 texel = 1.0 / u.viewport;
            for (int k = 0; k < 12; k++) {
                float angle = float(k) * 0.5236;
                float2 direction = float2(cos(angle), sin(angle));
                halo += scene.sample(s, uv + direction * texel * 5.0);
                halo += scene.sample(s, uv + direction * texel * 13.0) * 0.6;
            }
            halo /= 19.2;
            // The hologram's layers fade as the face becomes real (§ 8.3).
            float hologram = 1.0 - u.realism;
            float4 col = c + halo * (0.8 + 0.6 * u.glow) * hologram * u.halo;

            float line = mix(1.0, 0.76 + 0.24 * step(0.5, fract(in.position.y / 3.0)), hologram * u.scanlines);
            float bandAt = fract(u.time / 5.0) * 1.4 - 0.2;
            float band = exp(-pow((uv.y - bandAt) * 10.0, 2.0));
            col.rgb *= line * mix(1.0, u.flicker, hologram);
            col.rgb += u.colour.rgb * band * 0.2 * saturate(col.a) * hologram * u.scanlines;

            if (u.projector > 0.5 && hologram > 0.0) {
                float2 p = (in.uv - float2(0.5, 0.94)) * float2(1.0, 4.5);
                float plinth = exp(-pow(length(p) - 0.15, 2.0) * 1200.0) * 0.5 + exp(-dot(p, p) * 25.0) * 0.22;
                float width = mix(0.12, 0.4, saturate((0.94 - in.uv.y) / 0.8));
                float beam = saturate(1.0 - abs(in.uv.x - 0.5) / width) * saturate((in.uv.y - 0.15) / 0.79) * 0.09;
                col.rgb += u.colour.rgb * (plinth + beam) * hologram;
                col.a = max(col.a, (plinth + beam) * hologram);
            }
            float alpha = saturate(max(col.a, max(col.r, max(col.g, col.b))));
            float3 rgb = col.rgb + u.background.rgb * u.background.a * (1.0 - alpha);
            return float4(rgb, alpha + u.background.a * (1.0 - alpha));
        }
        """
}
