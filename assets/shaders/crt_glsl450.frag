#version 450
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 outColour;
layout(set = 0, binding = 0) uniform sampler2D sceneTexture;
layout(push_constant) uniform CrtSettings {
    vec2 outputSize;
    float scanlineStrength;
    float maskStrength;
} crt;

void main()
{
    vec3 colour = texture(sceneTexture, uv).rgb;
    float scan = 1.0 - crt.scanlineStrength * (0.5 + 0.5 * sin(uv.y * crt.outputSize.y * 3.14159265));
    float triad = mod(floor(uv.x * crt.outputSize.x), 3.0);
    vec3 mask = triad < 1.0 ? vec3(1.0, 1.0 - crt.maskStrength, 1.0 - crt.maskStrength) :
                (triad < 2.0 ? vec3(1.0 - crt.maskStrength, 1.0, 1.0 - crt.maskStrength) :
                               vec3(1.0 - crt.maskStrength, 1.0 - crt.maskStrength, 1.0));
    outColour = vec4(colour * scan * mask, 1.0);
}



