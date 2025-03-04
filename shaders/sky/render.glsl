#include "common.glsl"


//#define CUSTOMRAYLEIGH
#define SAMPLES 4
#define SCATTER_EVENTS 5

const float sundeg = 0.5;

const int points = 16;
const int odpoints = 8;

const vec3 scatterm = vec3(2.1e-5);
//const vec3 scatterr = vec3(1.8e-6, 14.5e-6, 44.1e-6);

const float ozone = 1.0;

const float planetrad = 6371e3;
const float atmoheight = 100e3;

const vec2 scaleheights = vec2(8.5, 1.25) * 1000.0;

const vec2 inversescaleheights = 1.0 / scaleheights;
const vec2 scaledplanetrads = planetrad * inversescaleheights;
const float atmorad = planetrad + atmoheight;
const float atmolowerlim = planetrad - 1000.0;

float rphase(float c) {
    return  3.0 * (1.0 + c * c) / 16.0 / pi;
}

float mphase2 (float c) {
    float g = 0.76;

    float e = 1.0;
    for (int i = 0; i < 8; i++) {
        float gFromE = 1.0 / e - 2.0 / log(2.0 * e + 1.0) + 1.0;
        float deriv = 4.0 / ((2.0 * e + 1.0) * log(2.0 * e + 1.0) * log(2.0 * e + 1.0)) - 1.0 / (e * e);
        if (abs(deriv) < 0.00000001) break;
        e = e - (gFromE - g) / deriv;
    }

    return e / (2.0 * pi * (e * (1.0 - c) + 1.0) * log(2.0 * e + 1.0));
}


float raydens (in float h) {
    return exp(-h * inversescaleheights.x + scaledplanetrads.x);
}

float miedens (in float h) {
    return exp(-h * inversescaleheights.y + scaledplanetrads.y);
}

//From Jessie
float ozonedens (in float h) {
    float o1 = 25.0 *     exp(( 0.0 - h) /   8.0) * 0.5;
    float o2 = 30.0 * pow(exp((18.0 - h) /  80.0), h - 18.0);
    float o3 = 75.0 * pow(exp((25.3 - h) /  35.0), h - 25.3);
    float o4 = 50.0 * pow(exp((30.0 - h) / 150.0), h - 30.0);
    return (o1 + o2 + o3 + o4) / 134.628;
}

vec3 dens2 (float height) {
    height = max(height, planetrad);
    float ray = raydens(height);
    float mie = miedens(height);
    float ozone = ozonedens((height - planetrad) / 1000.0);

    return vec3(ray, mie, ozone);
}

vec3 lighttrans (vec3 ro, vec3 rd) {
    float dist = dot(ro, rd);
    dist = sqrt(dist * dist + atmorad * atmorad - dot(ro, ro)) - dist;
    float t = dist / float(odpoints);
    vec3 step = rd * t;
    ro += step * 0.5;

    vec3 sum = vec3(0.0);
    for (int i = 0; i < odpoints; i++, ro += step) {
        float height = length(ro);
        sum += dens2(height);
    }
    
    vec3 scattero = vec3(PreethamBetaO_Fit(680.0), PreethamBetaO_Fit(550.0), PreethamBetaO_Fit(440.0)) * 2.5035422e25 * exp(-25e3 / 8e3) * 134.628 / 48.0 * 3e-6 * ozone * 1e-4;
    #ifndef CUSTOMRAYLEIGH
    vec3 scatterr = vec3(BetaR(680.0), BetaR(550.0), BetaR(440.0));
    #endif
    
    vec3 scatterm = vec3(BetaM(680.0), BetaM(550.0), BetaM(440.0));

    vec3 od = (scatterr * t * sum.x) + (scatterm * t * sum.y) + (scattero * t * sum.z);
    vec3 trans = exp(-od);
    if (any(isnan(trans))) trans = vec3(0.0);
    if (any(isinf(trans))) trans = vec3(1.0);

    return trans;
}

