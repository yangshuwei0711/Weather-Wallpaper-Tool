//
//  SkyRenderer.metal
//  weather wallpaper tool
//
//  Created by 楊舒瑋 on 2026/6/29.
//

#include <metal_stdlib>
using namespace metal;

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

// 3D 空間雜訊函數
float hash(float3 p) {
    p = fract(p * float3(123.34, 456.21, 789.12));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y * p.z);
}

vertex RasterizerData vertexMain(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    RasterizerData out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = out.position.xy * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

fragment float4 fragmentMain(RasterizerData in [[stage_in]],
                             constant float3& timeData [[buffer(0)]],
                             constant float& moonPhase [[buffer(1)]],
                             constant float& aspect [[buffer(2)]],
                             constant float& time [[buffer(3)]]) {

    float2 uv = in.uv * 2.0 - 1.0;
    uv.y = -uv.y;
    uv.x *= aspect;
    
    // 🌟 幾何修正：將自轉軸心下移，確保天體最高點剛好切齊螢幕頂部，不會飛出邊框
    float2 origin = float2(0.0, -0.65);
    
    // 新的半徑計算 (因為地平線在 y = -1.0，所以與 origin 現在差了 0.35 的高度)
    float orbitRadius = sqrt(aspect * aspect + 0.35 * 0.35);
    float alpha = atan2(0.35, aspect);

    float currentTime = timeData.x;
    float sunrise = timeData.y;
    float sunset = timeData.z;

    float sunAngle = 0.0;
    if (currentTime >= sunrise && currentTime <= sunset) {
        float progress = (currentTime - sunrise) / (sunset - sunrise);
        sunAngle = mix(-alpha, 3.1415926 + alpha, progress);
    } else {
        float nightLength = 24.0 - (sunset - sunrise);
        float elapsedNight = (currentTime > sunset) ? (currentTime - sunset) : (currentTime + 24.0 - sunset);
        float nightProgress = elapsedNight / nightLength;
        sunAngle = mix(3.1415926 + alpha, 2.0 * 3.1415926 - alpha, nightProgress);
    }

    float2 sunPos = origin + float2(cos(sunAngle) * orbitRadius, sin(sunAngle) * orbitRadius);
    
    // 🌟 修正 1：利用真實月相計算月球的 2D 軌道落後角度
    float moonAngle = sunAngle - (moonPhase * 6.283185);
    float2 moonPos = origin + float2(cos(moonAngle) * orbitRadius, sin(moonAngle) * orbitRadius);

    float3 daySky = float3(0.12, 0.42, 0.82);
    float3 nightSky = float3(0.008, 0.012, 0.025);
    float skyProgress = smoothstep(0.0, 0.5, sunPos.y + 1.0);
    float3 finalColor = mix(nightSky, daySky, skyProgress);

    // ---------------------------------------------------------
    // 動態星空系統
    // ---------------------------------------------------------
    float2 toPixel = uv - origin;
    float cosS = cos(-sunAngle);
    float sinS = sin(-sunAngle);
    float2 rotatedUV = float2(
        toPixel.x * cosS - toPixel.y * sinS,
        toPixel.x * sinS + toPixel.y * cosS
    );
    
    float2 starUV = rotatedUV * 26.0;
    float2 gridID = floor(starUV);
    float2 starLocalPos = fract(starUV) - 0.5;
    
    float starExistence = hash(float3(gridID.x, gridID.y, 0.0));
    float isStar = step(0.98, starExistence);

    float offsetX = hash(float3(gridID.x, gridID.y, 1.0)) * 0.4 - 0.2;
    float offsetY = hash(float3(gridID.x, gridID.y, 2.0)) * 0.4 - 0.2;
    float distToStar = length(starLocalPos - float2(offsetX, offsetY));
    
    float sizeRandom = hash(float3(gridID.x, gridID.y, 3.0));
    float starRadius = 0.03 + 0.12 * sizeRandom;
    
    float core = smoothstep(starRadius * 0.3, 0.0, distToStar);
    float glow = smoothstep(starRadius * 1.8, 0.0, distToStar) * 0.5;
    float starShape = core + glow;
    
    float colorRand = hash(float3(gridID.x, gridID.y, 4.0));
    float3 blueStar = float3(0.65, 0.85, 1.0);
    float3 redStar = float3(1.0, 0.65, 0.55);
    float isRed = step(0.85, colorRand);
    float3 starBaseColor = mix(blueStar, redStar, isRed);
    starBaseColor *= (0.6 + 0.4 * hash(float3(gridID.x, gridID.y, 5.0)));
    
    float starVisibility = 1.0 - smoothstep(-0.05, 0.1, sunPos.y + 1.0);
    finalColor += starBaseColor * starShape * isStar * 4.5 * starVisibility;

    // ---------------------------------------------------------
    // 銳利的瑞利散射大氣效果
    // ---------------------------------------------------------
    float3 twilightColor = float3(0.98, 0.22, 0.02);
    float twilightIntensity = smoothstep(-0.2, 0.0, sunPos.y + 1.0) * (1.0 - smoothstep(0.0, 0.3, sunPos.y + 1.0));
    float rayleighBelt = exp(-7.0 * (uv.y + 1.0));
    finalColor += twilightColor * rayleighBelt * twilightIntensity * 3.0;

    // ---------------------------------------------------------
    // 2D 月球本體與真實月相陰影 (修正版)
    // ---------------------------------------------------------
    float distToMoon = length(uv - moonPos);
    float moonRadius = 0.055;
    if (distToMoon < moonRadius && moonPos.y > -1.2) {
        float2 moonLocalPos = (uv - moonPos) / moonRadius;
        float z = sqrt(max(0.0, 1.0 - dot(moonLocalPos, moonLocalPos)));
        float3 fakeNormal = normalize(float3(moonLocalPos.x, moonLocalPos.y, z));
        
        // 🌟 修正 2：利用月相，在 3D 空間中捏造一個精準的虛擬太陽光方向
        float phaseAngle = moonPhase * 6.283185;
        // cos 前面的負號確保當 phase = 0.5 (滿月) 時，光從螢幕正前方 (z = 1.0) 打過來
        float3 phaseLightDir = normalize(float3(sin(phaseAngle), 0.0, -cos(phaseAngle)));
        
        // 將最低亮度提升至 0.18，確保暗面能透出微微的「地照」輪廓
        float illumination = max(0.18, dot(fakeNormal, phaseLightDir));
        float3 moonBodyColor = float3(1.3, 1.3, 1.2) * illumination;
        
        float alpha = smoothstep(moonRadius, moonRadius - 0.002, distToMoon);
        finalColor = mix(finalColor, moonBodyColor, alpha);
    }

    // ---------------------------------------------------------
    // 7. 2D 太陽本體與大氣耀光
    // ---------------------------------------------------------
    float distToSun = length(uv - sunPos);
    
    // 1. 縮小太陽本體 (從 0.06 降到 0.025)
    float sunRadius = 0.02;
    float sunBody = smoothstep(sunRadius, sunRadius - 0.003, distToSun);
    
    // 2. 收束光暈範圍：將 distToSun 乘以 0.8 (原本是 0.45) 讓光暈衰減得更快
    float sunGlow = pow(max(0.0, 1.0 - distToSun * 2), 8.0);
    float3 sunGlowColor = mix(float3(1.0, 0.15, 0.0), float3(1.0, 0.92, 0.65), smoothstep(0.0, 0.3, sunPos.y + 1.0));
    
    if (sunPos.y > -1.2) {
        // 微調耀光強度 (1.8 降為 1.5)
        finalColor += sunGlowColor * sunGlow * 1.5 * (sunPos.y + 1.2);
        finalColor = mix(finalColor, float3(1.0, 1.0, 0.95), sunBody);
    }

    return float4(finalColor, 0.85);
}
