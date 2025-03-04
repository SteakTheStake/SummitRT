#version 120

#define DRAW_SHADOW_MAP gcolor //Configures which buffer to draw to the screen [gcolor shadowcolor0 shadowtex0 shadowtex1]

#include "/settings.glsl"
#include "/lib/color_adjustments.glsl"

uniform float frameTimeCounter;
uniform sampler2D gcolor;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

varying vec2 texcoord;





void main() {
	vec3 color = texture2D(DRAW_SHADOW_MAP, texcoord).rgb;
	

	color = mix(color,vec3(0.,0.,1.),BLUE_AMOUNT);
	//comment just for you
	
	//call our functon
	color = make_green(color, GREEN_AMOUNT );
	
	//greyscale
	//float average_color = (color.r+color.b+color.g)/3.0;
	//color = mix(color, vec3(average_color) ,GRAY_AMOUNT);
	
	
	color = make_gray(color, GRAY_AMOUNT );
	
	

/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(color, 1.0); //gcolor
}