#version 450

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 texCoord;

layout(location = 0) out vec4 outColor;

layout (binding = 1) uniform sampler2D tex;

const float LINE_WIDTH = 0.1;

void main() {
    float lw = LINE_WIDTH * 0.5;
    float upper = 1.0 - lw;

    if (texCoord.x <= lw || texCoord.x > upper || texCoord.y <= lw || texCoord.y > upper) {
        outColor = vec4(1.0);
    } else {
        outColor = texture(tex, texCoord) * vec4(fragColor, 1.0);
    }
}
