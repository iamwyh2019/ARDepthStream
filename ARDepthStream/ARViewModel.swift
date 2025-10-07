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
    @Published var phoneCoordinate: String = "Coord: N/A"
    @Published var phoneOrientationQuat: String = "Quat: N/A"
    @Published var phoneOrientationEuler: String = "Euler: N/A"
    @Published var isSavingRecording = false
    
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
    
    // Recording properties
    private let recordingFPS: TimeInterval = 5.0
    @Published var isRecording = false
    private var lastRecordingTime: TimeInterval = 0
    private var recordingSessionFolder: URL?
    private var recordingFrames: [(timestamp: Double, position: SIMD3<Float>, yaw: Float, points: [(SIMD3<Float>, SIMD3<UInt8>)])] = []
    private var currentHeight: Float = 0.0
    private var lockedHeight: Float?

    // SLAM-style world frame (set when AR session starts)
    private var worldForwardAtStart: SIMD3<Float>?  // Initial forward direction (horizontal)
    
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

        // Reset world frame (will be set on first frame)
        worldForwardAtStart = nil
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

        // Process recording if active
        if isRecording {
            processRecording(frame: frame)
        }
        
        // Update status with resolution and frame rate info (less frequently to improve performance)
        frameRateUpdateCounter += 1
        if frameRateUpdateCounter >= 30 {  // Update stats less frequently
            frameRateUpdateCounter = 0
            
            if let rgbImage = latestRgbImage, let depthMap = latestDepthMap {
                let cameraTransform = frame.camera.transform

                // --- Get current camera forward direction (gravity-aligned) ---
                let cameraRotation = simd_float3x3(
                    simd_make_float3(cameraTransform.columns.0),
                    simd_make_float3(cameraTransform.columns.1),
                    simd_make_float3(cameraTransform.columns.2)
                )
                let cameraToRobot = simd_float3x3(
                    SIMD3<Float>(0, 0, -1),  // Robot X (forward) = Camera -Z
                    SIMD3<Float>(1, 0, 0),   // Robot Y (left) = Camera X
                    SIMD3<Float>(0, 1, 0)    // Robot Z (up) = Camera Y
                )
                let robotInWorld = cameraRotation * cameraToRobot
                let worldUp = SIMD3<Float>(0, 1, 0)
                let currentForwardInWorld = robotInWorld.columns.0
                let forwardProjected = currentForwardInWorld - dot(currentForwardInWorld, worldUp) * worldUp
                let currentForward = normalize(forwardProjected)

                // Initialize world frame on first frame (define X, Y axes)
                if self.worldForwardAtStart == nil {
                    self.worldForwardAtStart = currentForward
                }

                guard let initialForward = self.worldForwardAtStart else {
                    return
                }

                // Define world axes based on initial forward direction
                let worldX = initialForward  // X = forward (initial direction)
                let worldY = cross(worldUp, initialForward)  // Y = left (perpendicular to forward)
                let worldZ = worldUp  // Z = up (gravity)

                // Transform ARKit position to your coordinate system
                let arkitPosition = cameraTransform.columns.3
                let arkitPos3 = SIMD3<Float>(arkitPosition.x, arkitPosition.y, arkitPosition.z)
                let slamPosition = SIMD3<Float>(
                    dot(arkitPos3, worldX),  // X component (forward)
                    dot(arkitPos3, worldY),  // Y component (left)
                    dot(arkitPos3, worldZ)   // Z component (up)
                )
                let coordString = String(format: "Coord: [%.2f, %.2f, %.2f]", slamPosition.x, slamPosition.y, slamPosition.z)

                // --- Yaw relative to initial forward direction ---
                // Positive yaw = turning left
                let cosYaw = dot(currentForward, initialForward)
                let sinYaw = dot(cross(currentForward, initialForward), worldUp)
                let yaw = -atan2(sinYaw, cosYaw)  // Flip sign: positive = left
                let yawDegrees = yaw * (180 / .pi)

                let quatString = String(format: "Yaw: %.2f°", yawDegrees)
                let eulerString = String(format: "---", yawDegrees)

                // --- Height (Only when plane is available) ---
                let planeAnchors = session.currentFrame?.anchors.compactMap { $0 as? ARPlaneAnchor }
                let horizontalPlanes = planeAnchors?.filter { $0.alignment == .horizontal }
                if let lowestPlane = horizontalPlanes?.min(by: { $0.transform.columns.3.y < $1.transform.columns.3.y }) {
                    let cameraY = cameraTransform.columns.3.y
                    let floorY = lowestPlane.transform.columns.3.y
                    self.currentHeight = cameraY - floorY
                }
                
                let heightToShow = self.isRecording ? (self.lockedHeight ?? self.currentHeight) : self.currentHeight
                let heightString = String(format: "Height: %.2fm", heightToShow)

                // --- Status Message ---
                let rgbWidth = CVPixelBufferGetWidth(rgbImage)
                let rgbHeight = CVPixelBufferGetHeight(rgbImage)
                let depthWidth = CVPixelBufferGetWidth(depthMap)
                let depthHeight = CVPixelBufferGetHeight(depthMap)
                let avgRGBFrameRate = rgbFrameRateHistory.reduce(0, +) / Double(rgbFrameRateHistory.count)
                let statusString = String(format: "RGB FPS: %.1f\nRGB: %d×%d\nDepth: %d×%d\nMax Depth: %.1fm",
                                          avgRGBFrameRate, rgbWidth, rgbHeight,
                                          depthWidth, depthHeight, self.depthThreshold)

                // --- Update UI on Main Thread ---
                DispatchQueue.main.async {
                    self.estimatedHeight = heightString
                    self.phoneCoordinate = coordString
                    self.phoneOrientationQuat = quatString
                    self.phoneOrientationEuler = eulerString
                    self.statusMessage = statusString
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
        let basis = calculateGravityAlignedBasis(cameraTransform: cameraTransform)
        let points = generateColoredPointCloud(depth: depthBuffer, rgb: rgbBuffer, rgbIntrinsics: intrinsics, cameraTransform: cameraTransform, basis: basis, maxDepth: self.depthThreshold)

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

    // MARK: - Recording

    func startRecording() {
        // Lock the current height
        lockedHeight = currentHeight

        // Set up file paths and create session directory
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let savesFolder = documents.appendingPathComponent("Saves", isDirectory: true)

        if !fileManager.fileExists(atPath: savesFolder.path) {
            try? fileManager.createDirectory(at: savesFolder, withIntermediateDirectories: true)
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let sessionFolder = savesFolder.appendingPathComponent("session_\(timestamp)", isDirectory: true)
        try? fileManager.createDirectory(at: sessionFolder, withIntermediateDirectories: true)

        // Create pointclouds subfolder
        let pointcloudsFolder = sessionFolder.appendingPathComponent("pointclouds", isDirectory: true)
        try? fileManager.createDirectory(at: pointcloudsFolder, withIntermediateDirectories: true)

        // Store session folder for later export
        recordingSessionFolder = sessionFolder

        // Clear recording buffer
        recordingFrames.removeAll()

        // Reset state and start recording
        lastRecordingTime = 0
        isRecording = true
    }

    func stopRecording() {
        isRecording = false

        guard let sessionFolder = recordingSessionFolder else {
            lockedHeight = nil
            return
        }

        // Show saving indicator
        DispatchQueue.main.async {
            self.isSavingRecording = true
        }

        // Export all recorded data on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let fileManager = FileManager.default

            // Save height to file
            let heightURL = sessionFolder.appendingPathComponent("height.txt")
            let heightString = String(format: "%.4f", self.lockedHeight ?? 0.0)
            try? heightString.write(to: heightURL, atomically: true, encoding: .utf8)

            // Write pose.csv
            let poseURL = sessionFolder.appendingPathComponent("pose.csv")
            var csvContent = "timestamp,x,y,z,yaw_deg\n"

            for frame in self.recordingFrames {
                let yawDegrees = frame.yaw * (180.0 / .pi)
                let line = String(format: "%.6f,%.6f,%.6f,%.6f,%.6f\n",
                                frame.timestamp,
                                frame.position.x, frame.position.y, frame.position.z,
                                yawDegrees)
                csvContent += line
            }
            try? csvContent.write(to: poseURL, atomically: true, encoding: .utf8)

            // Write PLY files
            let pointcloudsFolder = sessionFolder.appendingPathComponent("pointclouds")
            for frame in self.recordingFrames {
                let plyFilename = String(format: "pc_%.6f.ply", frame.timestamp)
                let plyURL = pointcloudsFolder.appendingPathComponent(plyFilename)
                writePLY(points: frame.points, to: plyURL)
            }

            print("Recording saved: \(self.recordingFrames.count) frames to \(sessionFolder.lastPathComponent)")

            // Clear memory and hide loading indicator
            DispatchQueue.main.async {
                self.recordingFrames.removeAll()
                self.recordingSessionFolder = nil
                self.lockedHeight = nil
                self.isSavingRecording = false
            }
        }
    }

    private func eulerAngles(from quat: simd_quatf) -> SIMD3<Float> {
        let ysqr = quat.vector.y * quat.vector.y

        // Roll (x-axis rotation)
        let t0 = +2.0 * (quat.vector.w * quat.vector.x + quat.vector.y * quat.vector.z)
        let t1 = +1.0 - 2.0 * (quat.vector.x * quat.vector.x + ysqr)
        let roll = atan2(t0, t1)

        // Pitch (y-axis rotation)
        var t2 = +2.0 * (quat.vector.w * quat.vector.y - quat.vector.z * quat.vector.x)
        t2 = t2 > 1.0 ? 1.0 : t2
        t2 = t2 < -1.0 ? -1.0 : t2
        let pitch = asin(t2)

        // Yaw (z-axis rotation)
        let t3 = +2.0 * (quat.vector.w * quat.vector.z + quat.vector.x * quat.vector.y)
        let t4 = +1.0 - 2.0 * (ysqr + quat.vector.z * quat.vector.z)
        let yaw = atan2(t3, t4)

        return SIMD3<Float>(roll, pitch, yaw)
    }

    private func processRecording(frame: ARFrame) {
        // Throttle to recording FPS
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastRecordingTime >= (1.0 / recordingFPS) else { return }
        lastRecordingTime = currentTime

        // Ensure we have all necessary data
        guard let depthBuffer = frame.sceneDepth?.depthMap,
              let initialForward = self.worldForwardAtStart else {
            return
        }

        let cameraTransform = frame.camera.transform
        let intrinsics = frame.camera.intrinsics

        // 1. Get gravity-aligned basis and points
        let basis = calculateGravityAlignedBasis(cameraTransform: cameraTransform)
        let points = generateColoredPointCloud(depth: depthBuffer, rgb: frame.capturedImage, rgbIntrinsics: intrinsics, cameraTransform: cameraTransform, basis: basis, maxDepth: self.depthThreshold)

        // 2. Compute current forward direction
        let cameraRotation = simd_float3x3(
            simd_make_float3(cameraTransform.columns.0),
            simd_make_float3(cameraTransform.columns.1),
            simd_make_float3(cameraTransform.columns.2)
        )
        let cameraToRobot = simd_float3x3(
            SIMD3<Float>(0, 0, -1),  // Robot X (forward) = Camera -Z
            SIMD3<Float>(1, 0, 0),   // Robot Y (left) = Camera X
            SIMD3<Float>(0, 1, 0)    // Robot Z (up) = Camera Y
        )
        let robotInWorld = cameraRotation * cameraToRobot
        let worldUp = SIMD3<Float>(0, 1, 0)
        let currentForwardInWorld = robotInWorld.columns.0
        let forwardProjected = currentForwardInWorld - dot(currentForwardInWorld, worldUp) * worldUp
        let currentForward = normalize(forwardProjected)

        // 3. Compute yaw relative to initial forward (flip sign: positive = left)
        let cosYaw = dot(currentForward, initialForward)
        let sinYaw = dot(cross(currentForward, initialForward), worldUp)
        let yaw = -atan2(sinYaw, cosYaw)

        // 4. Define world axes and transform position to your coordinate system
        let worldX = initialForward  // X = forward
        let worldY = cross(worldUp, initialForward)  // Y = left
        let worldZ = worldUp  // Z = up

        let arkitPosition = cameraTransform.columns.3
        let arkitPos3 = SIMD3<Float>(arkitPosition.x, arkitPosition.y, arkitPosition.z)
        let slamPosition = SIMD3<Float>(
            dot(arkitPos3, worldX),  // X component (forward)
            dot(arkitPos3, worldY),  // Y component (left)
            dot(arkitPos3, worldZ)   // Z component (up)
        )

        // 5. Store frame in memory
        let timestamp = Date().timeIntervalSince1970
        let frameData = (timestamp: timestamp, position: slamPosition, yaw: yaw, points: points)
        recordingFrames.append(frameData)
    }
}
