#version 450

#define EPSILON    0.0001
#define ITERATIONS 256
#define MAX_DIST   1000.0

#define PI         3.14159265

//#define NORMALS_ONLY

layout(location = 0) out vec4 fragColor;
layout(location = 0) in  vec2 texCoord;

const vec3 spos = vec3(0.0);
const vec3 light = normalize(vec3(1.0, 0.4, 2.3));

const float sp_radius = 5.0;

layout(binding = 0) uniform FragUniforms {
    mat4  transform;
    vec2  resolution;
    float time;
    float aspect;
} u;

const vec2 mouse = vec2(0, 0);


float scene(in vec3 pos) {
    return length(pos) - 0.5;
}



float march(vec3 o, vec3 dir) {
    float t = 0.0;
    for (int i = 0; i < ITERATIONS; i++) {
        vec3 ray = o + dir * t;
        
        float cd = scene(ray);
        
        t += cd;
        
        if (t <= EPSILON || t > MAX_DIST) {
            break;
        }
    }
    
    return t;
}

vec3 calcNormals(in vec3 pos) {
    const float e = 0.0005;
    const vec2 k = vec2(1, -1) * 0.5773 * e;
    return normalize(
        k.xyy*scene(pos+k.xyy) + 
        k.yyx*scene(pos+k.yyx) +
        k.yxy*scene(pos+k.yxy) +
        k.xxx*scene(pos+k.xxx) );
}


vec3 render(float dist, vec3 pos) {
    if (dist > MAX_DIST) return vec3(0.0);
    
    vec3 n = calcNormals(pos);
    
    #ifdef NORMALS_ONLY
        return abs(n);
    #endif
    
    float dif = 0.9 * clamp(dot(light, n), 0.0, 1.0);
    
    vec3 albedo = vec3(1.0);
    vec3 ambient = vec3(0.1);
    return albedo * dif + ambient;
}

// check to make sure y is represented in the correct coordinate space
vec3 lookat(vec3 orig, vec3 eye, vec3 pos) {
    const vec3 world_up = vec3(0.0, 1.0, 0.0);
    
    vec3 z = normalize(pos - eye);
    vec3 x = normalize(cross(z, world_up));
    vec3 y = normalize(cross(x, z));
    
    mat3 look = mat3(x, y, z);
    
    return orig * look;
}

void main() {
    // Normalized screen coordinates (from -1 to 1)
    // quite helpful for figuring out ray direction without doing an explicit
    // perspective projection
    vec2 uv = (texCoord - 0.5 * u.resolution.xy)/u.resolution.y;

    // adjust for vulkan
    uv.y = -uv.y * u.aspect;

    float ylook = 0.0; //4.0 * (iMouse.y - 0.5 * iResolution.y)/iResolution.y;
    
    float a = mouse.x / u.resolution.x * 2.0 * PI;
    
    vec3 pos = vec3(4.0 * cos(a), ylook, 4.0 * sin(a));
    vec3 dir = lookat(normalize(vec3(uv, 1.0)), pos, spos);
    
    float dist = march(pos, dir);
    
    fragColor = vec4(render(dist, pos + dir * dist), 1.0);
}
