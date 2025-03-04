

/* RENDERTARGETS: 3 */
layout(location = 0) out vec4 color;
const bool colortex3Clear = false;
const int RGBA32F = 0; // buffer must be 32f hdr otherwise there are all kinds of artifacts when accumulating
const int colortex3Format = RGBA32F;



in vec2 texcoord;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform int frameCounter;
uniform float frameTime;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 sunPosition;

uniform int worldTime;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform float frameTimeCounter;
uniform int hideGUI;
uniform int isEyeInWater;
uniform sampler2D colortex0;
uniform sampler2D shadowtex0;
uniform sampler2D colortex1;
uniform sampler2D gcolor;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D noisetex;
const int shadowMapResolution = 4096;

#define RENDER_DIST 90 
#define MAX_DIST 2000.0
#define EPS1 0.0002
#define EPS2 0.000003
#define EPS3 0.00001
#define PI 3.14159267
#define PI2 6.28318531
#define PIinv 0.31830989
vec3 eyeCameraPosition;
vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
  vec4 homPos = projectionMatrix * vec4(position, 1.0);
  return homPos.xyz / homPos.w;
}


vec3 sRGBtoLinear(vec3 col) {
	float gamma = 2.2f;
	return pow(col,vec3(gamma));
}

vec3 getFragPosition() {
     float depthBuffer = texture(depthtex0,texcoord).s;
	   vec3 divceCoordinates = vec3(texcoord,depthBuffer)*2.0f - 1.0f;
	   vec3 viewCoord = projectAndDivide(gbufferProjectionInverse,divceCoordinates);
	   viewCoord = mat3(gbufferModelViewInverse) * viewCoord;
	   return viewCoord + eyeCameraPosition;  
}



struct Ray {
	vec3 origin;
	vec3 direction;
};

Ray genRay() {
   	vec2 texcoord = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
	vec4 tmp = gbufferProjectionInverse * vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
        return Ray(cameraPosition,normalize(mat3(gbufferModelViewInverse) * tmp.xyz));    
}




struct hit {
  vec4 voxPosID;
  vec3 tint;
	vec3 normal;
  float Distance;
	vec3 hitpoint;
};

vec4 intersectBox(vec3 ro, vec3 rd, vec3 origin, vec3 size) { // for rotated boxes, first project ro and rd onto the rotated coord sys axes. - origin is local, to make it global subtract origin from ro beforehand
	ro = ro - origin;
	vec3 offset = size * sign(rd); // depending on the direction we are looking, we offset the planes

	vec3 tN = (ro + offset) / -rd; // near planes. the offset shifts the planes towards us
	vec3 tF = (ro - offset) / -rd; // far planes. the offset shifts the planes away from us

	float dN = max(tN.x, max(tN.y, tN.z));
	float dF = min(tF.x, min(tF.y, tF.z));

	if(dF < dN || dF < 0.0) return vec4(vec3(0.0), 1000.0); // dF < 0.0  removes the double shadow if the ray is exiting the box without intersection

	vec3 n = -sign(rd) * step(tN.yzx,tN.xyz) * step(tN.zxy,tN.xyz);

	return vec4(n, dN);
	}
	vec4 intersectCustom(int voxID, vec3 entryP, vec3 exitP, vec3 rd, vec3 orig_n) {
	vec3 n; float d;

	// SLABS BOTTOM
	if(voxID < 52) {
		if(entryP.y < 0.5) return vec4(orig_n, 0.0);
		if(exitP.y > 0.5) return vec4(vec3(0.0), 1000.0);
		float tMax = (0.5 - entryP.y) / rd.y;
		return vec4(vec3(0.0,1.0,0.0), tMax);
		}
	// SLABS TOP
	if(voxID < 53) {
		if(entryP.y > 0.5) return vec4(orig_n, 0.0);
		if(exitP.y < 0.5) return vec4(vec3(0.0), 1000.0);
		float tMax = (0.5 - entryP.y) / rd.y;
		return vec4(vec3(0.0,-1.0,0.0), tMax);
		}
         if (voxID == 54) {
        float blockHeight = 0.9375; // 15/16 block height

        // If the ray is above the block, ignore intersections below
        if (entryP.y < blockHeight) return vec4(orig_n, 0.0);
        if (exitP.y > blockHeight) return vec4(vec3(3.0, 0.0, 0.0), 1000.0);

        // Intersection with top surface
        float tMax = (blockHeight - entryP.y) / rd.y;
        if (tMax > 0.0) return vec4(vec3(0.0, 1.0, 0.0), tMax);

        // Sides intersection
        float tX = (0.5 - entryP.x) / rd.x;
        float tZ = (0.5 - entryP.z) / rd.z;

        if (tX < 0.0 && tX > tZ) return vec4(vec3(sign(rd.x), 0.0, 0.0), tX);
        if (tZ > 0.0) return vec4(vec3(0.0, 0.0, sign(rd.z)), tZ);
    }  
		}
     

