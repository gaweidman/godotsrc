shader_type spatial;

uniform sampler2D albedo;
uniform sampler2D bump_map;

uniform samplerCube env_map;

uniform vec3 color2 : source_color = vec3(1.0);

uniform bool half_lambert = false;
uniform bool allow_albedo_modulation = true;

group_uniforms detail;
uniform sampler2D detail;

group_uniforms phong;
uniform bool albedo_alpha_phong_mask = false;
uniform bool phong = true;
uniform bool phong_albedo_tint = false;
uniform bool invert_phong_mask = false;
uniform sampler2D phong_exponent_texture;
uniform vec3 phong_tint : source_color = vec3(1.0);
uniform vec3 phong_fresnel_ranges = vec3(0, 0.5, 1);
uniform float phong_exponent : hint_range(0.0, 255.0) = 0.0;
uniform float phong_boost = 1.0;
uniform float phong_exponent_factor = 1.0;

group_uniforms self_illum;
uniform bool self_illum = false;
uniform vec3 self_illum_tint : source_color = vec3(1.0);
uniform sampler2D self_illum_mask;

group_uniforms emissive_blend;
uniform bool emissive_blend = false;
uniform float emissive_blend_strength = 1.0;
uniform vec2 emissive_blend_scroll_vector;
uniform vec3 emissive_blend_tint : source_color = vec3(1.0);
uniform sampler2D emissive_blend_base_texture;
uniform sampler2D emissive_blend_texture;
uniform sampler2D emissive_blend_flow_texture;

group_uniforms rimlight;
uniform bool rimlight = false;
uniform float rimlight_mask; // TODO
uniform float rimlight_exponent : hint_range(0.0, 255.0) = 5.0;
uniform float rimlight_boost = 1.0;

vec3 antinormalize(vec3 val) {
	return val * 2.0 - vec3(1.0);
}

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	ALBEDO = texture(albedo, UV).xyz;
	
	if (allow_albedo_modulation) { 
		ALBEDO *= color2;
	}
	
	if (self_illum) {
		EMISSION += texture(self_illum_mask, UV).xyz * self_illum_tint;
	}
	
	//ALBEDO = vec3(texture(phong_exponent_texture, UV).r);
}

float clamp_0to1(float val) {
	return clamp(val, 0.0, 1.0);
}

float calc_fresnel_term( vec3 normal, vec3 view_dir, float exponent, float boost) {
	float fresnel_term = 1.0 - clamp_0to1(dot( normal, view_dir ));
	return boost * pow(fresnel_term, exponent);
}

float fresnel(vec3 normal, vec3 view_dir, float exponent, float boost, vec3 ranges) {
	float result, f = calc_fresnel_term( normal, view_dir, exponent, boost );
	if ( f > 0.5 )
		result = mix( ranges.y, ranges.z, (2.0 * f) - 1.0);
	else
        result = mix( ranges.x, ranges.y, 2.0 * f );

	return result;
}

void light() {
	vec4 normal_texel = texture(bump_map, UV);
	vec3 modified_normal = antinormalize(normalize(NORMAL + normal_texel.xyz));
	float lambert_term = clamp_0to1(dot(NORMAL, LIGHT));
	float diffuse_strength = 0.0;
	
	if (half_lambert)
		diffuse_strength = clamp_0to1(lambert_term * 0.5 + 0.5);
	else
		diffuse_strength = lambert_term;
	
	DIFFUSE_LIGHT += diffuse_strength * LIGHT_COLOR * ATTENUATION * LIGHT_AREA_DIFFUSE_MULTIPLIER / PI;
	
	if (phong) {
		vec3 reflection = normalize(reflect(LIGHT, NORMAL));

		// $phongexponent overrides $phongexponentmap in the source engine, so we replicate that here
		bool phong_exponent_override = phong_exponent > 0.0;
		
		vec4 phong_exp_pixel = texture(phong_exponent_texture, UV);
		
		float phong_dot_term = clamp_0to1(dot(reflection, -VIEW));
		float texel_phong_exp;
		float phong_strength;
		if (phong_exponent_override) {
			texel_phong_exp = phong_exponent * phong_exponent_factor;
			phong_strength = phong_boost * pow(phong_dot_term, texel_phong_exp);
		} else {
			// the red channel stores the phong exponent
			float phong_mask = phong_exp_pixel.r * 255.0;
			
			if (albedo_alpha_phong_mask)
				phong_mask = texture(albedo, UV).a;
			
			if (invert_phong_mask)
				texel_phong_exp = (1.0 - phong_mask) * phong_exponent_factor;
			else
				texel_phong_exp = phong_mask * phong_exponent_factor;
				
			phong_strength = phong_boost * pow(phong_dot_term, texel_phong_exp);
			
		}
		
		if (phong_albedo_tint) {
			vec3 tint = mix(ALBEDO, vec3(1.0), phong_exp_pixel.g);
			DIFFUSE_LIGHT += phong_strength * tint *
				LIGHT_COLOR * ATTENUATION * LIGHT_AREA_DIFFUSE_MULTIPLIER / PI;
		} else {
			DIFFUSE_LIGHT += phong_strength * phong_tint * 
				LIGHT_COLOR * ATTENUATION * LIGHT_AREA_DIFFUSE_MULTIPLIER / PI;
		}
		
		if (rimlight) {
			float fresnel_term = fresnel(NORMAL, VIEW, rimlight_exponent, rimlight_boost, phong_fresnel_ranges);
			float light_contribution = clamp_0to1(dot(LIGHT, -VIEW));
			
			DIFFUSE_LIGHT += fresnel_term * phong_exp_pixel.a * phong_tint * 
				LIGHT_COLOR * ATTENUATION / PI;
		}
	}
	
	//DIFFUSE_LIGHT = vec3(1.0);
}
