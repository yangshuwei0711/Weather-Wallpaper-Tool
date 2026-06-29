#include <metal_stdlib>
using namespace metal;

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

// ==========================================
// 1. 物理幾何與光學參數常數
// ==========================================
constant float R_EARTH = 6360e3;    // 地球半徑 (公尺)
constant float R_ATM = 6420e3;      // 大氣層半徑 (公尺)
constant float3 BETA_R = float3(5.5e-6, 13.0e-6, 22.4e-6); // 瑞利散射係數 (RGB對應不同波長)
constant float BETA_M = 21.0e-6;    // 米氏散射係數
constant float H_R = 7994.0;        // 瑞利密度標高
constant float H_M = 1200.0;        // 米氏密度標高
constant float G_M = 0.75;          // 米氏相位非對稱因子

// 射線與球體交點測試
float2 raySphereIntersect(float3 ro, float3 rd, float3 center, float radius) {
    float3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float h = b * b - c;
    if(h < 0.0) return float2(-1.0);
    h = sqrt(h);
    return float2(-b - h, -b + h);
}

// 相位函數
float phaseRayleigh(float cosTheta) {
    return 3.0 / (16.0 * 3.14159) * (1.0 + cosTheta * cosTheta);
}

float phaseMie(float cosTheta, float g) {
    float g2 = g * g;
    return 3.0 / (8.0 * 3.14159) * ((1.0 - g2) * (1.0 + cosTheta * cosTheta)) /
           ((2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

// ==========================================
// 2. 主渲染管線
// ==========================================
fragment float4 fragmentMain(RasterizerData in [[stage_in]],
                             constant float3& timeData [[buffer(0)]],
                             constant float& aspect [[buffer(2)]]) {

    float2 uv = in.uv * 2.0 - 1.0;
    uv.y = -uv.y;
    uv.x *= aspect;
    
    // 計算太陽位置與 3D 向量
    float currentTime = timeData.x;
    float sunrise = timeData.y;
    float sunset = timeData.z;
    float alpha = atan2(0.35, aspect);
    float sunAngle = 0.0;
    if (currentTime >= sunrise && currentTime <= sunset) {
        float progress = (currentTime - sunrise) / (sunset - sunrise);
        sunAngle = mix(-alpha, 3.1415926 + alpha, progress);
    } else {
        float nightLength = 24.0 - (sunset - sunrise);
        float elapsedNight = (currentTime > sunset) ? (currentTime - sunset) : (currentTime + 24.0 - sunset);
        sunAngle = mix(3.1415926 + alpha, 2.0 * 3.1415926 - alpha, elapsedNight / nightLength);
    }
    
    // 將 2D 的太陽角度轉換為 3D 世界的光源方向
    float3 sunDir = normalize(float3(cos(sunAngle), sin(sunAngle), 0.15));

    // 建立 3D 攝影機系統
    float3 rayOrigin = float3(0.0, R_EARTH + 1.0, 0.0); // 站在地表上 1 公尺
    
    // 將螢幕 UV 投射為 3D 視角射線 (將視野稍微向上仰，呈現天空感)
    float3 rayDir = normalize(float3(uv.x, uv.y + 0.3, 1.0));

    // ==========================================
    // 3. 數值積分：Ray Marching 核心
    // ==========================================
    float3 earthCenter = float3(0.0, 0.0, 0.0);
    float2 atmIntersect = raySphereIntersect(rayOrigin, rayDir, earthCenter, R_ATM);
    
    // 如果射線沒有擊中大氣層，直接返回全黑太空
    if (atmIntersect.y < 0.0) return float4(0,0,0,1);
    
    // 限制行進距離
    float tMin = max(0.0, atmIntersect.x);
    float tMax = atmIntersect.y;
    float2 earthIntersect = raySphereIntersect(rayOrigin, rayDir, earthCenter, R_EARTH);
    if (earthIntersect.x > 0.0) tMax = min(tMax, earthIntersect.x); // 被地球擋住

    float segmentLength = (tMax - tMin) / 16.0; // 主射線採樣 16 步
    float tCurrent = tMin + segmentLength * 0.5;
    
    float3 totalR = float3(0.0);
    float3 totalM = float3(0.0);
    float opticalDepthR = 0.0;
    float opticalDepthM = 0.0;
    
    float cosTheta = dot(rayDir, sunDir);
    float pR = phaseRayleigh(cosTheta);
    float pM = phaseMie(cosTheta, G_M);

    // 外層迴圈：沿著視線方向步進
    for (int i = 0; i < 16; i++) {
        float3 samplePos = rayOrigin + rayDir * tCurrent;
        float height = length(samplePos) - R_EARTH;
        
        // 該點的大氣密度 (依高度呈指數衰減)
        float hr = exp(-height / H_R) * segmentLength;
        float hm = exp(-height / H_M) * segmentLength;
        opticalDepthR += hr;
        opticalDepthM += hm;
        
        // 內層迴圈：計算從該點到太陽方向的衰減 (光學深度)
        float lightSegmentLength = raySphereIntersect(samplePos, sunDir, earthCenter, R_ATM).y / 4.0; // 光源射線採樣 4 步
        float lightTCurrent = lightSegmentLength * 0.5;
        float lightOpticalDepthR = 0.0;
        float lightOpticalDepthM = 0.0;
        
        bool blockedByEarth = false;
        if (raySphereIntersect(samplePos, sunDir, earthCenter, R_EARTH).x > 0.0) {
            blockedByEarth = true;
        }

        if (!blockedByEarth) {
            for (int j = 0; j < 4; j++) {
                float3 lightSamplePos = samplePos + sunDir * lightTCurrent;
                float lightHeight = length(lightSamplePos) - R_EARTH;
                lightOpticalDepthR += exp(-lightHeight / H_R) * lightSegmentLength;
                lightOpticalDepthM += exp(-lightHeight / H_M) * lightSegmentLength;
                lightTCurrent += lightSegmentLength;
            }
            
            // 結合兩段路徑的總衰減
            float3 tau = BETA_R * (opticalDepthR + lightOpticalDepthR) +
                         BETA_M * 1.1 * (opticalDepthM + lightOpticalDepthM);
            float3 attenuation = exp(-tau);
            
            // 累加該點的散射光
            totalR += hr * attenuation;
            totalM += hm * attenuation;
        }
        tCurrent += segmentLength;
    }
    
    // 計算最終物理色彩
    float sunIntensity = 20.0;
    float3 finalColor = sunIntensity * (totalR * BETA_R * pR + totalM * BETA_M * pM);
    
    // HDR 色調映射 (Tone Mapping) 與 Gamma 校正
    finalColor = 1.0 - exp(-1.5 * finalColor); // Exposure
    finalColor = pow(finalColor, float3(1.0 / 2.2)); // Gamma
    
    return float4(finalColor, 1.0);
}
