//pref
overAlpha|float|0.0|0.8|2.0|Ability to see overlay images added to background
//frag
uniform  float overAlpha = 0.8;
uniform float ambient = 1.0;
uniform float diffuse = 0.3;
uniform float specular = 0.25;
uniform float shininess = 10.0;

		
void main() {
	#ifdef BETTER_BUT_SLOWER
	textureSz = textureSize(intensityVol, 0);
	#endif
    vec3 start = TexCoord1.xyz;
	vec3 backPosition = GetBackPosition(start);
	vec3 dir = backPosition - start;
	float len = length(dir);
	dir = normalize(dir);
	vec4 deltaDir = vec4(dir.xyz * stepSize, stepSize);
	vec4 gradSample, colorSample;
	float bgNearest = len; //assume no hit
	float overFarthest = len;
	vec4 colAcc = vec4(0.0,0.0,0.0,0.0);
	vec4 prevGrad = vec4(0.0,0.0,0.0,0.0);
	vec4 samplePos;
	//background pass
	samplePos = vec4(start.xyz +deltaDir.xyz* (fract(sin(gl_FragCoord.x * 12.9898 + gl_FragCoord.y * 78.233) * 43758.5453)), 0.0);
	vec4 clipPos = applyClip(dir, samplePos, len);
	float stepSizeX2 = samplePos.a + (stepSize * 2.0);
	//fast pass - optional
	fastPass (len, dir, intensityVol, samplePos);
	if ((samplePos.a > len) && ( overlays < 1 )) { //no hit: quit here
		FragColor = colAcc;
		return;		
	}
	if (samplePos.a < clipPos.a)
		samplePos = clipPos;
	//end fastpass - optional	vec3 defaultDiffuse = vec3(0.5, 0.5, 0.5);
	vec4 gradMax = colAcc;
	if ( overlays < 1 ) { //pass without overlays
		while (samplePos.a <= len) {
			colorSample = texture3D(intensityVol,samplePos.xyz);
			if (colorSample.a > colAcc.a)
				colAcc = colorSample;
			samplePos += deltaDir;
		} //while samplePos.a < len
		colAcc.a *= backAlpha;
		FragColor = colAcc;
		return;
	}
	//overlay pass
	vec4 ocolAcc = vec4(0.0,0.0,0.0,0.0);
	vec4 prevNorm = ocolAcc;
	while (samplePos.a <= len) {
			colorSample = texture3D(intensityVol,samplePos.xyz);
			if (colorSample.a > colAcc.a)
				colAcc = colorSample;
			gradSample= texture3D(gradientVol,samplePos.xyz);
			if (gradSample.a > gradMax.a)
				gradMax = gradSample;
			//overlay:	
			colorSample.rgba = texture3D(intensityOverlay,samplePos.xyz);
			colorSample.a = 1.0-pow((1.0 - colorSample.a), stepSize/sliceSize);
			if (colorSample.a > 0.0) {
				gradSample = texture3D(gradientOverlay,samplePos.xyz);
				gradSample.rgb = normalize(gradSample.rgb*2.0 - 1.0);
				if (gradSample.a < prevNorm.a)
					gradSample.rgb = prevNorm.rgb;
				prevNorm = gradSample;
				float lightNormDot = dot(gradSample.rgb, lightPosition);
				vec3 a = colorSample.rgb * ambient;
				vec3 d = max(lightNormDot, 0.0) * colorSample.rgb * diffuse;
				float s =   specular * pow(max(dot(reflect(lightPosition, gradSample.rgb), dir), 0.0), shininess);
				colorSample.rgb = a + d + s;
			}
			colorSample.rgb *= colorSample.a;
			ocolAcc= (1.0 - ocolAcc.a) * colorSample + ocolAcc;
			samplePos += deltaDir;
	} //while samplePos.a < len
	colAcc.a *= backAlpha;
	if (ocolAcc.a > 0.01)  {
		ocolAcc.a = ocolAcc.a * (overAlpha);
		colAcc.rgb=mix(colAcc.rgb, ocolAcc.rgb,  ocolAcc.a);
		colAcc.a=max(colAcc.a,ocolAcc.a);
	}	
	FragColor = colAcc;
}