// v1.46: hologram surface for 3D characters (메뉴 → 캐릭터 → 질감 → 홀로그램).
// Fresnel rim glow, fine scanlines, a bright band sweeping upward, and horizontal glitch slices.
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

[[visible]]
void hologramSurface(realitykit::surface_parameters params)
{
    float t = params.uniforms().time();
    float3 wp = params.geometry().world_position();
    float3 n = normalize(params.geometry().normal());
    float3 v = normalize(params.geometry().view_direction());
    float fres = pow(1.0 - saturate(abs(dot(n, v))), 2.2);

    float scan = 0.5 + 0.5 * sin(wp.y * 260.0 - t * 5.0);
    float phase = fract(wp.y * 0.9 - t * 0.3);
    float band = smoothstep(0.0, 0.03, phase) * (1.0 - smoothstep(0.03, 0.09, phase));

    float slice = floor(wp.y * 45.0);
    float glitch = step(0.975, fract(sin(slice * 12.9898 + floor(t * 9.0) * 78.233) * 43758.5453));

    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    constexpr sampler s(filter::linear, address::repeat);
    half3 base = params.textures().base_color().sample(s, uv + float2(glitch * 0.03, 0.0)).rgb;
    float lum = dot(float3(base), float3(0.3, 0.59, 0.11));

    float3 cyan = float3(0.25, 0.92, 1.0);
    float3 col = cyan * (0.2 + 0.95 * lum) + cyan * fres * 1.8 + float3(0.7, 1.0, 1.0) * band * 0.9;
    float flick = 0.92 + 0.08 * sin(t * 41.0) * sin(t * 17.0);
    col *= (0.7 + 0.3 * scan) * flick;

    params.surface().set_base_color(half3(0.0));
    params.surface().set_emissive_color(half3(col));
    float alpha = (0.16 + 0.6 * fres + 0.22 * lum + band * 0.5) * (0.78 + 0.22 * scan) * (1.0 - 0.7 * glitch);
    params.surface().set_opacity(half(saturate(alpha)));
}
