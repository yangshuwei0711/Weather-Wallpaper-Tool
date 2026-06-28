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

// 3. 片段著色器 (Fragment Shader)：這就是我們未來算大氣散射的地方！
fragment float4 fragmentMain(RasterizerData in [[stage_in]]) {
    // 顯影測試：我們用 UV 座標的 X 與 Y 來決定紅色與綠色的強度
    // 這會畫出一個從左上到右下變化的漂亮漸層
    return float4(in.uv.x, in.uv.y, 0.8, 0.6); // (R, G, B, Alpha)
}


