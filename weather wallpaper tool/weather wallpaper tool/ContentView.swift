import SwiftUI
import MetalKit

struct ContentView: View {
    // 預設將滑桿時間設為中午 12 點
    @State private var timeOfDay: Float = 12.0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景的 Metal 渲染層
            MetalView(timeOfDay: $timeOfDay)
                .ignoresSafeArea()
            
            // 浮動時間控制面板
            VStack(spacing: 8) {
                Text(String(format: "模擬時間: %02d:%02d", Int(timeOfDay), Int((timeOfDay - floor(timeOfDay)) * 60)))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                Slider(value: $timeOfDay, in: 0...24)
                    .tint(.orange)
            }
            .padding()
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
            .padding(.bottom, 40)
            .padding(.horizontal, 60)
        }
    }
}

struct MetalView: NSViewRepresentable {
    @Binding var timeOfDay: Float
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        
        // 🌟 確保像素格式與 Pipeline 匹配
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.delegate = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // 即時把 SwiftUI 的滑桿數值同步給 Coordinator
        context.coordinator.parent = self
    }
}

class Coordinator: NSObject, MTKViewDelegate {
    var parent: MetalView
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?
    let startDate = Date()
    
    init(_ parent: MetalView) {
        self.parent = parent
        super.init()
        
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device.makeCommandQueue()
        
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertexMain")
        let fragmentFunction = library?.makeFunction(name: "fragmentMain")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // 確保支援透明度混合，這樣才能隱約看見你的桌布底圖
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("❌ Pipeline 編譯失敗: \(error)")
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        // 如果這裡 guard 失敗，畫面就會完全空白
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let pipelineState = self.pipelineState else { return }
        
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        // 🌟 防呆機制：確保高度大於 0，避免產生 NaN 黑洞
        let width = Float(view.drawableSize.width)
        let height = max(1.0, Float(view.drawableSize.height))
        var aspect = width / height
        
        // 讀取時間變數
        let currentTime = parent.timeOfDay
        let sunriseTime: Float = 5.5
        let sunsetTime: Float = 18.5
        var timeData = SIMD3<Float>(currentTime, sunriseTime, sunsetTime)
        
        var elapsedTime = Float(Date().timeIntervalSince(startDate))
        var moonPhase = MoonMath.getMoonPhase(date: Date())
        
        // 綁定 Buffer 通道
        encoder.setFragmentBytes(&timeData, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&moonPhase, length: MemoryLayout<Float>.size, index: 1)
        encoder.setFragmentBytes(&aspect, length: MemoryLayout<Float>.size, index: 2)
        encoder.setFragmentBytes(&elapsedTime, length: MemoryLayout<Float>.size, index: 3)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
