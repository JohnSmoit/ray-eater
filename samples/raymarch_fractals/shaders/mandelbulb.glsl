#version 450

#define EPSILON    0.001
#define ITERATIONS 48
#define MAX_DIST   80.0

#define PI         3.14159265

//#define NORMALS_ONLY

layout(location = 0) out vec4 fragColor;
layout(location = 0) in  vec2 texCoord;

const vec3 spos = vec3(0.0);

const float sp_radius = 5.0;

layout(binding = 0) uniform FragUniforms {
    mat4  transform;
    vec2  resolution;
    float time;
    float aspect;
} u;

#define TIME (u.time * 0.1)

const vec2 mouse = vec2(0, 0);

const int fractal_iterations = 12;
const float yeet = 4.0;
const float power = 8.0;

vec4 freakyFractal(in vec3 pos) {
    float dr = 1.0;
    float r;
    vec3 o = vec3(1.0);
    vec3 z = pos;

    for (int i = 0; i < fractal_iterations; i++) {
        r = length(z);
        o = min(o, abs(z));

        if (r > yeet) break;

        float theta = acos(z.z / r) + TIME;
        float phi   = atan(z.y, z.x);

        dr = pow(r, power - 1) * power * dr + 1.0;

        float scaled_r = pow(r, power);
        theta = theta * power;
        phi   = phi   * power;

        z = scaled_r * vec3(
            sin(theta) * cos(phi), 
            sin(phi) * sin(theta), 
            cos(theta)
        ) + pos;
    }

    return vec4(0.5 * log(r) * r / max(dr, 1e-6), abs(normalize(o)));
}

vec4 vecScene(in vec3 pos) {
    return freakyFractal(pos);
}

float scene(in vec3 pos) {
    return freakyFractal(pos).x;
}

float march(vec3 o, vec3 dir) {
    float t = 0.0;
    for (int i = 0; i < ITERATIONS; i++) {

        vec3 ray = o + dir * t;
        
        float cd = scene(ray);
        
        t += cd;

        if (cd < EPSILON * t || t > MAX_DIST) {
            break;
        }
    }
    
    return t;
}

vec3 calcNormals(in vec3 pos) {
    const float e = EPSILON;
    const vec2 k = vec2(1, -1) * 0.5773 * e;
    return normalize(
        k.xyy*scene(pos+k.xyy) + 
        k.yyx*scene(pos+k.yyx) +
        k.yxy*scene(pos+k.yxy) +
        k.xxx*scene(pos+k.xxx) );
}

vec3 calcNormals1(in vec3 pos) {
    vec3 eps = vec3(0.001,0.0,0.0);
    return normalize( vec3(
           scene(pos+eps.xyy).x - scene(pos-eps.xyy).x,
           scene(pos+eps.yxy).x - scene(pos-eps.yxy).x,
           scene(pos+eps.yyx).x - scene(pos-eps.yyx).x ) );
}

const vec3 col_c = vec3(1.0, 0.03, 0.82);
const vec3 col_a = vec3(0.1, 1.0, 0.9);
const vec3 col_b = vec3(0.4, 0.05, 0.5);

const vec3 sky_a = vec3(1.0, 0.95, 0.95);
const vec3 sky_b = vec3(0.3, 0.9, 1.0);
const vec3 sky_c = vec3(0.2, 0.2, 0.4);

// Basic ass phong lighting, replace with something fancier
// if you wish
vec3 render(float dist, vec3 pos, vec3 look, vec3 dir, vec3 light) {
    if (dist > MAX_DIST) 
    {
        float sky = pow(dot(dir, vec3(0.0, 1.0, 0.0)), 2.0);
        float sky2 = pow(dot(dir, vec3(0.0, -1.0, 0.0)), 2.0);

        vec3 sky_a = max(mix(sky_a, sky_b, sky), vec3(0.0));
        vec3 sky_b = max(mix(sky_a, sky_c, sky2), vec3(0.0));

        return sky_a + sky_b;
    }
    
    vec3 n = calcNormals(pos);
    vec3 o = vecScene(pos).yzw;
    
    #ifdef NORMALS_ONLY
        return abs(n);
    #endif

    float trapMix = length(o);
    vec3 base = vec3(0.2, 0.9, 1.0);
    vec3 band = 0.25 + 0.5 * cos(6.2831 * (o + 0.2 * o));
    vec3 albedo = mix(col_a, col_b, band);
    
    float dif = max(dot(n, light), 0.0);


    float shine = 32.0;
    vec3 halfa  = normalize(light + look);
    float spa   = max(dot(halfa, n), 0.0);
    float spec  = pow(spa, shine);

    return albedo * dif / dist + albedo * 0.1 / dist + spec * vec3(1) / dist;
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

    float ylook = sin(TIME * 0.5) * 4.0;
    
    float a = mouse.x / u.resolution.x * 2.0 * PI;

    float dist = (sin(TIME) + 1.0) * 0.5 * 4.0 + 1.0;
    
    vec3 pos = vec3(dist * cos(TIME), ylook, dist * sin(TIME));
    vec3 lpos = vec3(dist * cos(TIME * 3.0), ylook, dist * sin(TIME * 3.0));

    vec3 dir = lookat(normalize(vec3(uv, 1.0)), pos, spos);
    vec3 look = lookat(normalize(vec3(uv, 1.0)), pos, spos);
    vec3 light = lookat(normalize(vec3(0.0, 0.0, 1.0)), lpos, spos);
    
    float di = march(pos, dir);
    
    fragColor = vec4(render(di, pos + dir * di, look, dir, light), 1.0);
}
