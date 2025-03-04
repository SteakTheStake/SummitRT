#version 120

#include "/settings.glsl"


uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
	vec4 color = texture2D(texture, texcoord) * glcolor;

	#if GREEN_CLOUDS == 1
		color.rgb = vec3(0.,1.,0.);
	#endif
	
	

/* DRAWBUFFERS:0 */
	gl_FragData[0] = color; //gcolor
}