vec3 lighttrans2 (vec3 ro, vec3 rd, float dist) {
    float t = dist / float(odpoints);
    vec3 step = rd * t;
    ro += step * 0.5;

    vec3 sum = vec3(0.0);
    for (int i = 0; i < odpoints; i++, ro += step) {
        float height = length(ro);
        sum += dens2(height);
    }
    
    vec3 scattero = vec3(PreethamBetaO_Fit(680.0), PreethamBetaO_Fit(550.0), PreethamBetaO_Fit(440.0)) * 2.5035422e25 * exp(-25e3 / 8e3) * 134.628 / 48.0 * 3e-6 * ozone;
    #ifndef CUSTOMRAYLEIGH
    vec3 scatterr = vec3(BetaR(680.0), BetaR(550.0), BetaR(440.0));
    #endif
    
    vec3 scatterm = vec3(BetaM(680.0), BetaM(550.0), BetaM(440.0));

    vec3 od = (scatterr * t * sum.x) + (scatterm * t * sum.y) + (scattero * t * sum.z);
    vec3 trans = exp(-od);
    if (any(isnan(trans))) trans = vec3(0.0);
    if (any(isinf(trans))) trans = vec3(1.0);

    return trans;
}

vec3 march (vec3 ro, vec3 rd, vec3 lrd, vec3 intens, vec3 col) {
    vec2 atmo = RSI(ro, rd, vec4(vec3(0.0), atmorad));
    vec2 plan = RSI(ro, rd, vec4(vec3(0.0), atmolowerlim));

    bool atmoi = atmo.y >= 0.0;
    bool plani = plan.x >= 0.0;

    col *= float(!plani);

    vec2 idk = vec2((plani && plan.x < 0.0) ? plan.y : max(atmo.x, 0.0), (plani && plan.x > 0.0) ? plan.x : atmo.y);

    float t = length(idk.y - idk.x) / float(points);
    vec3 step = rd * t;
    vec3 p = ro + rd * idk.x + step * 0.5;

    float mu = dot(rd, lrd);

    float rayphase = rphase(mu) * 4.0 * pi;
    float miephase = mphase2(mu) * 4.0 * pi;
    
    vec3 scattero = vec3(PreethamBetaO_Fit(680.0), PreethamBetaO_Fit(550.0), PreethamBetaO_Fit(440.0)) * 2.5035422e25 * exp(-25e3 / 8e3) * 134.628 / 48.0 * 3e-6 * ozone;
    #ifndef CUSTOMRAYLEIGH
    vec3 scatterr = vec3(BetaR(680.0), BetaR(550.0), BetaR(440.0));
    #endif
    
    vec3 scatterm = vec3(BetaM(680.0), BetaM(550.0), BetaM(440.0));

    vec3 scattering = vec3(0.0);
    vec3 trans = vec3(1.0);
    for (int i = 0; i < points; i++, p += step) {
        vec3 dens = dens2(length(p));
        if (dens.x > 1e35) break;
        if (dens.y > 1e35) break;
        if (dens.z > 1e35) break;

        vec3 mass = t * dens;
        if (any(isnan(mass))) mass = vec3(0.0);

        vec3 stepod = (scatterr * mass.x) + (scatterm * mass.y) + (scattero * mass.z);

        vec3 steptrans = clamp(exp(-stepod), 0.0, 1.0);
        vec3 scatter = trans * clamp((steptrans - 1.0) / -stepod, 0.0, 1.0);

        scattering += (scatterr * mass.x * rayphase + scatterm * mass.y * miephase) * scatter * lighttrans(p, lrd);
        trans *= steptrans;
    }
    if (any(isnan(scattering))) return vec3(0.0);

    return scattering * intens + col * trans;
}

float trace (vec3 ro, vec3 rd) {
    vec2 atmo = RSI(ro, rd, vec4(vec3(0.0), atmorad));
    vec2 plan = RSI(ro, rd, vec4(vec3(0.0), atmolowerlim));

    bool atmoi = atmo.y >= 0.0;
    bool plani = plan.x >= 0.0;

    vec2 idk = vec2((plani && plan.x < 0.0) ? plan.y : max(atmo.x, 0.0), (plani && plan.x > 0.0) ? plan.x : atmo.y);

    return length(idk.y - idk.x);
}

