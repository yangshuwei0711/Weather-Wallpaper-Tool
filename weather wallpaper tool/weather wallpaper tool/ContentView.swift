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
        
        // --- 1. 計算當下太陽向量 ---
        // (你可以把 Date() 換成其他時間來測試日出日落，例如 Date().addingTimeInterval(3600 * 8) 來快進 8 小時)
        // 快轉 10 小時 (10小時 * 60分 * 60秒)
        let futureDate = Date().addingTimeInterval(10 * 3600)
        var sunVector = SunMath.getSunVector(date: futureDate, latitude: 24.1, longitude: 120.68)
        
        encoder.setRenderPipelineState(pipelineState)
        
        // --- 2. 開通數據通道：將太陽向量傳送給 GPU 的 Fragment Shader ---
        // 我們將它放在 index: 0 的位置，長度就是一個 SIMD3<Float> 的大小
        encoder.setFragmentBytes(&sunVector, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        
        // 3. 發出繪圖指令
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
