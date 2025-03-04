#version 120

uniform sampler2D lightmap;
uniform sampler2D texture;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;


flat in vec4 voxData;

#ifndef MC_GL_RENDERER_RADEON
  /* RENDERTARGETS: 0,1 */
    layout (location = 0) out vec4 shadowcolor0;
    layout (location = 1) out vec4 shadowPos0;
#endif
#ifdef MC_GL_RENDERER_RADEON
    vec4 shadowcolor0;
#endif

void main() {
	vec4 color = texture2D(texture, texcoord) * glcolor;

	gl_FragData[0] = color;
	shadowcolor0 = voxData;
    
    #ifdef MC_GL_RENDERER_RADEON
        gl_FragData[0] = shadowcolor0;
    #endif
}