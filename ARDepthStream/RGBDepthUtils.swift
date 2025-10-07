import Foundation
import ARKit
import UIKit
import CoreImage

public func calculateGravityAlignedBasis(cameraTransform: simd_float4x4) -> (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>) {
    // When holding landscape-left:
    // ARKit camera: +X=left, +Y=up, -Z=forward (toward scene)
    // Desired robot: +X=forward, +Y=left, +Z=up (gravity-aligned)

    let cameraRotation = simd_float3x3(
        simd_make_float3(cameraTransform.columns.0),
        simd_make_float3(cameraTransform.columns.1),
        simd_make_float3(cameraTransform.columns.2)
    )

    // World up in world space
    let worldUp = simd_float3(0, 1, 0)

    // Camera's forward direction in world space (camera looks along -Z)
    let cameraForward = simd_make_float3(cameraTransform.columns.2) * -1.0

    // Project camera forward onto horizontal plane (remove vertical component)
    let forwardProjected = cameraForward - dot(cameraForward, worldUp) * worldUp
    let forward = normalize(forwardProjected)

    // Left is perpendicular to both up and forward
    // left = cross(up, forward) in right-handed system
    let left = cross(worldUp, forward)

    // Return as (right, up, forward) but right = -left
    return (right: -left, up: worldUp, forward: forward)
}

public func saveRGBImage(_ buffer: CVPixelBuffer, to url: URL) {
    let ciImage = CIImage(cvPixelBuffer: buffer)
    let context = CIContext()
    if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
        let uiImage = UIImage(cgImage: cgImage)
        if let pngData = uiImage.pngData() {
            try? pngData.write(to: url)
        }
    }
}

public func generateColoredPointCloud(depth: CVPixelBuffer, rgb: CVPixelBuffer, rgbIntrinsics: simd_float3x3, cameraTransform: simd_float4x4, basis: (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>), maxDepth: Float) -> [(SIMD3<Float>, SIMD3<UInt8>)] {
    CVPixelBufferLockBaseAddress(depth, .readOnly)
    CVPixelBufferLockBaseAddress(rgb, .readOnly)
    defer {
        CVPixelBufferUnlockBaseAddress(depth, .readOnly)
        CVPixelBufferUnlockBaseAddress(rgb, .readOnly)
    }

    let depthWidth = CVPixelBufferGetWidth(depth)
    let depthHeight = CVPixelBufferGetHeight(depth)
    let depthBase = CVPixelBufferGetBaseAddress(depth)!.assumingMemoryBound(to: Float.self)
    let depthStride = CVPixelBufferGetBytesPerRow(depth) / MemoryLayout<Float>.size

    let rgbWidth = CVPixelBufferGetWidth(rgb)
    let rgbHeight = CVPixelBufferGetHeight(rgb)
    let rgbBase = CVPixelBufferGetBaseAddress(rgb)!.assumingMemoryBound(to: UInt8.self)
    let rgbBytesPerRow = CVPixelBufferGetBytesPerRow(rgb)
    let rgbChannels = 4  // Assuming BGRA

    // Scale intrinsics properly for depth resolution
    let depthIntrinsics = simd_float3x3([
        simd_float3(rgbIntrinsics.columns.0.x * Float(depthWidth) / Float(rgbWidth), 0, 0),
        simd_float3(0, rgbIntrinsics.columns.1.y * Float(depthHeight) / Float(rgbHeight), 0),
        simd_float3(rgbIntrinsics.columns.2.x * Float(depthWidth) / Float(rgbWidth),
                    rgbIntrinsics.columns.2.y * Float(depthHeight) / Float(rgbHeight), 1)
    ])

    let fx = depthIntrinsics.columns.0.x
    let fy = depthIntrinsics.columns.1.y
    let cx = depthIntrinsics.columns.2.x
    let cy = depthIntrinsics.columns.2.y

    var result: [(SIMD3<Float>, SIMD3<UInt8>)] = []

    for y in 0..<depthHeight {
        for x in 0..<depthWidth {
            let z = depthBase[y * depthStride + x]
            
            if z.isFinite && z > 0 && z < maxDepth { // Adjust max depth as needed
                let X = (Float(x) - cx) * z / fx
                let Y = (cy - Float(y)) * z / fy
                
                let u_rgb = Int(round(Float(x) * Float(rgbWidth) / Float(depthWidth)))
                let v_rgb = Int(round(Float(y) * Float(rgbHeight) / Float(depthHeight)))

                if u_rgb >= 0, u_rgb < rgbWidth, v_rgb >= 0, v_rgb < rgbHeight {
                    let rgbOffset = v_rgb * rgbBytesPerRow + u_rgb * rgbChannels
                    let b = rgbBase[rgbOffset]
                    let g = rgbBase[rgbOffset + 1]
                    let r = rgbBase[rgbOffset + 2]

                    // Point in camera's standard local space (camera: +X=right, +Y=up, +Z=backward)
                    // Camera looks along -Z, so forward is at -z depth
                    let pointCameraSpace = SIMD3<Float>(X, Y, -z)

                    // Transform from camera space to world space
                    let cameraRotation = simd_float3x3(
                        simd_make_float3(cameraTransform.columns.0),
                        simd_make_float3(cameraTransform.columns.1),
                        simd_make_float3(cameraTransform.columns.2)
                    )
                    let pointWorldSpace = cameraRotation * pointCameraSpace

                    // Project onto robot basis: X=forward, Y=left, Z=up
                    let left = -basis.right
                    let finalX = dot(pointWorldSpace, basis.forward)  // Forward component
                    let finalY = dot(pointWorldSpace, left)           // Left component
                    let finalZ = dot(pointWorldSpace, basis.up)       // Up component

                    let finalPoint = SIMD3<Float>(finalX, finalY, finalZ)

                    result.append((finalPoint, SIMD3<UInt8>(r, g, b)))
                }
            }
        }
    }

    return result
}

public func writePLY(points: [(SIMD3<Float>, SIMD3<UInt8>)], to url: URL) {
    var content = "ply\nformat ascii 1.0\nelement vertex \(points.count)\n"
    content += "property float x\nproperty float y\nproperty float z\n"
    content += "property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n"

    for (pos, color) in points {
        // Format with specific precision to avoid scientific notation issues
        content += String(format: "%.6f %.6f %.6f %d %d %d\n",
                         pos.x, pos.y, pos.z,
                         color.x, color.y, color.z)
    }

    do {
        try content.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        print("Error writing PLY file: \(error)")
    }
}