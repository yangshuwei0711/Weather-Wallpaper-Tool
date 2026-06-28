import SwiftUI
import MetalKit

struct ContentView: View {
    var body: some View {
        MetalView()
            .edgesIgnoringSafeArea(.all)
    }
}

struct MetalView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        if let device = MTLCreateSystemDefaultDevice() {
            mtkView.device = device
        }
        
        // 測試：計算當下台中大里地區的太陽向量
        let sunVec = SunMath.getSunVector(date: Date(), latitude: 24.1, longitude: 120.68)
        print("🌞 當前太陽向量: \(sunVec)")
        
        let moonVec = MoonMath.getMoonVector(date: Date(), latitude: 24.1, longitude: 120.68)
        print("🌙 當前月球向量: \(moonVec)")
        
        let phase = MoonMath.getMoonPhase(date: Date())
        print("🌒 當前月相進度: \(phase) (0=新月, 0.5=滿月)")
        
        // 允許圖層透明
        mtkView.wantsLayer = true
        mtkView.layer?.isOpaque = false
        mtkView.layer?.backgroundColor = NSColor.clear.cgColor
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        // 將渲染的控制權交給 Coordinator
        mtkView.delegate = context.coordinator
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}
    
    // 建立 Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

class Coordinator: NSObject, MTKViewDelegate {
    var parent: MetalView
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState? // 新增：渲染管線狀態
    
    init(_ parent: MetalView) {
        self.parent = parent
        super.init()
        
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        self.commandQueue = device.makeCommandQueue()
        
        // --- 新增：載入 Metal 檔案並建立渲染管線 ---
        // 抓取專案裡的 default library (會自動編譯 .metal 檔)
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexMain"),
              let fragmentFunction = library.makeFunction(name: "fragmentMain") else {
            print("找不到 Shader 函數！請檢查命名。")
            return
        }
        
        // 設定管線的規則
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        // 確保顏色格式與視圖一致
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // 開啟 Alpha 混合 (Blending) 這樣才能呈現透明度！
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        // 編譯這個管線狀態
        self.pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let pipelineState = self.pipelineState else { return }
        
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        // 1. 獲取當前即時的天體觀測數據（以台中大里座標為例）
        var sunVector = SunMath.getSunVector(date: Date(), latitude: 24.1, longitude: 120.68)
        var moonVector = MoonMath.getMoonVector(date: Date(), latitude: 24.1, longitude: 120.68)
        var moonPhase = MoonMath.getMoonPhase(date: Date())
        
        var aspect = Float(view.drawableSize.width / view.drawableSize.height)
        
        encoder.setRenderPipelineState(pipelineState)
        
        // 2. 開通多軌數據通道
        // Metal 的 float3 對齊格式為 16 bytes，Swift 的 SIMD3<Float> 跨距(stride)亦為 16 bytes，兩者完美對接
        encoder.setFragmentBytes(&sunVector, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&moonVector, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
        encoder.setFragmentBytes(&moonPhase, length: MemoryLayout<Float>.size, index: 2)
        
        encoder.setFragmentBytes(&aspect, length: MemoryLayout<Float>.size, index: 3)
        
        // 3. 執行繪圖
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
