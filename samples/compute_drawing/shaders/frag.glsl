#version 450

layout(location = 0) out vec4 fragColor;
layout(location = 0) in vec2 texCoord;

layout(binding = 0) uniform SampleUniforms {
    float time;
    vec2 mouse;
} uniforms;

layout(binding = 1) uniform sampler2D compute_image;

void main() {
   // vec2 ot = vec2(
   //     min(1.0, texCoord.x + sin(uniforms.time)),
   //     min(1.0, texCoord.y + cos(uniforms.time))
   // );

    fragColor = texture(compute_image, texCoord);
}
