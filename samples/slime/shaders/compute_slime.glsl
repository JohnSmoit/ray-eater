#version 450


struct Particle {
    vec4 position;
};

//TODO: Implement PUSH constants NOW
layout(binding = 0) uniform UniformBuffer {
    vec3 col;
    uint res_x;
    uint res_y;
    uint particle_count;
    uint pixels_rad;
} uniforms;

// buffer of particles
layout(std140, binding = 1) buffer ParticlesBuffer{
    Particle particles[];
} agents;

//TODO: Needs new descriptor type: Storage image
layout(rgba8_snorm, binding = 2) uniform writeonly image2D render_target;

layout(local_size_x = 8, local_size_y = 8) in;

// just write the particles positions to an render_target image I guess...
void main() {
    if (gl_GlobalInvocationID.x > uniforms.particle_count)
        return;

    ivec2 pos = ivec2(
        int(agents.particles[gl_GlobalInvocationID.x].position.x),
        int(agents.particles[gl_GlobalInvocationID.x].position.y)
    );

    ivec2 xb = ivec2(
        max(0, pos.x - uniforms.pixels_rad),
        min(uniforms.res_x, pos.x + uniforms.pixels_rad)
    );
    ivec2 yb = ivec2(
        max(0, pos.y - uniforms.pixels_rad),
        min(uniforms.res_y, pos.y + uniforms.pixels_rad)
    );

    for (int x = xb.x; x < xb.y; x++) {
        for (int y = yb.x; y < yb.y; y++) {
            imageStore(render_target, ivec2(x, y), vec4(uniforms.col, 1.0));
        }
    }
}
