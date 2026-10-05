// v1.48: hologram surface for 3D characters (메뉴 → 캐릭터 → 질감 → 홀로그램).
// Strong Fresnel rim, contour lines, a bright sweep band, height gradient, chromatic split and glitch slices.
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

static float hash11(float p) { return fract(sin(p * 127.1) * 43758.5453); }

[[visible]]
void hologramSurface(realitykit::surface_parameters params)
{
    float t = params.uniforms().time();
    float3 wp = params.geometry().world_position();
    float3 n = normalize(params.geometry().normal());
    float3 v = normalize(params.geometry().view_direction());
    float ndv = saturate(abs(dot(n, v)));
    float fres = pow(1.0 - ndv, 2.6);

    // glitch: whole horizontal slices jump sideways for a frame or two
    float slice = floor(wp.y * 38.0);
    float glitch = step(0.965, hash11(slice + floor(t * 11.0) * 17.0));

    // fine scanlines + wider contour lines that slowly rise
    float scan = 0.5 + 0.5 * sin(wp.y * 520.0 - t * 8.0);
    float contour = smoothstep(0.86, 1.0, 0.5 + 0.5 * sin(wp.y * 140.0 - t * 2.2));
    float phase = fract(wp.y * 0.8 - t * 0.28);
    float band = smoothstep(0.0, 0.025, phase) * (1.0 - smoothstep(0.025, 0.11, phase));

    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    constexpr sampler s(filter::linear, address::repeat);
    auto tex = params.textures().base_color();
    float2 off = float2(glitch * 0.035 + 0.0025, 0.0);
    float r = tex.sample(s, uv + off).r, g = tex.sample(s, uv).g, b = tex.sample(s, uv - off).b;
    float lum = dot(float3(r, g, b), float3(0.3, 0.59, 0.11));

    float h = saturate(wp.y * 0.9);                       // feet → head
    float3 deep = float3(0.05, 0.35, 1.0), cyan = float3(0.3, 0.95, 1.0), white = float3(0.85, 1.0, 1.0);
    // v1.50: dimmer and higher-contrast so the character's own features stay readable
    float detail = pow(lum, 1.35);
    float3 body = mix(cyan, deep, h * 0.6) * (0.05 + 0.75 * detail);
    float3 col = body
               + cyan * fres * 0.9
               + white * band * 0.45
               + cyan * contour * 0.18
               + float3(r - g, 0.0, b - g) * 0.25;         // faint chromatic edge
    float flick = 0.9 + 0.1 * sin(t * 47.0) * sin(t * 13.0);
    col *= (0.72 + 0.28 * scan) * flick;

    params.surface().set_base_color(half3(0.0));
    params.surface().set_emissive_color(half3(col));
    float alpha = (0.22 + 0.45 * fres + 0.45 * detail + band * 0.25 + contour * 0.08) * (0.8 + 0.2 * scan) * (1.0 - 0.75 * glitch);
    params.surface().set_opacity(half(saturate(alpha)));
}
