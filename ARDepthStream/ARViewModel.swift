import SwiftUI
import ARKit
import Combine

// The AR processing logic with Metal acceleration
class ARViewModel: NSObject, ObservableObject, ARSessionDelegate {
    // Published properties that SwiftUI will observe
    @Published var rgbImage: UIImage?
    @Published var depthImage: UIImage?
    @Published var statusMessage: String = "Initializing AR Session..."
    @Published var estimatedHeight: String = "Height: N/A"
    
    // AR properties
    private let arSession = ARSession()
    private var configuration = ARWorldTrackingConfiguration()
    private var currentVideoFormat: ARConfiguration.VideoFormat?
    
    // Metal renderer
    private let metalRenderer: MetalRenderer?
    
    // Performance optimization
    private var lastRGBFrameTime: TimeInterval = 0
    private var rgbFrameRateHistory: [Double] = []
    private var frameRateUpdateCounter = 0
    private var frameProcessingCounter = 0
    private let frameProcessingInterval = 2  // Process every Nth frame for better performance
    
    // Settings
    let visualizationMode: VisualizationMode = .rainbow
    
    var depthThreshold: Float = 3.0 {
        didSet {
            // Update visualization if threshold changes
            hasVisualizationChanged = true
        }
    }
    
    private var latestDepthMap: CVPixelBuffer?
    private var latestRgbImage: CVPixelBuffer?
    private var hasNewDepthData = false
    private var hasVisualizationChanged = false
    
    // For depth range calculation
    private var minDepthValue: Float = 0.0
    private var maxDepthValue: Float = 5.0
    private var depthRangeNeedsUpdate = true
    
    override init() {
        // Initialize Metal renderer
        metalRenderer = MetalRenderer()
        
        super.init()
        setupARSession()
    }
    
