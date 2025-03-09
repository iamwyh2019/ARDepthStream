import SwiftUI
import ARKit
import Combine

struct ContentView: View {
    @StateObject private var arViewModel = ARViewModel()
    @State private var overlayOpacity: Double = 0.5
    @State private var visualizationMode: VisualizationMode = .rainbow
    @State private var showInfo = false
    
    var body: some View {
        ZStack {
            // Base layer - RGB camera feed
            if let rgbImage = arViewModel.rgbImage {
                Image(uiImage: rgbImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .rotationEffect(.degrees(90))  // Rotate the image 90 degrees clockwise
            }
            
            // Overlay layer - Depth visualization
            if let depthImage = arViewModel.depthImage {
                Image(uiImage: depthImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(overlayOpacity)
                    .rotationEffect(.degrees(90))  // Rotate the depth image as well
            }
            
            // UI Controls
            VStack {
                // Info at the top
                HStack {
                    Text(arViewModel.statusMessage)
                        .font(.footnote)
                        .padding(6)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    Button(action: { showInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }
                .padding()
                
                Spacer()
                
                // Bottom controls
                VStack {
                    // Opacity slider
                    HStack {
                        Text("Opacity")
                            .foregroundColor(.white)
                        
                        Slider(value: $overlayOpacity, in: 0...1)
                    }
                    .padding(.horizontal)
                    
                    // Visualization mode picker
                    Picker("Mode", selection: $visualizationMode) {
                        Text("Rainbow").tag(VisualizationMode.rainbow)
                        Text("Heat").tag(VisualizationMode.heat)
                        Text("Grayscale").tag(VisualizationMode.grayscale)
                        Text("Edge").tag(VisualizationMode.edge)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .onChange(of: visualizationMode) { newMode in
                        arViewModel.visualizationMode = newMode
                    }
                }
                .padding(.bottom, 30)
                .background(Color.black.opacity(0.5))
            }
        }
        .statusBar(hidden: true)  // Hide the status bar
        .edgesIgnoringSafeArea(.all)  // Make the app full screen
        .persistentSystemOverlays(.hidden)  // This hides the home indicator
        .onAppear {
            arViewModel.startSession()
            
            // Configure for full screen and hide home indicator
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
        }
        .onDisappear {
            arViewModel.pauseSession()
        }
        .alert(isPresented: $showInfo) {
            Alert(
                title: Text("Depth Visualization Info"),
                message: Text("This app shows RGB and depth data alignment from iPhone LiDAR.\n\n- Use the slider to adjust overlay opacity\n- Try different visualization modes\n- Notice any misalignment between RGB and depth data\n\nPerfect alignment would show depth data precisely matching objects in the RGB image."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

// The AR processing logic is separated into a view model
class ARViewModel: NSObject, ObservableObject, ARSessionDelegate {
    // Published properties that SwiftUI will observe
    @Published var rgbImage: UIImage?
    @Published var depthImage: UIImage?
    @Published var statusMessage: String = "Initializing AR Session..."
    
    // AR properties
    private let arSession = ARSession()
    private let configuration = ARWorldTrackingConfiguration()
    private let ciContext = CIContext()
    
    // Performance monitoring
    private var lastFrameTime: TimeInterval = 0
    private var frameRateHistory: [Double] = []
    private var frameRateUpdateCounter = 0
    
    // Settings
    var visualizationMode: VisualizationMode = .rainbow {
        didSet {
            // Update visualization if mode changes
            processLatestFrame()
        }
    }
    
    private var latestDepthMap: CVPixelBuffer?
    private var latestRgbImage: CVPixelBuffer?
    
    override init() {
        super.init()
        setupARSession()
    }
    
    private func setupARSession() {
        arSession.delegate = self
        
        // Configure AR session for better performance
        configuration.frameSemantics = [.sceneDepth]  // Removed .smoothedSceneDepth for better performance
        
        // Check if device supports depth
        if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            statusMessage = "Device doesn't support scene depth"
        }
    }
    
    func startSession() {
        arSession.run(configuration)
        statusMessage = "Analyzing depth alignment..."
    }
    
    func pauseSession() {
        arSession.pause()
    }
    
    // ARSessionDelegate methods
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Calculate frame rate
        let currentTime = CACurrentMediaTime()
        let timeDiff = currentTime - lastFrameTime
        lastFrameTime = currentTime
        let frameRate = 1.0 / timeDiff
        
        // Keep track of frame rate history (last 10 frames)
        frameRateHistory.append(frameRate)
        if frameRateHistory.count > 10 {
            frameRateHistory.removeFirst()
        }
        
        // Store latest frame data
        latestRgbImage = frame.capturedImage
        latestDepthMap = frame.sceneDepth?.depthMap
        
        // Process the frame (optimized version)
        processLatestFrame()
        
        // Update status with resolution info (less frequently to improve performance)
        frameRateUpdateCounter += 1
        if frameRateUpdateCounter >= 10 {  // Update stats every 10 frames
            frameRateUpdateCounter = 0
            
            if let rgbImage = latestRgbImage, let depthMap = latestDepthMap {
                let rgbWidth = CVPixelBufferGetWidth(rgbImage)
                let rgbHeight = CVPixelBufferGetHeight(rgbImage)
                let depthWidth = CVPixelBufferGetWidth(depthMap)
                let depthHeight = CVPixelBufferGetHeight(depthMap)
                
                // Calculate average frame rate
                let avgFrameRate = frameRateHistory.reduce(0, +) / Double(frameRateHistory.count)
                
                DispatchQueue.main.async {
                    self.statusMessage = String(format: "FPS: %.1f\nRGB: %d×%d\nDepth: %d×%d",
                                               avgFrameRate, rgbWidth, rgbHeight, depthWidth, depthHeight)
                }
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = "AR Session Failed: \(error.localizedDescription)"
        }
    }
    
    private func processLatestFrame() {
        guard let rgbBuffer = latestRgbImage, let depthBuffer = latestDepthMap else {
            return
        }
        
        // Process RGB image (more efficiently)
        let processedRgbImage = imageFromPixelBuffer(rgbBuffer)
        
        // Process depth image with optimizations
        let processedDepthImage = visualizeDepth(depthMap: depthBuffer, mode: visualizationMode)
        
        // Update the published properties on the main thread
        DispatchQueue.main.async {
            self.rgbImage = processedRgbImage
            self.depthImage = processedDepthImage
        }
    }
    
    // MARK: - Image Processing (Optimized)
    
    private func imageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Use a more efficient approach for converting to UIImage
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func visualizeDepth(depthMap: CVPixelBuffer, mode: VisualizationMode) -> UIImage? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Increase sampling rate for better performance
        let sampling = 8  // Process every 8th pixel for better performance
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        // Get a pointer to the depth data
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }
        
        // Create a bitmap context
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Get the bytes per row for the depth buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        // Find min and max depth values for normalization (with sparse sampling)
        var minDepth: Float = .infinity
        var maxDepth: Float = 0.0
        
        for y in stride(from: 0, to: height, by: sampling) {
            for x in stride(from: 0, to: width, by: sampling) {
                let pixelOffset = y * bytesPerRow + x * MemoryLayout<Float32>.size
                let depthValue = baseAddress.load(fromByteOffset: pixelOffset, as: Float32.self)
                
                if depthValue > 0 && depthValue.isFinite && !depthValue.isNaN {
                    minDepth = min(minDepth, depthValue)
                    maxDepth = max(maxDepth, depthValue)
                }
            }
        }
        
        // If we didn't find any valid depth values, use defaults
        if minDepth == .infinity {
            minDepth = 0.0
            maxDepth = 5.0 // 5 meters is a typical max range for LiDAR
        }
        
        // Calculate depth range for normalization
        let depthRange = maxDepth - minDepth
        
        // Create output data buffer
        var outputData = [UInt8](repeating: 0, count: width * height * 4)
        
        // Process each pixel (with optimized sampling)
        for y in stride(from: 0, to: height, by: 2) {  // Process every other pixel for better performance
            for x in stride(from: 0, to: width, by: 2) {
                let pixelOffset = y * bytesPerRow + x * MemoryLayout<Float32>.size
                let depthValue = baseAddress.load(fromByteOffset: pixelOffset, as: Float32.self)
                
                // Process the current pixel
                processPixel(x: x, y: y, depthValue: depthValue, minDepth: minDepth, depthRange: depthRange,
                            width: width, outputData: &outputData, mode: mode)
                
                // Also assign the same color to neighboring pixels (2x2 block) for efficiency
                processPixel(x: x+1, y: y, depthValue: depthValue, minDepth: minDepth, depthRange: depthRange,
                            width: width, outputData: &outputData, mode: mode)
                processPixel(x: x, y: y+1, depthValue: depthValue, minDepth: minDepth, depthRange: depthRange,
                            width: width, outputData: &outputData, mode: mode)
                processPixel(x: x+1, y: y+1, depthValue: depthValue, minDepth: minDepth, depthRange: depthRange,
                            width: width, outputData: &outputData, mode: mode)
            }
        }
        
        // Create CGImage from the processed data
        guard let dataProvider = CGDataProvider(data: Data(outputData) as CFData) else {
            return nil
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // Helper function to process an individual pixel (with safety bounds checking)
    private func processPixel(x: Int, y: Int, depthValue: Float, minDepth: Float, depthRange: Float,
                             width: Int, outputData: inout [UInt8], mode: VisualizationMode) {
        // Safety check for bounds
        guard x >= 0 && y >= 0 && x < width && y < width * 4 / 4 else { return }
        
        let outputIndex = (y * width + x) * 4
        
        // Safety check for outputIndex
        guard outputIndex >= 0 && outputIndex + 3 < outputData.count else { return }
        
        if depthValue > 0 && depthValue.isFinite && !depthValue.isNaN {
            // Normalize depth value between 0 and 1
            let normalizedDepth = (depthValue - minDepth) / depthRange
            
            switch mode {
            case .rainbow:
                // Rainbow colormap
                let rgb = depthToRainbow(depth: normalizedDepth)
                outputData[outputIndex] = UInt8(min(255, max(0, rgb.r * 255)))     // R
                outputData[outputIndex + 1] = UInt8(min(255, max(0, rgb.g * 255))) // G
                outputData[outputIndex + 2] = UInt8(min(255, max(0, rgb.b * 255))) // B
                outputData[outputIndex + 3] = 255                                  // A
                
            case .heat:
                // Heat colormap (blue to red)
                let rgb = depthToHeatmap(depth: normalizedDepth)
                outputData[outputIndex] = UInt8(min(255, max(0, rgb.r * 255)))     // R
                outputData[outputIndex + 1] = UInt8(min(255, max(0, rgb.g * 255))) // G
                outputData[outputIndex + 2] = UInt8(min(255, max(0, rgb.b * 255))) // B
                outputData[outputIndex + 3] = 255                                  // A
                
            case .grayscale:
                // Grayscale with safety bounds
                let grayValue = UInt8(min(255, max(0, normalizedDepth * 255)))
                outputData[outputIndex] = grayValue     // R
                outputData[outputIndex + 1] = grayValue // G
                outputData[outputIndex + 2] = grayValue // B
                outputData[outputIndex + 3] = 255       // A
                
            case .edge:
                // Simplified edge detection for better performance
                outputData[outputIndex] = UInt8(min(255, max(0, normalizedDepth * 255)))     // R
                outputData[outputIndex + 1] = UInt8(min(255, max(0, normalizedDepth * 255))) // G
                outputData[outputIndex + 2] = UInt8(min(255, max(0, normalizedDepth * 255))) // B
                outputData[outputIndex + 3] = 255                                           // A
            }
        } else {
            // Invalid depth - make transparent
            outputData[outputIndex + 3] = 0 // A = 0
        }
    }
    
    // Colormap functions
    private func depthToRainbow(depth: Float) -> (r: Float, g: Float, b: Float) {
        let a = (1.0 - depth) * 4.0 // Invert and scale to get blue at far and red at near
        let x = min(max(a - Float(Int(a)), 0.0), 1.0)
        let c = Int(a) % 4
        
        switch c {
        case 0: return (1.0, x, 0.0)      // Red to Yellow
        case 1: return (1.0 - x, 1.0, 0.0) // Yellow to Green
        case 2: return (0.0, 1.0, x)      // Green to Cyan
        default: return (0.0, 1.0 - x, 1.0) // Cyan to Blue
        }
    }
    
    private func depthToHeatmap(depth: Float) -> (r: Float, g: Float, b: Float) {
        // Heatmap: close is red, far is blue
        let invertedDepth = 1.0 - depth
        
        return (
            r: min(max(1.5 * invertedDepth - 0.5, 0.0), 1.0),
            g: min(max(1.5 * abs(invertedDepth - 0.5), 0.0), 1.0),
            b: min(max(1.5 * (1.0 - invertedDepth) - 0.5, 0.0), 1.0)
        )
    }
}

enum VisualizationMode {
    case rainbow
    case heat
    case grayscale
    case edge
}
