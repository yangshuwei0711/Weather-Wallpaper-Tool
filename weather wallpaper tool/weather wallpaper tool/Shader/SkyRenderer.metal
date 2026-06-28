//
//  SkyRenderer.metal
//  weather wallpaper tool
//
//  Created by 楊舒瑋 on 2026/6/29.
//

#include <metal_stdlib>
using namespace metal;

// 1. 定義從頂點函數傳遞到片段函數的資料
struct RasterizerData {
    float4 position [[position]]; // 螢幕上的座標
    float2 uv;                    // 畫布的 UV 比例 (0.0 ~ 1.0)
};

// 2. 頂點著色器 (Vertex Shader)：負責生出一個覆蓋全螢幕的畫布
vertex RasterizerData vertexMain(uint vertexID [[vertex_id]]) {
    // 圖學小技巧：用三個點拉出一個覆蓋全螢幕的巨大三角形
    float2 positions[3] = {
        float2(-1.0, -1.0), // 左下
        float2( 3.0, -1.0), // 右下 (延伸到螢幕外)
        float2(-1.0,  3.0)  // 左上 (延伸到螢幕外)
    };
    
    RasterizerData out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    // 計算 UV 座標，讓左上角是 (0,0)，右下角是 (1,1)
    out.uv = out.position.xy * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

// 接收端：注意我們多了一個參數 sunDirection，並且標註它來自 [[buffer(0)]]
fragment float4 fragmentMain(RasterizerData in [[stage_in]],
                             constant float3& sunDirection [[buffer(0)]]) {
    
    // 抓出太陽的高度 (Y 軸)
    float sunHeight = sunDirection.y;
    
    // 定義白天的天空顏色 (明亮的淺藍色) 與晚上的天空顏色 (深邃的暗藍色)
    float3 dayColor = float3(0.5, 0.7, 1.0);
    float3 nightColor = float3(0.05, 0.1, 0.2);
    
    // smoothstep 是一個非常強大的圖學函數：
    // 當太陽在 -0.2 (地平線下) 到 0.2 (地平線上) 之間時，產生 0.0 ~ 1.0 的平滑漸變
    float mixFactor = smoothstep(-0.2, 0.2, sunHeight);
    
    // 根據太陽高度混合顏色
    float3 finalColor = mix(nightColor, dayColor, mixFactor);
    
    // 輸出最終顏色，設定不透明度為 0.8
    return float4(finalColor, 0.8);
}


