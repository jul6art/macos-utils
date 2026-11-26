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
            float4 background;
        };

        // 1. The points: round, larger and brighter towards the rim (the Fresnel light, § 8.2).
        struct PointOut { float4 position [[position]]; float size [[point_size]]; float light; };

        vertex PointOut pointVertex(uint id [[vertex_id]], const device GPUPoint* points [[buffer(0)]],
                                    constant Uniforms& u [[buffer(1)]]) {
            GPUPoint p = points[id];
            float4 world = u.model * float4(p.position.xyz, 1.0);
            float3 n = normalize((u.model * float4(p.normal.xyz, 0.0)).xyz);
            float rim = 1.0 - saturate(n.z);
            // Points turned away (the back of the head, the far side of an eyeball) fade out, as on a
            // surface lit from the front: the cloud reads as a face, not as a tangle.
            float facing = smoothstep(-0.35, 0.15, n.z);
            PointOut out;
            out.position = u.viewProjection * world;
            out.size = max(p.position.w * u.pointScale * (0.75 + 1.1 * rim * rim) * (0.4 + 0.6 * facing), 0.0);
            out.light = p.normal.w * (0.55 + 0.65 * rim * facing) * (0.8 + 0.4 * u.glow) * facing;
            return out;
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
            float4 col = c + halo * (0.8 + 0.6 * u.glow);

            float line = 0.76 + 0.24 * step(0.5, fract(in.position.y / 3.0));
            float bandAt = fract(u.time / 5.0) * 1.4 - 0.2;
            float band = exp(-pow((uv.y - bandAt) * 10.0, 2.0));
            col.rgb *= line * u.flicker;
            col.rgb += u.colour.rgb * band * 0.2 * saturate(col.a);

            if (u.projector > 0.5) {
                float2 p = (in.uv - float2(0.5, 0.94)) * float2(1.0, 4.5);
                float plinth = exp(-pow(length(p) - 0.15, 2.0) * 1200.0) * 0.5 + exp(-dot(p, p) * 25.0) * 0.22;
                float width = mix(0.12, 0.4, saturate((0.94 - in.uv.y) / 0.8));
                float beam = saturate(1.0 - abs(in.uv.x - 0.5) / width) * saturate((in.uv.y - 0.15) / 0.79) * 0.09;
                col.rgb += u.colour.rgb * (plinth + beam);
                col.a = max(col.a, plinth + beam);
            }
            float alpha = saturate(max(col.a, max(col.r, max(col.g, col.b))));
            float3 rgb = col.rgb + u.background.rgb * u.background.a * (1.0 - alpha);
            return float4(rgb, alpha + u.background.a * (1.0 - alpha));
        }
        """
}
