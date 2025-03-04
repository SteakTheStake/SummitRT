#version 120

attribute vec4 mc_Entity;
attribute vec3 at_midBlock;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;


out vec2 texcoord;
out vec4 glcolor;

const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;
const bool shadowcolor0Nearest = true;


#ifndef MC_GL_RENDERER_RADEON
    layout(location = 0) in vec4 inPosition;
    layout(location = 2) in vec4 inNormal;
#else
    vec4 inPosition = gl_Vertex;
    vec3 inNormal = gl_Normal;
#endif

uniform mat4 shadowModelViewInverse;
attribute vec4 mc_Entity;

out vec3 n;
out vec3 wPos;
flat out int id;
#include "/distort.glsl"

void main() {
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;

   	wPos = (shadowModelViewInverse * (gl_ModelViewMatrix * inPosition)).xyz;
	  n = mat3(shadowModelViewInverse) * gl_NormalMatrix * inNormal.xyz;
	  id = int(mc_Entity.x);

	#ifdef EXCLUDE_FOLIAGE
		if (mc_Entity.x == 10000.0) {
			gl_Position = vec4(10.0);
		}
		else {
	#endif
			gl_Position = ftransform();
			gl_Position.xyz = distort(gl_Position.xyz);
	#ifdef EXCLUDE_FOLIAGE
		}
	#endif
}