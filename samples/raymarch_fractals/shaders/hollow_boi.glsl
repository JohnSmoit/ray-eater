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

layout(binding = 1) uniform sampler2D main_tex;

const vec2 mouse = vec2(0, 0);

float sdfSubtract(float d1, float d2) {
    return max(-d2, d1);
}

float sdfSmoothUnion(float d1, float d2, float r) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/r, 0.0, 1.0 );
    return mix( d2, d1, h ) - r*h*(1.0-h);
}

float sdfSmooth(float d, float r) {
    return d - r;
}

vec3 sdfMirrorZ(vec3 pos, float offset) {
    return vec3(pos.xy, abs(pos.z - offset));
}

float cylinder(vec3 p, float h, float r) {
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(r,h);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float sphere(vec3 p, vec3 sp, float r) {
    return length(p - sp) - r;
}


float horns(vec3 pos) {
    vec3 p = pos - vec3(0.0, 0.96, 0.0);
    const float rad = 0.2;

    vec2 wut = vec2(length(p.yz) - 1.0, p.x);
    float donut = length(wut) - rad;
    
    float mid = sphere(pos, vec3(0.0, 1.9, 0.0), 0.6);
    
    return sdfSubtract(donut, mid);
}



float body(vec3 pos) {
    return 0.0;
}



float scene(in vec3 pos) {
    float head_base = sdfSmooth(cylinder(pos, 0.4,0.5), 0.5);
    float eye = sphere(sdfMirrorZ(pos, 0.0), vec3(0.75, 0.0, 0.4), 0.3);
    
    return sdfSmoothUnion( horns(pos), sdfSubtract(head_base, eye), 0.2);
    //return horns(pos);
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

    float dotx = abs(dot(n, vec3(1.0, 0.0, 0.0)));
    float doty = abs(dot(n, vec3(0.0, 1.0, 0.0)));
    float dotz = abs(dot(n, vec3(0.0, 0.0, 1.0)));
    
    vec3 albedo = 
        texture(main_tex, normalize(pos.yz) + vec2(0.5)).rgb * dotx +
        texture(main_tex, normalize(pos.xz) + vec2(0.5)).rgb * doty +
        texture(main_tex, normalize(pos.xy) + vec2(0.5)).rgb * dotz;
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
