#include <metal_stdlib>
using namespace metal;

struct CrtSettings {
    float2 outputSize;
    float scanlineStrength;
    float maskStrength;
};

fragment float4 waifuCrtFragment(float2 uv [[stage_in]],
                                 texture2d<float> sceneTexture [[texture(0)]],
                                 constant CrtSettings &crt [[buffer(0)]])
{
    constexpr sampler textureSampler(filter::linear);
    float3 colour = sceneTexture.sample(textureSampler, uv).rgb;
    float scan = 1.0 - crt.scanlineStrength * (0.5 + 0.5 * sin(uv.y * crt.outputSize.y * 3.14159265));
    uint triad = uint(floor(uv.x * crt.outputSize.x)) % 3u;
    float3 mask = float3(1.0 - crt.maskStrength);
    mask[triad] = 1.0;
    return float4(colour * scan * mask, 1.0);
}



