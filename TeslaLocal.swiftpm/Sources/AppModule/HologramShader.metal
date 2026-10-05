// v1.53: Tripo-style hologram (메뉴 → 캐릭터 → 질감 → 홀로그램).
// Dark see-through body, bright cyan-white rim and mesh-like grid lines, slow scan band, glitch slices,
// and a bottom-to-top materialise effect driven by custom.x (reveal height in world metres; ≥ 9 = fully shown).
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

static float hash11(float p) { return fract(sin(p * 127.1) * 43758.5453); }

[[visible]]
void hologramSurface(realitykit::surface_parameters params)
{
    float t = params.uniforms().time();
    float reveal = params.uniforms().custom_parameter().x;
    float3 wp = params.geometry().world_position();
    float3 n = normalize(params.geometry().normal());
    float3 v = normalize(params.geometry().view_direction());
    float ndv = saturate(abs(dot(n, v)));
    float fres = pow(1.0 - ndv, 2.2);

    // materialise: nothing above the reveal front, a hot white line at the front, sparkle just below it
    float above = step(reveal, wp.y);
    float front = 1.0 - smoothstep(0.0, 0.035, abs(wp.y - reveal));
    float sparkle = step(0.82, hash11(floor(wp.x * 180.0) + floor(wp.y * 180.0) * 7.0 + floor(t * 24.0))) * (1.0 - smoothstep(0.0, 0.18, reveal - wp.y));

    float slice = floor(wp.y * 38.0);
    float glitch = step(0.975, hash11(slice + floor(t * 9.0) * 17.0));

    float scan = 0.5 + 0.5 * sin(wp.y * 520.0 - t * 8.0);
    float phase = fract(wp.y * 0.6 - t * 0.22);
    float band = smoothstep(0.0, 0.02, phase) * (1.0 - smoothstep(0.02, 0.09, phase));

    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    constexpr sampler s(filter::linear, address::repeat);
    auto tex = params.textures().base_color();
    float2 off = float2(glitch * 0.03 + 0.002, 0.0);
    float r = tex.sample(s, uv + off).r, g = tex.sample(s, uv).g, b = tex.sample(s, uv - off).b;
    float lum = dot(float3(r, g, b), float3(0.3, 0.59, 0.11));

    // mesh-like lines: thin grid in UV space + world-space horizontal contours
    float2 gq = abs(fract(uv * 48.0) - 0.5);
    float grid = 1.0 - smoothstep(0.0, 0.06, min(0.5 - gq.x, 0.5 - gq.y));
    float contour = 1.0 - smoothstep(0.0, 0.08, abs(fract(wp.y * 60.0) - 0.5) * 2.0 - 0.9);
    contour = saturate(contour);

    float3 teal = float3(0.12, 0.85, 0.78), cyan = float3(0.35, 1.0, 0.95), white = float3(0.9, 1.0, 1.0);
    // v1.53: much darker interior so the silhouette and features read; light comes from edges and lines
    float detail = pow(lum, 1.6);
    float3 body = teal * (0.015 + 0.28 * detail);
    float3 col = body
               + cyan * fres * 1.1
               + cyan * grid * (0.12 + 0.25 * fres)
               + teal * contour * 0.06
               + white * band * 0.22
               + white * front * 1.6
               + cyan * sparkle * 0.9;
    float flick = 0.94 + 0.06 * sin(t * 47.0) * sin(t * 13.0);
    col *= (0.82 + 0.18 * scan) * flick;

    params.surface().set_base_color(half3(0.0));
    params.surface().set_emissive_color(half3(col));
    float alpha = (0.10 + 0.70 * fres + 0.22 * detail + grid * 0.18 + band * 0.12 + front + sparkle * 0.6)
                * (0.85 + 0.15 * scan) * (1.0 - 0.7 * glitch) * (1.0 - above);
    params.surface().set_opacity(half(saturate(alpha)));
}