    private func setupARSession() {
        arSession.delegate = self
        
        // Configure AR session for better performance
        configuration.frameSemantics = [.sceneDepth]
        configuration.planeDetection = [.horizontal]
        
        // Check if device supports depth
        if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            statusMessage = "Device doesn't support scene depth"
        }
    }
    
    func startSession() {
        arSession.run(configuration)
        statusMessage = "Analyzing depth alignment..."
        
        // Reset performance tracking
        lastRGBFrameTime = CACurrentMediaTime()
        rgbFrameRateHistory.removeAll()
        frameRateUpdateCounter = 0
        frameProcessingCounter = 0
    }
    
    func pauseSession() {
        arSession.pause()
    }
    
    // Set video format and restart session
    func setVideoFormat(_ format: ARConfiguration.VideoFormat) {
        guard currentVideoFormat != format else { return }
        
        configuration.videoFormat = format
        currentVideoFormat = format
        
        // Run the session with the new configuration
        arSession.run(configuration)
    }
    
    // ARSessionDelegate methods
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Calculate RGB frame rate
        let currentTime = CACurrentMediaTime()
        let rgbTimeDiff = currentTime - lastRGBFrameTime
        lastRGBFrameTime = currentTime
        let rgbFrameRate = 1.0 / rgbTimeDiff
        
        // Keep track of RGB frame rate history
        rgbFrameRateHistory.append(rgbFrameRate)
        if rgbFrameRateHistory.count > 10 {
            rgbFrameRateHistory.removeFirst()
        }
        
        // Store latest RGB image
        latestRgbImage = frame.capturedImage
        
        // Check if we have new depth data
        if let sceneDepth = frame.sceneDepth {
            // Store depth map
            latestDepthMap = sceneDepth.depthMap
            hasNewDepthData = true
            
            // Calculate depth range (less frequently)
            if depthRangeNeedsUpdate {
                depthRangeNeedsUpdate = false
                
                // Use background queue for depth range calculation
                DispatchQueue.global(qos: .userInitiated).async {
                    self.calculateDepthRange(depthMap: sceneDepth.depthMap)
                }
            }
        }
        
        // Process frames less frequently for better performance (every Nth frame)
        frameProcessingCounter += 1
        if frameProcessingCounter >= frameProcessingInterval || hasVisualizationChanged {
            frameProcessingCounter = 0
            hasVisualizationChanged = false
            processLatestFrame()
        }
        
        // Update status with resolution and frame rate info (less frequently to improve performance)
        frameRateUpdateCounter += 1
        if frameRateUpdateCounter >= 30 {  // Update stats less frequently
            frameRateUpdateCounter = 0
            
            if let rgbImage = latestRgbImage, let depthMap = latestDepthMap {
                let rgbWidth = CVPixelBufferGetWidth(rgbImage)
                let rgbHeight = CVPixelBufferGetHeight(rgbImage)
                let depthWidth = CVPixelBufferGetWidth(depthMap)
                let depthHeight = CVPixelBufferGetHeight(depthMap)
                
                // Calculate average RGB frame rate
                let avgRGBFrameRate = rgbFrameRateHistory.reduce(0, +) / Double(rgbFrameRateHistory.count)
                
                // Find the lowest horizontal plane
                let planeAnchors = session.currentFrame?.anchors.compactMap { $0 as? ARPlaneAnchor }
                let horizontalPlanes = planeAnchors?.filter { $0.alignment == .horizontal }
                if let lowestPlane = horizontalPlanes?.min(by: { $0.transform.columns.3.y < $1.transform.columns.3.y }) {
                    // The height is the difference between the camera's current position and the plane's position.
                    let cameraY = frame.camera.transform.columns.3.y
                    let floorY = lowestPlane.transform.columns.3.y
                    let height = cameraY - floorY
                    
                    DispatchQueue.main.async {
                        self.estimatedHeight = String(format: "Height: %.2fm", height)
                    }
                }
                
                DispatchQueue.main.async {
                    self.statusMessage = String(format: "RGB FPS: %.1f\nRGB: %d×%d\nDepth: %d×%d\nMax Depth: %.1fm",
                                              avgRGBFrameRate, rgbWidth, rgbHeight,
                                              depthWidth, depthHeight, self.depthThreshold)
                }
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = "AR Session Failed: \(error.localizedDescription)"
        }
    }
    
    // Calculate min and max depth values (optimized for performance)
    private func calculateDepthRange(depthMap: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        // Get dimensions
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return
        }
        
        // Use sparse sampling for better performance (sample fewer pixels)
        let sampling = 16  // Increased sampling interval for better performance
        
        var localMin: Float = Float.greatestFiniteMagnitude
        var localMax: Float = 0.0
        
        // Process in standard non-SIMD approach
        for y in stride(from: 0, to: height, by: sampling) {
            for x in stride(from: 0, to: width, by: sampling) {
                let pixelOffset = y * bytesPerRow + x * MemoryLayout<Float>.size
                let depthValue = baseAddress.load(fromByteOffset: pixelOffset, as: Float.self)
                
                if depthValue > 0 && depthValue <= depthThreshold && depthValue.isFinite && !depthValue.isNaN {
                    localMin = min(localMin, depthValue)
                    localMax = max(localMax, depthValue)
                }
            }
        }
        
        // Update the main depth range values if we found valid values
        if localMin < Float.greatestFiniteMagnitude {
            minDepthValue = localMin
            maxDepthValue = localMax
        } else {
            // Fallback to defaults
            minDepthValue = 0.0
            maxDepthValue = depthThreshold
        }
    }
    
    private func processLatestFrame() {
        guard let rgbBuffer = latestRgbImage, let depthBuffer = latestDepthMap else {
            return
        }
        
        // Early return if Metal renderer isn't available
        guard let renderer = metalRenderer else {
            statusMessage = "Metal renderer not available"
            return
        }
        
        // Use Metal to process depth visualization
        if let processedDepthImage = renderer.processDepth(
            depthBuffer: depthBuffer,
            minDepth: minDepthValue,
            maxDepth: maxDepthValue,
            threshold: depthThreshold,
            mode: visualizationMode
        ) {
            DispatchQueue.main.async {
                self.depthImage = processedDepthImage
            }
        }
        
        // Use Metal to process RGB with depth mask
        if let processedRGBImage = renderer.processRGBWithDepthMask(
            rgbBuffer: rgbBuffer,
            depthBuffer: depthBuffer,
            threshold: depthThreshold
        ) {
            DispatchQueue.main.async {
                self.rgbImage = processedRGBImage
            }
        }
        
        // Schedule depth range update (less frequently)
        if hasNewDepthData {
            hasNewDepthData = false
            depthRangeNeedsUpdate = true
        }
    }
    
    func captureAndSaveFrame() {
        guard let frame = arSession.currentFrame,
              let depthBuffer = frame.sceneDepth?.depthMap else {
            print("No depth or frame available")
            return
        }

        let rgbBuffer = frame.capturedImage
        let intrinsics = frame.camera.intrinsics
        let timestamp = Int(Date().timeIntervalSince1970)

        // Get camera transform for gravity alignment
        let cameraTransform = frame.camera.transform

        // Find the lowest horizontal plane to calculate height and floor level
        var height: Float = 0.0
        var floorY: Float = 0.0
        let planeAnchors = arSession.currentFrame?.anchors.compactMap { $0 as? ARPlaneAnchor }
        let horizontalPlanes = planeAnchors?.filter { $0.alignment == .horizontal }
        if let lowestPlane = horizontalPlanes?.min(by: { $0.transform.columns.3.y < $1.transform.columns.3.y }) {
            let cameraY = cameraTransform.columns.3.y
            floorY = lowestPlane.transform.columns.3.y
            height = cameraY - floorY
        }

        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let savesFolder = documents.appendingPathComponent("Saves", isDirectory: true)

        // Ensure Saves folder exists
        if !fileManager.fileExists(atPath: savesFolder.path) {
            try? fileManager.createDirectory(at: savesFolder, withIntermediateDirectories: true)
        }

        // Create timestamped folder
        let targetFolder = savesFolder.appendingPathComponent("\(timestamp)", isDirectory: true)
        try? fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        // File names
        let rgbURL = targetFolder.appendingPathComponent("rgb_\(timestamp).png")
        let plyURL = targetFolder.appendingPathComponent("depth_\(timestamp).ply")
        let heightURL = targetFolder.appendingPathComponent("height_\(timestamp).txt")

        // Save height and pose file
        let heightAndPoseInfo = "Height: \(height)\n\nPose Transform Matrix:\n\(String(describing: cameraTransform))"
        try? heightAndPoseInfo.write(to: heightURL, atomically: true, encoding: .utf8)

        // Save content using the corrected coordinate system
        saveRGBImage(rgbBuffer, to: rgbURL)

        // Generate colored point cloud using the corrected function
        let points = generateColoredPointCloud(depth: depthBuffer, rgb: rgbBuffer, rgbIntrinsics: intrinsics, cameraTransform: cameraTransform, maxDepth: self.depthThreshold)

        // Write PLY file with proper formatting
        writePLY(points: points, to: plyURL)

        // Show confirmation popup
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Saved",
                message: "Saved RGB and PLY files to timestamp \(timestamp)\nPoints generated: \(points.count)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))

            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = scene.windows.first?.rootViewController {
                rootVC.present(alert, animated: true)
            }
        }
    }
}
