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
        
        // 這次我們把背景塗成完全透明，讓 Shader 自己決定顏色
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        // --- 核心指令區 ---
        encoder.setRenderPipelineState(pipelineState)
        // 告訴 GPU：畫 3 個頂點（就是我們在 Shader 寫的那個大三角形）
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        // ------------------
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
