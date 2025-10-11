#version 450

#define ITER 48
#define THRESH 4.0

#define ALTERNATE_MAPa

#define MAP_COL(v1, v2, v3) vec3(float(v1) / 255.0, float(v2) / 255.0, float(v3) / 255.0)

layout(location = 0) out vec4 fragColor;
layout(location = 0) in  vec2 texCoord;

layout(binding = 0) uniform FragUniforms {
    mat4  transform;
    vec2  resolution;
    float time;
    float aspect;
} u;

layout(binding = 1) uniform sampler2D main_tex;

vec2 square_complex(in vec2 num) 
{
    return vec2(num.x * num.x - num.y * num.y, 2.0 * num.x * num.y);
}

vec3 vec_interp(vec3 col1, vec3 col2, float val) 
{
    return vec3(col1.x + (col2.x - col1.x) * val, 
        col1.y + (col2.y - col1.y) * val,
        col1.z + (col2.z - col1.z) * val);
}

vec3 grad2(float val) 
{
    const vec3 col1 = MAP_COL(1, 2, 35);
    const vec3 col2 = MAP_COL(240, 55, 215);
    const vec3 col3 = MAP_COL(250, 255, 112);
    
    vec3 bi1 = vec_interp(col1, col2, val);
    vec3 bi2 = vec_interp(col2, col3, val);
    
    vec3 final = vec_interp(bi1, bi2, val); 
    
    return final;
}

float lineDist(vec2 p, vec2 a, vec2 b) 
{
    vec2 pa = p-a, ba = b-a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h );
}

float sdBox( in vec2 p, in vec2 b )
{
    vec2 d = abs(p)-abs(b);
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}

float sdSphere(in vec2 p, vec2 p2, float rad) {
    return length(p - p2) - rad;
}

vec3 fractal(in vec2 pos) 
{
    float t2 = (u.time - 13.0) * 0.1;
    vec2 c = vec2(sin(t2), cos(t2)) * 1.0;
    float zoom = 1.0;//0.02;
    vec2 z = pos * zoom;
    vec2 dz = vec2(0);
    
    vec3 col = vec3(0.0);
    
    int i = 0;
    for (; i < ITER; i++) 
    {
        z = square_complex(z) + c;
        
        float l = dot(z, z);
        
        float w = 1.0 / float(i + 1);
        vec2 uv = 0.5 + 0.5 * normalize(z);
        vec3 tex = texture(main_tex, pos + z).xyz * w;
        
        col += tex;
        //dist = min(sdSphere(pos, vec2(sin(iTime), cos(iTime)), 0.5), min(sdBox(z, vec2(tan(iTime), 0.3)), min(dist, lineDist(z, vec2(sin(iTime)), vec2(fract(iTime) * 2.0, sin(iTime))))));
        if (l > THRESH) 
        {
            break;
        }
    }
    
	float d = sqrt( dot(z,z)/dot(dz,dz) );
    //float sn = log(log(dot(z,z))/(log(64.0)))/log(2.0) * dot(orbit, orbit) / float(ITER);
    float l = float(i) / float(ITER);
    #ifdef ALTERNATE_MAP
    col = texture(main_tex, pos + z).xyz;
    #endif
    return col;
    
    return col * d;
}

vec3 map_col(int v1, int v2, int v3) 
{
    return vec3(float(v1) / 255.0,float(v2) / 255.0,float(v3) / 255.0);
}



void main()
{
    vec2 fragCoord2 = texCoord - u.resolution.xy / 2.0;
    vec2 uv = ((texCoord / u.resolution.xy) - 0.5) * 2.0;

    // Time varying pixel color
    vec3 col = fractal(uv);
    

    // Output to screen
    fragColor = vec4(col,1.0);
}