// VOXEl
int checkVoxel(ivec3 coords) {

		ivec2 ShadowMapPosPX = coords.xz*16 + ivec2(coords.y % 16, coords.y/16) +2048;
		float ShadowMapData = texelFetch(shadowcolor0, ShadowMapPosPX, 0).w;
		if(ShadowMapData < 0.0001) return 0; // check if out of bounds to avoid seeing weird blocks in distance
		int voxID =  int(floor((1.0 - ShadowMapData) * 255.5));
		return voxID;
	}

vec3 tintLookUpTable[16] = vec3[16](
        vec3(0.9),
        vec3(0.9686, 0.5294, 0.2745),
        vec3(0.7,0.2,0.7),
        vec3(0.3,0.6,0.8),
 		vec3(0.8,0.7,0.1),   // [6] yellow
		vec3(0.45,0.75,0.2),   // [7] lime
		vec3(0.9,0.4,0.6),   // [8] pink
		vec3(0.3765, 0.3765, 0.3765),   // [9] gray
		vec3(0.5),   // [10] light_gray
		vec3(0.1,0.55,0.59),   // [11] cyan
		vec3(0.5,0.2,0.8),   // [12] purple
		vec3(0.2,0.3,0.7),   // [13] blue
		vec3(0.32,0.2,0.15),   // [14] brown
		vec3(0.22,0.3,0.12),   // [15] green
		vec3(0.7,0.2,0.2),   // [16] red
		vec3(0.05)   
);

vec3 emissiveLookUpTable[5] = vec3[5](
vec3(1.0, 0.7255, 0.251), 
vec3(0.6706, 0.9882, 0.9882),
vec3(1.0, 0.0667, 0.0),   
vec3(0.5882, 1.0, 0.2941), 
vec3(0.1373, 0.2824, 1.0)
);
  


vec3 getTint(int voxID) {
	#ifdef WATER
		if(voxID == 28) return vec3(0.8,0.83,0.88); // different color for the absorption depth coloring
	#endif
    vec3 tint = vec3(0.9);
    
	   if(voxID == 107) {
		tint = vec3(0.45,0.75,0.2);
	  }
	  if(voxID == 116) {
		tint = vec3(0.5569, 0.2667, 0.251);
	  }
      if(voxID > 120 && voxID < 126) {
		int lookUpID = voxID - 121;
		tint = emissiveLookUpTable[lookUpID];
	  }

	  if(voxID == 10) {
		tint = vec3(0);
	  }
      
	  if(voxID > 101 && voxID < 118) {
         int lookUpID = voxID - 102;
       tint = tintLookUpTable[lookUpID];

	  }

	if(voxID > 49) voxID = 11; // custom glass models are just regular glass

	vec3[19] block_color = vec3[19](
		vec3(0.0, 0.0, 0.0), // [0] unused
		vec3(0.9),   // [1] regular glass
		vec3(1.0, 1.0, 1.0),   // [2] white
		vec3(0.6,0.22,0.0),   // [3] orange
		vec3(0.7,0.2,0.7),   // [4] magenta
		vec3(0.3,0.6,0.8),   // [5] light_blue
		vec3(0.8,0.7,0.1),   // [6] yellow
		vec3(0.45,0.75,0.2),   // [7] lime
		vec3(0.9,0.4,0.6),   // [8] pink
		vec3(0.3765, 0.3765, 0.3765),   // [9] gray
		vec3(0.5),   // [10] light_gray
		vec3(0.1,0.55,0.59),   // [11] cyan
		vec3(0.5,0.2,0.8),   // [12] purple
		vec3(0.2,0.3,0.7),   // [13] blue
		vec3(0.32,0.2,0.15),   // [14] brown
		vec3(0.22,0.3,0.12),   // [15] green
		vec3(0.7,0.2,0.2),   // [16] red
		vec3(0.05),   // [17] black
		vec3(0.6,0.7,0.85)  // [18] water
	);
    
	return tint;
	}