vec3 pt (vec3 ro, vec3 rd, vec3 lrd, vec3 intens, vec3 col, uint rng) {
    vec3 through = vec3(1.0);
    vec3 scattering = vec3(0.0);
    
    vec3 scattero = vec3(PreethamBetaO_Fit(680.0), PreethamBetaO_Fit(550.0), PreethamBetaO_Fit(440.0)) * 2.5035422e25 * exp(-25e3 / 8e3) * 134.628 / 48.0 * 3e-6 * ozone;
    #ifndef CUSTOMRAYLEIGH
    vec3 scatterr = vec3(BetaR(680.0), BetaR(550.0), BetaR(440.0));
    #endif
    
    vec3 scatterm = vec3(BetaM(680.0), BetaM(550.0), BetaM(440.0));
    
    vec3 p = ro;
    
    vec3 trans = lighttrans2(ro, rd, trace(ro, rd));
    
    for (int i = 0; i < SCATTER_EVENTS; i++) {
        float t = trace(p, rd);
        float dist = t * randF(rng);
        
        vec3 od = lighttrans2(p, rd, dist);
        
        p = p + rd * dist;
        
        vec3 mass = dens2(length(p));
        if (mass.x > 1e35) break;
        if (mass.y > 1e35) break;
        if (mass.z > 1e35) break;
        if (any(isnan(mass))) mass = vec3(0.0);
        
        vec3 newDir = randV(rng);
        
        float mu = dot(rd, newDir);

        float rayphase = rphase(mu) * 4.0 * pi;
        float miephase = mphase2(mu) * 4.0 * pi;
        
        float mu2 = dot(rd, lrd);

        float rayphase2 = rphase(mu2) * 4.0 * pi;
        float miephase2 = mphase2(mu2) * 4.0 * pi;
        
        scattering += through * (scatterr * mass.x * rayphase2 + scatterm * mass.y * miephase2) * od * lighttrans(p, lrd) * t * intens;
        through *= (scatterr * mass.x * rayphase + scatterm * mass.y * miephase) * od * t;
        
        rd = newDir;
    }
    
    return scattering + col * trans;
}

uniform float frameTimeCounter;

vec3 sky (vec3 ro, vec3 rd, vec3 sunrd, vec3 rsunrd, vec3 col) {
    vec3 sunintens = vec3(plancks(680.0, 5800.0), plancks(550.0, 5800.0), plancks(440.0, 5800.0));
    vec3 sun = dot(rd, rsunrd) > cos(radians(sundeg)) ? sunintens : col;
    ro.y += planetrad;
    return march(ro, rd, sunrd, sunintens * 2.0 * pi * (1.0 - cos(radians(sundeg))), sun);
}

vec3 skypt (vec3 ro, vec3 rd, vec3 sunrd, vec3 col, uint rng) {
    ro.y += planetrad;
    
    vec3 sunintens = vec3(plancks(680.0, 5800.0), plancks(550.0, 5800.0), plancks(440.0, 5800.0));
    vec3 sun = dot(rd, sunrd) > cos(radians(sundeg)) ? sunintens : col;
        
    vec3 sum = vec3(0.0);
    for (int i = 0; i < SAMPLES - min(frameTimeCounter, 0); i++) {
        vec3 sampledsunrd = coneDir(sunrd, rng, radians(sundeg));
        sum += pt(ro, rd, sampledsunrd, sunintens * 2.0 * pi * (1.0 - cos(radians(sundeg))), sun, rng);
    }
    
    return sum / float(SAMPLES);
}
vec3 tone(vec3 color){	
	mat3 m1 = mat3(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
	);
	mat3 m2 = mat3(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
	);
	vec3 v = m1 * color;    
	vec3 a = v * (v + 0.0245786) - 0.000090537;
	vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
	return pow(clamp(m2 * (a / b), 0.0, 1.0), vec3(1.0 / 2.2));
}