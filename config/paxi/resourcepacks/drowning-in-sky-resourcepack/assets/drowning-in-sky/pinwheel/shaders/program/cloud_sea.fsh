// https://github.com/FoundryMC/Veil/blob/1.21/common/src/main/resources/resourcepacks/fog/assets/veil/pinwheel/shaders/program/height_fog.fsh
// Plane/ray intersection based on the above. I added extra noise

#include veil:fog
#include veil:space_helper

#define FOG_Y 64.99
#define THICKNESS 0.3

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform sampler2D Noise;
uniform float VeilRenderTime;

uniform vec4 FogColor;
//const vec4 FogColor = vec4(0.8, 0.8, 0.8, 1.0);


in vec2 texCoord;

out vec4 fragColor;

struct Plane{
    vec3 position;
    vec3 normal;
};

struct Intersection{
    float t;
    float hit;
    vec3  hitPoint;
};

const Plane PLANE = Plane(vec3(0.0, FOG_Y, 0.0), vec3(0.0, 1.0, 0.0));

void intersectPlane(vec3 ray, Plane p, inout Intersection i) {
    vec3 pos = VeilCamera.CameraPosition + VeilCamera.CameraBobOffset;
    float d = -dot(p.position, p.normal);
    float v = dot(ray, p.normal);
    float t = -(dot(pos, p.normal) + d) / v;
    if (t > 0.0 && t < i.t){
        i.t = t;
        i.hit = 1.0;
        i.hitPoint = pos + vec3(t * ray.x, t * ray.y, t * ray.z);
    }
}

// ===
// Simplex 2D noise
//
vec3 permute(vec3 x) { return mod(((x*34.0)+1.0)*x, 289.0); }

float snoise(vec2 v){
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
           -0.577350269189626, 0.024390243902439);
  vec2 i  = floor(v + dot(v, C.yy) );
  vec2 x0 = v -   i + dot(i, C.xx);
  vec2 i1;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
  + i.x + vec3(0.0, i1.x, 1.0 ));
  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy),
    dot(x12.zw,x12.zw)), 0.0);
  m = m*m ;
  m = m*m ;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
  vec3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}
// ===

float fractalNoise(vec2 v) {
    float oct1 = snoise(v);
    float oct2 = snoise(v * 2) * 0.75;
    float oct3 = snoise(v * 4) * 0.5;
    float oct4 = snoise(v * 8) * 0.25;
    return oct1 + oct2 + oct3 + oct4;
}

void main() {
    vec4 baseColor = texture(DiffuseSampler0, texCoord);
    vec3 viewPos = screenToLocalSpace(texCoord, texture(DiffuseDepthSampler, texCoord).r).xyz;

	vec3 actualCamPos = VeilCamera.CameraPosition + VeilCamera.CameraBobOffset;
    float dist;
	vec3 fogHitPos = actualCamPos;
    if (actualCamPos.y < FOG_Y) {
        dist = length(viewPos);

        Intersection i;
        i.t = length(viewPos);
        intersectPlane(viewDirFromUv(texCoord), PLANE, i);

        if (i.hit != 0) {
            dist = i.t;
			fogHitPos = i.hitPoint;
        }
    } else {
        Intersection i;
        i.t = length(viewPos);
        intersectPlane(viewDirFromUv(texCoord), PLANE, i);
        if (i.hit == 0) {
			// we avoid the fog entirely
            fragColor = baseColor;
            return;
        }

        dist = length(viewPos) - i.t;
		fogHitPos = i.hitPoint;
    }

	// Create some noise by double-sampling the blue noise
    vec2 noisePointDrift = fogHitPos.xz + vec2(sin(VeilRenderTime * 0.1234), sin(VeilRenderTime * 0.1345 + 1));
	float noiseSample = fractalNoise(noisePointDrift/16);
	float noiseA = fractalNoise(vec2(noiseSample + fogHitPos.x * 0.001, noiseSample + fogHitPos.z * 0.002));
    float noiseB = fractalNoise(fogHitPos.zx);
    float noiseC = fractalNoise(vec2(VeilRenderTime * 0.1, 1));
    float allNoise = smoothstep(0.0, 1.0, (noiseA + noiseB + noiseC) / 3.0);
	float noiseAround1 = (allNoise * 0.2 + 1.0);
	
    float distance = dist;//(pos.y - FOG_Y) / FOG_HEIGHT;
    float thickness = clamp(exp(THICKNESS * -distance * noiseAround1), 0.0, 1.0);
    fragColor = mix(FogColor, baseColor, thickness);
}
