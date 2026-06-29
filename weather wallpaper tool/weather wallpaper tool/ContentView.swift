import SwiftUI
import MetalKit
import Combine

struct ContentView: View {
    // 從清晨 4:30 開始，準備迎接 5:30 的日出霞光
    @State private var timeOfDay: Float = 4.5
    
    // 建立一個每 0.05 秒觸發一次的計時器
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景的 Metal 渲染層
            MetalView(timeOfDay: $timeOfDay)
                .ignoresSafeArea()
            
            // 狀態顯示面板
            VStack(spacing: 8) {
                Text(String(format: "自動縮時攝影中: %02d:%02d", Int(timeOfDay), Int((timeOfDay - floor(timeOfDay)) * 60)))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                Text("放下鍵盤與滑鼠，欣賞你的宇宙 🌌")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
            .padding(.bottom, 40)
        }
        // 🌟 接收計時器訊號，自動快轉時間
        .onReceive(timer) { _ in
            // 每次推進 0.02 小時 (約 1.2 分鐘)，製造平滑的日夜交替
            timeOfDay += 0.02
            
            // 如果超過 24 小時，就回到 0 點重新開始
            if timeOfDay >= 24.0 {
                timeOfDay = 0.0
            }
        }
    }
}

// 下方的 MetalView 與 Coordinator 保持最乾淨的狀態，不用做任何按鍵處理
struct MetalView: NSViewRepresentable {
    @Binding var timeOfDay: Float
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.delegate = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
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
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let pipelineState = self.pipelineState else { return }
        
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        let width = Float(view.drawableSize.width)
        let height = max(1.0, Float(view.drawableSize.height))
        var aspect = width / height
        
        let currentTime = parent.timeOfDay
        let sunriseTime: Float = 5.5
        let sunsetTime: Float = 18.5
        var timeData = SIMD3<Float>(currentTime, sunriseTime, sunsetTime)
        
        var elapsedTime = Float(Date().timeIntervalSince(startDate))
        var moonPhase = MoonMath.getMoonPhase(date: Date())
        
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
