//color adjustments

vec3 make_green(in vec3 color, in float amount)
{
	color = mix(color,vec3(0.,1.,0.),amount);
	return color;
}


vec3 make_gray(in vec3 color, in float amount)
{
	float average_color = (color.r+color.b+color.g)/3.0;
	color = mix(color, vec3(average_color) ,amount);
	return color;
}