int indexContribution;

uvec3 murmurHash33(uvec3 src) {
         
        src += uvec3(44*indexContribution); 
    const uint M = 0x5bd1e995u;
    uvec3 h = uvec3(1190494759u, 2147483647u, 3559788179u);
    src *= M; src ^= src>>24u; src *= M;
    h *= M; h ^= src.x; h *= M; h ^= src.y; h *= M; h ^= src.z;
    h ^= h>>13u; h *= M; h ^= h>>15u;
    return h;
}

// 3 outputs, 3 inputs
vec3 hash33(vec3 src) {
    uvec3 h = murmurHash33(floatBitsToUint(src));
    return uintBitsToFloat(h & 0x007fffffu | 0x3f800000u) - 1.0;
}


vec3 cosWeightedRandomHemisphereDirection(  vec3 n , vec3 seed) {
  	vec2 r = hash33(vec3(seed)).xy;
   //  r = texture(noiseTex0,texcoord*406.0f + ubo.time + i).xy;
	vec3  uu = normalize( cross( n, vec3(0.0,1.0,1.0) ) );
	vec3  vv = cross( uu, n );
	float ra = sqrt(r.y);
	float rx = ra*cos(6.2831*r.x); 
	float ry = ra*sin(6.2831*r.x);
	float rz = sqrt( 1.0-r.y );
	vec3  rr = vec3( rx*uu + ry*vv + rz*n );
    
    return normalize( rr );
}

int VoxID;

hit traverseAir(Ray ray, int render_dist, bool alsoHitGlass, bool checkFirstVoxel, float maxTintDist,bool firstHit) {
	vec3 rd = ray.direction;
    vec3 ro = ray.origin;
   if(firstHit) {
      ro = vec3(fract(ray.origin.x),ray.origin.y,fract(ray.origin.z));
   }
  ivec3 voxPos = ivec3(floor(ro));   // voxel coordinates of the voxel in which the camera is
	ivec3 stepVox = ivec3(sign(rd));   // direction in which X and Y must be incremented
	vec3 tMax = (voxPos + max(ivec3(0),stepVox) - ro) / rd;
	vec3 tDelta = stepVox / rd;
	vec3 n = ivec3(1.0); float d = 0.0; int voxID = 0;
	int lastTintID = 0; vec3 tint = vec3(1.0);
	for(int i = 0; i <= render_dist; i++) {
		voxID = checkVoxel(voxPos);
		tint = getTint(voxID);
		if(i > 0 || checkFirstVoxel) {

			if(voxID > 100) break; // if solid block

			// if not air etc
			if(voxID > 9) {

				// if transparent / glass
				if(voxID < 50) {
					if(alsoHitGlass) break;
					if(lastTintID != voxID && d < maxTintDist) tint *= getTint(voxID); // maxTintDist is to avoid tinted shadows if stained glass is BEHIND object (sphere rim shadow color bug)
					}

				else { // it must be custom geometry - intersect - if hit, break
					vec3 entryP = ro+rd*d - voxPos;  vec3 exitP = ro+rd*min(tMax.x, min(tMax.y, tMax.z)) - voxPos; // point where ray enters/exits the box of custom shape (relative to its local coord system)
					vec4 customData = intersectCustom(voxID, entryP, exitP, rd, n);
					if(customData.w != 1000.0 || i==render_dist) {n = customData.xyz; d = d + customData.w; break;} // if hit custom shape  -  the "|| i==render_dist" is to fix errors on last iteration on custom models
					// if it goes through, the loop continues and traverses the blocks behind
					}
				}

			}

		lastTintID = voxID;

		if(tMax.x < tMax.y) {
			if(tMax.x < tMax.z) {
				d = tMax.x; n = vec3(-stepVox.x,0.0,0.0);
				voxPos.x += stepVox.x; tMax.x += tDelta.x;
			} else {
				d = tMax.z; n = vec3(0.0,0.0,-stepVox.z);
				voxPos.z += stepVox.z; tMax.z += tDelta.z;
			}
		} else {
			if(tMax.y < tMax.z) {
				d = tMax.y; n = vec3(0.0,-stepVox.y,0.0);
				voxPos.y += stepVox.y; tMax.y += tDelta.y;
			} else {
				d = tMax.z; n = vec3(0.0,0.0,-stepVox.z);
				voxPos.z += stepVox.z; tMax.z += tDelta.z;
				}
			}

		}
	if(voxID < 10) { d = MAX_DIST; n = vec3(0.0); } // if last block is air - no hit
	return hit(vec4(voxPos, voxID), tint,n,d,(rd*d+ro)+n*0.001f);
	}

