//pref
ambient|float|0.0|1.0|1|Illuminate surface regardless of lighting
diffuse|float|0.0|0.2|1|Illuminate surface based on light position
specular|float|0.0|0.2|1|Glint from shiny surfaces
shininess|float|0.01|10.0|30|Specular reflections can be rough or precise
edgeThresh|float|0|0.1|1|Surface threshold (requires low edgeBoundMix)
boundThresh|float|0.0|0.3|0.95|Boundary threshold (requires high edgeBoundMix)
edgeBoundMix|float|0|1|1|Mixture of edge and boundary opacity
boundBrightness|float|0|0.3|1|Boundary color (requires high edgeBoundMix)
overlayDepth|float|0.0|0.3|0.8|Ability to see overlays beneath the background surface
colorTemp|float|0|0.5|1
//frag
uniform float ambient = 1.0;
uniform float diffuse = 0.0;
uniform float specular = 0.0;
uniform float shininess = 10.0;
uniform float edgeThresh = 0.1;
uniform float boundThresh = 0.3;
uniform float edgeBoundMix = 1.0;
uniform float boundBrightness = 0.0;
uniform float overlayDepth = 0.3;
uniform float overlayClip = 0.0;
uniform float colorTemp = 0.9;

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
	vec4 boundColor = vec4(boundBrightness, boundBrightness, boundBrightness, 1.0);
	vec4 samplePos;
	//background pass
	float noClipLen = len;
	samplePos = vec4(start.xyz +deltaDir.xyz* (fract(sin(gl_FragCoord.x * 12.9898 + gl_FragCoord.y * 78.233) * 43758.5453)), 0.0);
	vec4 clipPos = applyClip(dir, samplePos, len);
	float stepSizeX2 = samplePos.a + (stepSize * 2.0);
	//fast pass - optional
	fastPass (len, dir, gradientVol, samplePos);
	if ((samplePos.a > len) && ( overlays < 1 )) { //no hit: quit here
		FragColor = colAcc;
		return;		
	}
	//end fastpass - optional
	gradSample= texture3D(intensityVol,samplePos.xyz); //force uniform to be used
	vec3 defaultDiffuse = vec3(0.5, 0.5, 0.5);
	vec3 lightDirHeadOn = rayDir.xyz;
	float boundExpD = 0.01;
	float edgeExp = 0.2;
	float edgeBoundMixD = 1.0 - pow(edgeBoundMix, 2.0);
	vec4 edgeColor = vec4(1.0, 1.0, 1.0, 1.0);
	if (colorTemp < 0.5) {
		edgeColor.b = 1.0-((0.5-colorTemp)*-0.5);
		edgeColor.g = 1.0-((0.5-colorTemp)*-0.1);
	}
	if (colorTemp > 0.5) {
		edgeColor.g = 1.0-((colorTemp-0.5)*-0.1);
		edgeColor.r = 1.0-((colorTemp-0.5)*-0.5);
	}
	while (samplePos.a <= len) {
		gradSample= texture3D(gradientVol,samplePos.xyz);
		if (gradSample.a > 0.0) {
			bgNearest = min(samplePos.a, bgNearest);
			gradSample.rgb = normalize(gradSample.rgb*2.0 - 1.0);
			colorSample = gradSample;
			if (gradSample.a > boundThresh) {
				float lightNormDot = dot(gradSample.rgb, lightDirHeadOn); //with respect to viewer
				colorSample.a = colorSample.a * pow(1.0-abs(lightNormDot),6.0);
				colorSample.a = colorSample.a * pow(colorSample.a,boundExpD);
			} else {
				colorSample.a = 0.0;
			}
			colorSample.rgb = boundColor.rgb * colorSample.a;
			if  (gradSample.a > edgeThresh) {
				float edge = smoothstep(edgeThresh, 1.0, gradSample.a);
				edge = pow(edge, edgeExp);
				float edgeAlpha = edge*edgeBoundMixD;
				if (edgeAlpha > colorSample.a) {
					//specular
					float lightNormDot = dot(gradSample.rgb, lightPosition); //with respect to light location
					if (lightNormDot > 0.0)
						edge +=   specular * pow(max(dot(reflect(lightPosition, gradSample.rgb), dir), 0.0), shininess);
					colorSample.rgb = edgeColor.rgb * edge;

					colorSample.a = edgeAlpha;
					colorSample.rgb *= colorSample.a;
				}
			}
			colAcc= (1.0 - colAcc.a) * colorSample + colAcc;
			if ( colAcc.a > 0.95 )
			break;
		}
		samplePos += deltaDir;
	} //while samplePos.a < len
	colAcc.a = colAcc.a/0.95;
	colAcc.a *= backAlpha;
	if ( overlays < 1 ) { //no overlays - color based solely on background image
		FragColor = colAcc;
		return;
	}
	//overlay pass
	vec4 overAcc = vec4(0.0,0.0,0.0,0.0);
	prevGrad = vec4(0.0,0.0,0.0,0.0);
	if (overlayClip > 0)
		samplePos = clipPos;
	else {
		len = noClipLen;
		samplePos = vec4(start.xyz +deltaDir.xyz* (fract(sin(gl_FragCoord.x * 12.9898 + gl_FragCoord.y * 78.233) * 43758.5453)), 0.0);
	}
	//fast pass - optional
	fastPass (len, dir, intensityOverlay, samplePos);
	//end fastpass - optional
	while (samplePos.a <= len) {
		colorSample = texture3D(intensityOverlay,samplePos.xyz);
		if (colorSample.a > 0.00) {
			colorSample.a = 1.0-pow((1.0 - colorSample.a), stepSize/sliceSize);
			vec3 a = colorSample.rgb * ambient;
			float s =  0;
			vec3 d = vec3(0.0, 0.0, 0.0);
			overFarthest = samplePos.a;
			//gradient based lighting http://www.mccauslandcenter.sc.edu/mricrogl/gradients
			gradSample = texture3D(gradientOverlay,samplePos.xyz); //interpolate gradient direction and magnitude
			gradSample.rgb = normalize(gradSample.rgb*2.0 - 1.0);
			//reusing Normals http://www.marcusbannerman.co.uk/articles/VolumeRendering.html
			if (gradSample.a < prevGrad.a)
				gradSample.rgb = prevGrad.rgb;
			prevGrad = gradSample;
			float lightNormDot = dot(gradSample.rgb, lightPosition);
			d = max(lightNormDot, 0.0) * colorSample.rgb * diffuse;
			s =   specular * pow(max(dot(reflect(lightPosition, gradSample.rgb), dir), 0.0), shininess);
			colorSample.rgb = a + d + s;
			colorSample.rgb *= colorSample.a;
			overAcc= (1.0 - overAcc.a) * colorSample + overAcc;
			if (overAcc.a > 0.95 )
				break;
		}
		samplePos += deltaDir;
	} //while samplePos.a < len
	overAcc.a = overAcc.a/0.95;
	//end ovelay pass clip plane applied to background ONLY...
	float overMix = overAcc.a;
	if (((overFarthest) > bgNearest) && (colAcc.a > 0.0)) { //background (partially) occludes overlay
		float dx = (overFarthest - bgNearest)/1.73;
		dx = colAcc.a * pow(dx, overlayDepth);
		overMix *= 1.0 - dx;
	}
	colAcc.rgb = mix(colAcc.rgb, overAcc.rgb, overMix);
	colAcc.a = max(colAcc.a, overAcc.a);
	FragColor = colAcc;
}