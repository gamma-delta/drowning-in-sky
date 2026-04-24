// https://github.com/FoundryMC/Veil/blob/1.21/common/src/main/resources/resourcepacks/fog/assets/veil/pinwheel/shaders/program/height_fog.fsh
// Plane/ray intersection based on the above. I added extra noise

#include veil:fog
#include veil:space_helper

#define FOG_Y 64.95
#define THICKNESS 0.3

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform sampler2D LightmapUV;
uniform float VeilRenderTime;
uniform vec4 FogColor;

const vec4 ShallowFogColor = vec4(0.6, 0.6, 0.62, 0.8);
const vec4 DeepFogColor = vec4(0.7, 0.7, 0.75, 1.0);

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
    vec4 lightColor = texture(LightmapUV, texCoord);
    float skyLight = lightColor.g;
    float blockLight = lightColor.r;
    // fragColor = lightColor; return;
    
    vec4 baseColor = texture(DiffuseSampler0, texCoord);
    vec3 viewPos = screenToLocalSpace(texCoord, texture(DiffuseDepthSampler, texCoord).r).xyz;
    vec3 viewWorldspacePos = screenToWorldSpace(texCoord, texture(DiffuseDepthSampler, texCoord).r).xyz;

	vec3 actualCamPos = VeilCamera.CameraPosition + VeilCamera.CameraBobOffset;

	vec3 fogHitPos = actualCamPos;
    bool didHitFog = false;
    float dist;
    if (actualCamPos.y < FOG_Y) {
        dist = length(viewPos);

        Intersection i;
        i.t = length(dist);
        intersectPlane(viewDirFromUv(texCoord), PLANE, i);

        if (i.hit != 0) {
            dist = i.t;
			fogHitPos = actualCamPos + viewDirFromUv(texCoord) * 0.2;
            didHitFog = true;
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
        didHitFog = true;
    }

    // Noise sample in 2d from the fog hit pos, 3d on the camera hit pos, and 1d on the distance
    vec2 fogHitDrift = fogHitPos.xz + vec2(sin(VeilRenderTime * 0.333), sin(VeilRenderTime * 0.3444 + 1));
    vec3 viewHitDrift = viewWorldspacePos + vec3(sin(VeilRenderTime * 0.2456 + 2), sin(VeilRenderTime * 0.2765 + 3), sin(VeilRenderTime * 0.2123 + 4));
    float fogHitNoise = fractalNoise(fogHitDrift / 11);
    float viewHitXZNoise = fractalNoise(viewHitDrift.xz / 15);
    float viewHitYNoise = fractalNoise(vec2(viewHitDrift.y / 31, 1.234567));
    float thicknessNoise = fractalNoise(vec2(7.89, dist / 33)) * 0.5;
    float allNoise = smoothstep(0.0, 1.0, (fogHitNoise + viewHitXZNoise + viewHitYNoise + thicknessNoise) / (3+0.5));
	float noiseAround1 = (allNoise * 0.8 + 1.0);
	
    float distance = dist;
    if (didHitFog && dist != 0) {
        distance += length(actualCamPos.xyz - viewWorldspacePos.xyz) / 8;
    }
    // Block light makes the fog thinner, with diminishing returns
    float minBrightForFogThin = 8.0;
    float blockLightAdjustRaw = 2 * (blockLight-minBrightForFogThin/16.0);
    float blockLightAdjust = clamp(1.0 + clamp(blockLightAdjustRaw, 0, 1) * 5, 1, 100000);
    // Sky light makes the fog thicker -- skydark makes it thinner
    float skyDarkAdjust = 1 + 10 * max(6.0/16.0 - skyLight, 0);
    float thickness = clamp(
        exp(THICKNESS * -distance * noiseAround1 / blockLightAdjust / skyDarkAdjust),
        0.0, 1.0
    );

    float mcFogColorBrightness = (FogColor.r + FogColor.g + FogColor.b) / 3.0;
    float mcFogColorDodge = mix(0.0, 1.0, mcFogColorBrightness);
    float mcFogColorDodgeBias = 0.7;
    vec4 shallowFogColorDodged = vec4(ShallowFogColor.rgb * (mcFogColorDodgeBias + mcFogColorDodge * (1.0-mcFogColorDodgeBias)), ShallowFogColor.a);
    vec4 deepFogColorNoisy = vec4(clamp(DeepFogColor.rgb - allNoise / 32, 0.0, 1.0), DeepFogColor.a);
    vec4 theFogColor = mix(shallowFogColorDodged, deepFogColorNoisy, smoothstep(1.0, 32.0, distance));
    fragColor = mix(theFogColor, baseColor, thickness);
}