uniform vec3 shadowLightPosition;
mat2 R(float theta) {
	return mat2(cos(theta),-sin(theta),sin(theta),cos(theta));
}

vec3 getSunDirection(bool isJittered ,int index) {

	vec3 dir = normalize((mat3(gbufferModelViewInverse) * shadowLightPosition));
	  if(isJittered) {
		dir = normalize((mat3(gbufferModelViewInverse) * shadowLightPosition) + hash33(vec3(texcoord,frameTimeCounter + index*8)));
	  }
	  
	   dir.zx = R(PI/4.0) * dir.zx; 
	   dir.xy = R(radians(0.0)) * dir.xy;

	   return dir;
}




vec3 skyc(Ray r,out vec3 suncolor) {
	vec3 sunDirection = getSunDirection(false,0);
       vec3 up = vec3(0.0, 1.0, 0.0);        

     float dep = max(dot(sunDirection,r.direction)-0.9999f,0.0);
     vec3 topDome = max(vec3(sqrt(r.direction.y)),0.0);
     vec3 bottomDome = max(vec3(sqrt(-r.direction.y)),0.0);
  
    float distr = dot(sunDirection,up);

  vec3 skycolor = vec3(0.298, 0.5843, 0.8549);
   skycolor = mix(vec3(0.4157, 0.6627, 0.8627),skycolor,distr);
   
    vec3 dawnLine = vec3(1.0, 0.349, 0.0);
      dawnLine = mix(dawnLine,vec3(1),distr*distr);
     
  vec3 sky = (skycolor - bottomDome*0.7*dawnLine) + topDome*0.1 - max((topDome - 0.5)*dawnLine,-.3);
    vec3 otsph = mix(vec3(0.2039, 0.2706, 0.5569),vec3(0.0392, 0.0392, 0.1569),sqrt(distr));
  
    sky = mix(sky,otsph,(pow(topDome.x,1.3f)));
  
  vec3 dawnFonScattering = vec3(0.9412, 0.6196, 0.3882);
  float foNfallout = max(dot(r.direction,normalize(vec3(r.direction.x,0,r.direction.z))),0.0);
   foNfallout -= topDome.r;

   foNfallout = max(foNfallout,0.0f);
   foNfallout = pow(foNfallout,2.2);
     foNfallout = foNfallout-0.3;
	 foNfallout = max(foNfallout,0.0);
	 foNfallout = pow(foNfallout,2) * pow(max(dot(sunDirection,r.direction),0.0f),2.0) * (1-distr);

   sky += foNfallout*2*dawnFonScattering;
 
 //  sky = mix(vec3(0.7961, 0.7569, 1.0),sky,0.5*distr);
  // return vec3(dep);
  float fallLight = pow(max(distr,0.0),1/(2.0*PI));  
  vec3 sunColor = vec3(1); 
  vec3 dawnColor = vec3(1.0, 0.4392, 0.1373);
     
  vec3 sun = vec3(dep > 0) * mix(sunColor,dawnColor,1.0-distr) * 5;
    suncolor = mix(sunColor,dawnColor,1.0-distr);
  

  vec3 tot = mix(sky,vec3(0.0, 0.0, 0.0),min(bottomDome.x,0.94))*sqrt(distr) +sun;
 
    tot = mix(vec3(0.7961, 0.7569, 1.0)*sqrt(max(1.1 - sqrt(max(r.direction.g,0.0)),0.0))*sky,tot,0.5*distr*distr);
      tot*=fallLight;
	  tot+=sun;

   if(worldTime > 12777) {
	  tot *= 0.1;
	  suncolor = vec3(0.0);
   }
     


  return vec3((tot*vec3(0.6941, 0.8039, 0.9804)));
}



