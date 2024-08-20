shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled;

uniform float lightEnergMultipl;
uniform float Absorption = 1.0;
uniform vec3 BoundsMin;
uniform vec3 BoundsMax;
uniform float CloudTransparencyParam;
uniform float Scatter_g;
uniform float timeAffect;
uniform sampler2D CloudNoiseTexture;
uniform float FOV;


group_uniforms StepParameters;
uniform float SampleSteps;
uniform float AdjustStepColor;


group_uniforms BuiltinTextures;
uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture;


group_uniforms Light;
uniform vec3 WorldLightPosition;
uniform vec3 WorldLightDir;
uniform int lightSteps;
uniform vec3 lightColor : source_color;


varying float distTravelled;
varying float totalDL;
varying bool rayHitBox;
varying vec3 original_color;
varying float theDensity;
varying vec3 rayPOS;
varying float HGAngle;
varying float totalEnergy;
varying float distLimit;
varying float StepSize;
varying float lastDepth;
varying vec4 view;
varying vec3 ndc;
varying float depth;
varying vec2 RayBoxInfo;
varying vec3 RayDirection;
varying vec3 RayOrigin;


float SampleDensity(vec3 pos) {
	vec2 uv = pos.xz * 0.013 + (TIME*timeAffect) * 0.01;
	vec4 shape = texture(CloudNoiseTexture, uv);
	float density = max(0, shape.r);
	return density;
}


vec2 RayBoxDist(vec3 boundsMin, vec3 boundsMax, vec3 rayO, vec3 rayD) {
	vec3 t0 = (boundsMin - rayO) / rayD;
	vec3 t1 = (boundsMax - rayO) / rayD;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	
	float distA = max(max(tmin.x, tmin.y), tmin.z);
	float distB = min(tmax.x, min(tmax.y, tmax.z));
	
	float distToBox = max(0, distA);
	float distInsideBox = max(0, distB - distToBox);
	return vec2(distToBox, distInsideBox);
}


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float Beer_Powder(float dist, float dens) {
	return ((exp(-dist*dens)) * (1.0 - exp(-dist*dens * 2.0)));
}

float PreCHenyeyGreenstein(float g, float costh){
	float gT = g*g;
	return 0.0796 * ((1.0 - gT) / pow(1.0 + gT - 2.0*g*costh, 1.5));
}

float HGPhase(float C, float angle, float K) {
	return mix(PreCHenyeyGreenstein(-C, angle), PreCHenyeyGreenstein(C, angle), K);
}


vec3 get_camera_direction(vec2 uv, vec2 viewport_size, mat4 inv_view_matrix) {
	vec2 normalized_uv = uv * 2. - 1.;
	vec2 resolution = 1. / viewport_size;
	float aspect_ratio = resolution.y / resolution.x;
	float tan_half_fov = tan(radians(FOV) * .5);
	
	vec3 dir_view = normalize(vec3(normalized_uv.x * aspect_ratio * tan_half_fov, normalized_uv.y * tan_half_fov, -1.0));
	vec4 dir_world = inv_view_matrix * vec4(dir_view, 0.0);

	return normalize(dir_world.xyz);
}

float LightCalc(float dist, float density, float angle) {
	float Energy = Beer_Powder(dist, density) * HGPhase(Scatter_g*0.2, angle, 1.0) * Absorption;
	return Energy;
}


void fragment() {
	RayOrigin = CAMERA_POSITION_WORLD;
	RayDirection = get_camera_direction(UV, VIEWPORT_SIZE, INV_VIEW_MATRIX);
	
	RayBoxInfo = RayBoxDist(BoundsMin, BoundsMax, RayOrigin, RayDirection);
	
	depth = texture(depth_texture, SCREEN_UV).x;
	ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	lastDepth = -view.z;
	
	StepSize = RayBoxInfo.y/SampleSteps;
	distTravelled = 0.0;
	
	distLimit = min(lastDepth - RayBoxInfo.x, RayBoxInfo.y);
	totalEnergy = 0.0;
	totalDL = 0.0;
	
	HGAngle = dot(RayDirection, WorldLightPosition);
	
	while (distTravelled < distLimit ) {
		rayPOS = RayOrigin + RayDirection * (RayBoxInfo.x + distTravelled);
		theDensity = SampleDensity(rayPOS);
		
		for (int Lstep = 0; Lstep < lightSteps; Lstep ++) {
			rayPOS += WorldLightDir * StepSize;
			totalDL += max(0, SampleDensity(rayPOS) * StepSize) * 0.036;
		}
		
		
		theDensity += totalDL;
		totalEnergy += LightCalc(distTravelled*CloudTransparencyParam, theDensity, HGAngle)*lightEnergMultipl;
		distTravelled += StepSize;
	}

	original_color = texture(screen_texture, SCREEN_UV).rgb;
	ALBEDO = original_color;
	
	rayHitBox = RayBoxInfo.y > 0.0 && RayBoxInfo.x < lastDepth;
	if (rayHitBox) {
		ALBEDO = original_color + (totalEnergy*AdjustStepColor) * lightColor;
		
	}
}
