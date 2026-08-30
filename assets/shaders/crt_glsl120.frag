// Legacy OpenGL CRT treatment.  Keep the effect subtle enough for CAD line work.
uniform sampler2D sceneTexture;
uniform vec2 outputSize;
uniform float scanlineStrength;
uniform float maskStrength;

void main()
{
    vec2 uv = gl_TexCoord[0].xy;
    vec3 colour = texture2D(sceneTexture, uv).rgb;
    float scan = 1.0 - scanlineStrength * (0.5 + 0.5 * sin(uv.y * outputSize.y * 3.14159265));
    float triad = mod(floor(uv.x * outputSize.x), 3.0);
    vec3 mask = triad < 1.0 ? vec3(1.0, 1.0 - maskStrength, 1.0 - maskStrength) :
                (triad < 2.0 ? vec3(1.0 - maskStrength, 1.0, 1.0 - maskStrength) :
                               vec3(1.0 - maskStrength, 1.0 - maskStrength, 1.0));
    gl_FragColor = vec4(colour * scan * mask, 1.0);
}