vec3 ComputeLighting(hit data, int index) {
    vec3 sunDirection = getSunDirection(true,index);
	// sunDirection = normalize(vec3(1)  + hash33(vec3(texcoord,frameTimeCounter))*0.05);
	vec3 hemisphereDistribution = cosWeightedRandomHemisphereDirection(data.normal,vec3(texcoord,frameTimeCounter + index*3));
	 Ray ray = Ray(data.hitpoint,hemisphereDistribution);
        uint rng = uint(uint(gl_FragCoord.x) * uint(1973) + uint(gl_FragCoord.y) * uint(9277) + uint(frameTimeCounter) * uint(26699)) | uint(1);
         
		 vec3 E0 ;
		 vec3 s = skyc(ray,E0);
		 	hit OcclusionCheck = traverseAir(ray, int(16), false, true, MAX_DIST,false);   
	     bool isOccluded = OcclusionCheck.Distance > 30.0f;
	//	vec3 dir = coneDir(sunDirection, rng, radians(sundeg));
       //   vec3 irad = tone(sky(ray.origin, ray.direction, dir, sunDirection, vec3(0.0))*0.4);
          int id = int(data.voxPosID.w);
		    ray.direction = sunDirection;
	hit shadowCheck = traverseAir(ray, int(32), false, true, MAX_DIST,false);   
	  bool isShadow = shadowCheck.Distance > 30.0f;
	  vec3 Lr = vec3(isShadow) * data.tint * max(dot(data.normal,sunDirection),0.0f)*10.0f*E0  + s*data.tint*vec3(isOccluded);
	     if(id > 120 && id < 126) {
			Lr = data.tint * 20.0f;
		 }
	
	return Lr;
}

void computeGlobalIllumination(hit data,inout vec3 shade,int index) {
   vec3 seed = vec3(texcoord,frameTimeCounter+1+index*5.0);
     Ray ray = Ray(data.hitpoint,cosWeightedRandomHemisphereDirection(data.normal,seed));
     /*FIRST GI BOUNCE*/ 
	  hit hitData = traverseAir(ray, int(16), false, true, MAX_DIST,false);   
       int id = int(data.voxPosID.w);
         	    if(id > 120 && id < 126 ) {
			     data.tint = pow(data.tint,vec3(1.0f/2.2));
		      }
          
        hitData.tint *= 1.1f;

     vec3 conservationOfEnergy = data.tint;
     vec3 firstShadeBounce = ComputeLighting(hitData,index);
  vec3 secondShadeBounce = vec3(0);
    /*SECOND GI BOUNCE*/
   /**/
     vec3 newSeed = vec3(texcoord-10f,-frameTimeCounter+10+index*7.0);  
       Ray newRay = Ray(hitData.hitpoint,cosWeightedRandomHemisphereDirection(hitData.normal,newSeed));
         hit newHitData = traverseAir(newRay, int(8), false, true, MAX_DIST,false);   
          //  newHitData.tint *= 1.1f;
           vec3 reConservationOfEnergy = hitData.tint*0.9;
		    secondShadeBounce = ComputeLighting(newHitData,index+8);

  shade += (firstShadeBounce + secondShadeBounce)*conservationOfEnergy;   

//	shade = data.tint;
}

uniform sampler2D colortex4;

bool Entity() {
 return (texture(colortex4,texcoord).r == 1);	
} 

