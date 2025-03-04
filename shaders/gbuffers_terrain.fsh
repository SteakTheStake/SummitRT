#version 120

#include "/settings.glsl"
#include "/lib/color_adjustments.glsl"


#define COLORED_SHADOWS 1 //0: Stained glass will cast ordinary shadows. 1: Stained glass will cast colored shadows. 2: Stained glass will not cast any shadows. [0 1 2]
#define SHADOW_BRIGHTNESS 0.75 //Light levels are multiplied by this number when the surface is in shadows [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]

uniform sampler2D lightmap;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D texture;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec4 shadowPos;

//fix artifacts when colored shadows are enabled
const bool shadowcolor0Nearest = true;
const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;

//only using this include for shadowMapResolution,
//since that has to be declared in the fragment stage in order to do anything.
#include "/distort.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform int frameCounter;
uniform float frameTimeCounter;
uniform float frameTime;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 sunPosition;
uniform int worldTime;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform sampler2D colormap;
uniform float alphaTestRef = 0.1;
uniform sampler2D normals;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 tangent;
in vec3 bitangent;
in float directalTangent;
in float BlockData;

const int MAX_STEPS = 100;
const float MAX_DISTANCE = 100.0;
const float SURFACE_DIST = 0.01;

mat3 tbnNormalTangent(vec3 normal, vec3 tangent,vec3 bitangent) {
    return mat3(normalize(tangent),bitangent,normalize(normal));
}

/* RENDERTARGETS: 0,1,10 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 Normals;
layout(location = 2) out vec4 DataBuffer;

void main() {
	vec4 color = texture2D(texture, texcoord) * glcolor;
	vec2 lm = lmcoord;
	vec3 Normal = normal;
	vec3 colorm = texture(colormap,texcoord).rgb;
    vec4 NormalTextures = texture(normals,texcoord);
 	   NormalTextures.xy = NormalTextures.xy*2.0f - 1.0f;
       float z = sqrt(1.0 - clamp(dot(NormalTextures.xy, NormalTextures.xy),0,1));
	    
	   vec3 NormalData = normalize(vec3(NormalTextures.xy,z));
        float ddt1ee = abs(dot(gbufferModelViewInverse[2].xyz,normal));
	
		
		mat3 tbN_0 = tbnNormalTangent(mat3(gbufferModelViewInverse) * normal, mat3(gbufferModelViewInverse) *  tangent, mat3(gbufferModelViewInverse) * bitangent);
        Normal = tbN_0 * NormalData;  
	if (shadowPos.w > 0.0) {
		//surface is facing towards shadowLightPosition
		#if COLORED_SHADOWS == 0
			//for normal shadows, only consider the closest thing to the sun,
			//regardless of whether or not it's opaque.
			if (texture2D(shadowtex0, shadowPos.xy).r < shadowPos.z) {
		#else
			//for invisible and colored shadows, first check the closest OPAQUE thing to the sun.
			if (texture2D(shadowtex1, shadowPos.xy).r < shadowPos.z) {
		#endif
			//surface is in shadows. reduce light level.
			lm.y *= SHADOW_BRIGHTNESS;
		}
		else {
			//surface is in direct sunlight. increase light level.
			lm.y = mix(31.0 / 32.0 * SHADOW_BRIGHTNESS, 31.0 / 32.0, sqrt(shadowPos.w));
			#if COLORED_SHADOWS == 1
				//when colored shadows are enabled and there's nothing OPAQUE between us and the sun,
				//perform a 2nd check to see if there's anything translucent between us and the sun.
				if (texture2D(shadowtex0, shadowPos.xy).r < shadowPos.z) {
					//surface has translucent object between it and the sun. modify its color.
					//if the block light is high, modify the color less.
					vec4 shadowLightColor = texture2D(shadowcolor0, shadowPos.xy);
					//make colors more intense when the shadow light color is more opaque.
					shadowLightColor.rgb = mix(vec3(1.0), shadowLightColor.rgb, shadowLightColor.a);
					//also make colors less intense when the block light level is high.
					shadowLightColor.rgb = mix(shadowLightColor.rgb, vec3(1.0), lm.x);
					//apply the color.
					color.rgb *= shadowLightColor.rgb;
				}
			#endif
		}
	}
	color *= texture2D(lightmap, lm);

	//greyscale
	color.rgb = make_gray(color.rgb, TERRAIN_GRAY_AMOUNT );

/* DRAWBUFFERS:0 */
	gl_FragData[0] = color; //gcolor

	DataBuffer = vec4(BlockData,0,0,1);
	Normals = vec4(Normal/2.0f + 0.5f,1.0f);
	color = texture(gtexture, texcoord) * glcolor;
//color *= texture(lightmap, lmcoord);
	//color.xyz = colorm.xyz;
	if (color.a < alphaTestRef) {
		discard;
	}