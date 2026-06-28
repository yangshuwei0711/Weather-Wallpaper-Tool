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

// 頂點著色器保持不變（生成全螢幕畫布）
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

// 片段著色器：球面幾何與天體光學計算
fragment float4 fragmentMain(RasterizerData in [[stage_in]],
                             constant float3& sunDirection [[buffer(0)]],
                             constant float3& moonDirection [[buffer(1)]],
                             constant float& moonPhase [[buffer(2)]],
                             constant float& aspect [[buffer(3)]]) {

    // 1. 建立 1:1 的完美物理畫布 (保證畫出來的距離計算絕對是正圓)
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect; // X 軸乘上螢幕比例，徹底抵銷任何螢幕拉伸

    // 2. 畫布底色 (保留日夜漸層)
    float sunHeight = sunDirection.y;
    float3 daySky = float3(0.4, 0.65, 0.95);
    float3 nightSky = float3(0.02, 0.04, 0.08);
    float skyMix = smoothstep(-0.2, 0.2, sunHeight);
    float3 finalColor = mix(nightSky, daySky, skyMix);

    // ---------------------------------------------------------
    // 3. 你的好點子：2D 圓弧軌跡 (Screen-Space Billboard)
    // ---------------------------------------------------------
    
    // 直接拿 3D 向量的 x, y 當作螢幕上的 2D 座標，並稍微放大軌跡範圍讓它繞著螢幕跑
    float arcWidth = 1.8;
    float arcHeight = 1.5;
    float2 moonPos = float2(moonDirection.x * arcWidth, moonDirection.y * arcHeight);
    
    // 計算當前像素到月亮中心的 2D 距離
    float distToMoon = length(uv - moonPos);
    float moonRadius = 0.08; // 鎖死月亮的大小

    // 如果該像素在月亮半徑內
    if (distToMoon < moonRadius) {
        
        // 【圖學黑科技】：在 2D 平面圓形上，憑空捏造出 3D 立體法向量！
        // 這樣我們就不需要真正的 3D 球體，也能算出完美的月相盈虧
        float2 localPos = (uv - moonPos) / moonRadius; // 將座標映射到 -1 ~ 1
        float z = sqrt(max(0.0, 1.0 - dot(localPos, localPos))); // 利用畢氏定理算出球面凸起的 Z 軸
        float3 fakeNormal = normalize(float3(localPos.x, localPos.y, z));

        // 用這顆捏造的 3D 法向球去接太陽光，算出真實的月相陰影
        float illumination = max(0.12, dot(fakeNormal, sunDirection));
        float3 moonBodyColor = float3(1.2, 1.2, 1.1) * illumination;

        // 抗鋸齒：讓圓形的邊緣平滑過渡，不要有像素狗牙
        float alpha = smoothstep(moonRadius, moonRadius - 0.002, distToMoon);
        finalColor = mix(finalColor, moonBodyColor, alpha);
    }
    
    // --- 附贈：太陽的光暈也可以用相同的 2D 邏輯畫出來 ---
    float2 sunPos = float2(sunDirection.x * arcWidth, sunDirection.y * arcHeight);
    float distToSun = length(uv - sunPos);
    float sunGlow = pow(max(0.0, 1.0 - distToSun * 0.6), 5.0); // 太陽的擴散光暈
    finalColor += float3(1.0, 0.75, 0.45) * sunGlow * max(0.0, skyMix);

    return float4(finalColor, 0.8);
}