vec4 getGbufferNormals() {
   vec3 terrainNormal = (texture(colortex1,texcoord).xyz * 2.0f - 1.0f);
    bool isEntity = (texture(colortex4,texcoord).r == 1);

     return vec4(terrainNormal,isEntity);
   
}


vec3 RayTrace(int index) {
   vec3 tot = vec3(0);
   vec3 col = vec3(1);
   float probability = 0.0; float probMin = 0.0; float probMax = 1.0;
      bool stencilTest = texture(depthtex0,texcoord).s == 1;
      Ray ray = genRay(); 
	  vec3 fragPosition = getFragPosition();
       vec3 s = skyc(ray,col);
        hit hitData = traverseAir(ray, int(RENDER_DIST), false, (probMax == probability), MAX_DIST,true); 
		hitData.tint = sRGBtoLinear(texture(colortex0,texcoord).rgb) * float(!stencilTest);  
		hitData.normal = getGbufferNormals().xyz * float(!stencilTest);
		if(distance(ray.origin,fragPosition) < 70){
		    hitData.hitpoint = getFragPosition() + hitData.normal*0.01f;
		 hitData.hitpoint.xz -= floor(cameraPosition).xz;
		}
        if(Entity()) {
			int entityID = 1000;
			hitData.voxPosID.w = entityID;
		} 
		
            bool test = VoxID == 107;
               vec3 shade = ComputeLighting(hitData,index);
		      computeGlobalIllumination(hitData,shade,index);      
     int VoxID = int(hitData.voxPosID.w);  
             // Ensure emissive blocks glow even if stencilTest is true
    if(stencilTest) {
      shade = s;
	}
   return vec3(shade);
}

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
 uniform mat4 gbufferProjection;

bool isViewUpdated() {
	   vec4 fragmentPosition = vec4(getFragPosition(),1);
	   vec4 previousPosition = fragmentPosition;
	   previousPosition.xyz -= previousCameraPosition;
             previousPosition = gbufferPreviousModelView * previousPosition;
             previousPosition = gbufferPreviousProjection * previousPosition;
             previousPosition /= previousPosition.w;


        float iDepth = 0.0f;

	     bool isCameraChanged = transpose(gbufferPreviousModelView)[2].xyz == transpose(gbufferModelView)[2].xyz;
	     bool isFovChanged = gbufferPreviousProjection[0][0] == gbufferProjection[0][0];
         bool isMoved =  previousCameraPosition == cameraPosition;
	     bool isEntity = getGbufferNormals().w == 1;  
 
   return isMoved && isCameraChanged && !isEntity && isFovChanged;
}

bool temporalUpdate() {

   vec4 prevViewDirection = gbufferPreviousModelView * (vec4(getFragPosition(),1) + vec4(cameraPosition-previousCameraPosition,0.0));
   vec4 prevHomogenous = gbufferPreviousProjection * prevViewDirection;
     vec2 prevScreen = (prevHomogenous.xy/prevHomogenous.w*0.5+0.5) * 1.0f;
	   vec4 prevNormal_map = texture2D(colortex1,prevScreen * 1.0f);
     
  return false;	
}



void main() {
    eyeCameraPosition = cameraPosition + gbufferModelViewInverse[3].xyz;
	    vec3 vox = vec3(0);
	  
	    for(int samples = 1; samples <= 1 ; samples++) { 
	         vox = mix(vox,RayTrace(samples),1.0/samples);
		}

		//vec3 IN = vox; 
           vec4 lastFrame = texture2D(colortex3, texcoord.xy);
    		   color.a = 1.0;
			
	       
              if(isViewUpdated()){
	          //   color.a = lastFrame.a + 1.0;
			  }
              
             color.rgb = mix(lastFrame.rgb, vox, min(0.7, 1.0 / color.a));
           //color.rgb = cameraPosition;
            
		//	color.rgba = (50/255)*lastFrame + (1 - 50/255)* vec4(IN,1);
			// float diff = length(vec3(vox) - length(lastFrame.rgb));
     //  color.rgb = vec3(diff > 0.05);
}
