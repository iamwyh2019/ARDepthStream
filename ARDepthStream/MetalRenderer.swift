import Metal
import MetalKit
import UIKit

class MetalRenderer {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var depthPipelineState: MTLComputePipelineState!
    private var rgbMaskPipelineState: MTLComputePipelineState!
    
    // Textures and buffers
    private var depthTexture: MTLTexture?
    private var depthOutTexture: MTLTexture?
    private var rgbTexture: MTLTexture?
    private var rgbOutTexture: MTLTexture?
    
    // Texture caches for efficient conversion
    private var textureCache: CVMetalTextureCache?
    
    init?() {
        // Get the default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return nil
        }
        
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        // Create Metal texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        self.textureCache = textureCache
        
        // Create pipeline states
        guard createPipelineStates() else {
            print("Failed to create pipeline states")
            return nil
        }
    }
    
    private func createPipelineStates() -> Bool {
        // Create a library from our shader code
        guard let library = try? device.makeLibrary(source: MetalShaders.depthVisualizationShader, options: nil) else {
            print("Failed to create Metal library")
            return false
        }
        
        // Get the kernel functions
        guard let depthFunction = library.makeFunction(name: "processDepth"),
              let rgbMaskFunction = library.makeFunction(name: "maskRGBWithDepth") else {
            print("Failed to create kernel functions")
            return false
        }
        
        // Create compute pipeline states
        do {
            depthPipelineState = try device.makeComputePipelineState(function: depthFunction)
            rgbMaskPipelineState = try device.makeComputePipelineState(function: rgbMaskFunction)
            return true
        } catch {
            print("Failed to create pipeline state: \(error)")
            return false
        }
    }
    
    // Create a Metal texture from a CVPixelBuffer
    private func createTexture(from pixelBuffer: CVPixelBuffer, format: MTLPixelFormat, planeIndex: Int = 0) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache!,
            pixelBuffer,
            nil,
            format,
            width,
            height,
            planeIndex,
            &texture
        )
        
        if status != kCVReturnSuccess {
            print("Failed to create Metal texture from pixel buffer")
            return nil
        }
        
        return CVMetalTextureGetTexture(texture!)
    }
    
    // Create an output texture
    private func createOutputTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        return device.makeTexture(descriptor: textureDescriptor)
    }
    
    // Process depth data using Metal
    func processDepth(depthBuffer: CVPixelBuffer,
                     minDepth: Float,
                     maxDepth: Float,
                     threshold: Float,
                     mode: VisualizationMode) -> UIImage? {
        
        // Create a Metal texture from the depth pixel buffer
        guard let depthTexture = createTexture(from: depthBuffer, format: .r32Float) else {
            print("Failed to create depth texture")
            return nil
        }
        self.depthTexture = depthTexture
        
        // Create an output texture
        let width = depthTexture.width
        let height = depthTexture.height
        
        if depthOutTexture == nil ||
           depthOutTexture?.width != width ||
           depthOutTexture?.height != height {
            depthOutTexture = createOutputTexture(width: width, height: height, pixelFormat: .rgba8Unorm)
        }
        
        guard let outTexture = depthOutTexture else {
            print("Failed to create output texture")
            return nil
        }
        
        // Create a command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Failed to create command buffer")
            return nil
        }
        
        // Create a compute command encoder
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create compute encoder")
            return nil
        }
        
        // Set the compute pipeline state
        computeEncoder.setComputePipelineState(depthPipelineState)
        
        // Set the textures
        computeEncoder.setTexture(depthTexture, index: 0)
        computeEncoder.setTexture(outTexture, index: 1)
        
        // Set the parameters
        var minDepthValue = minDepth
        var maxDepthValue = maxDepth
        var thresholdValue = threshold
        var modeValue = mode.rawValue
        
        computeEncoder.setBytes(&minDepthValue, length: MemoryLayout<Float>.size, index: 0)
        computeEncoder.setBytes(&maxDepthValue, length: MemoryLayout<Float>.size, index: 1)
        computeEncoder.setBytes(&thresholdValue, length: MemoryLayout<Float>.size, index: 2)
        computeEncoder.setBytes(&modeValue, length: MemoryLayout<Int>.size, index: 3)
        
        // Calculate the grid size and thread group size
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        // Dispatch the compute kernel
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        // Create a texture to hold the final image
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let resultTexture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        
        // Create a blit encoder to copy the result
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }
        
        blitEncoder.copy(from: outTexture,
                         sourceSlice: 0,
                         sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                         sourceSize: MTLSize(width: width, height: height, depth: 1),
                         to: resultTexture,
                         destinationSlice: 0,
                         destinationLevel: 0,
                         destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()
        
        // Commit the command buffer
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Convert the result texture to a UIImage
        return textureToUIImage(texture: resultTexture)
    }
    
    // Process RGB image with depth mask
    func processRGBWithDepthMask(rgbBuffer: CVPixelBuffer,
                                depthBuffer: CVPixelBuffer,
                                threshold: Float) -> UIImage? {
        
        // Create RGB image directly from CVPixelBuffer, preserving color
        let ciImage = CIImage(cvPixelBuffer: rgbBuffer)
        let context = CIContext(options: nil)
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        let rgbImage = UIImage(cgImage: cgImage)
        
        // Create a bitmap context for the masked image
        UIGraphicsBeginImageContextWithOptions(rgbImage.size, false, rgbImage.scale)
        defer { UIGraphicsEndImageContext() }
        
        // Draw the original image
        rgbImage.draw(at: .zero)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return rgbImage
        }
        
        // Get dimensions
        let rgbWidth = CGFloat(CVPixelBufferGetWidth(rgbBuffer))
        let rgbHeight = CGFloat(CVPixelBufferGetHeight(rgbBuffer))
        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)
        
        // Lock the depth buffer
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return rgbImage
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        
        // Calculate transformation with correct offset and scaling
        let scaleX = rgbWidth / CGFloat(depthWidth)
        let scaleY = rgbHeight / CGFloat(depthHeight)
        
        // Add slight offset to improve alignment (may need adjustment)
        let offsetX: CGFloat = 0.5 * scaleX
        let offsetY: CGFloat = 0.5 * scaleY
        
        // Set the blend mode to clear areas beyond threshold
        context.setBlendMode(.clear)
        context.setFillColor(UIColor.black.cgColor)
        
        // Sample step size for better performance
        let sampling = 8
        
        // Create mask by drawing black rectangles over areas beyond threshold
        for y in stride(from: 0, to: depthHeight, by: sampling) {
            for x in stride(from: 0, to: depthWidth, by: sampling) {
                let pixelOffset = y * bytesPerRow + x * MemoryLayout<Float>.size
                let depthValue = baseAddress.load(fromByteOffset: pixelOffset, as: Float.self)
                
                // If depth is beyond threshold, mask it
                if depthValue <= 0 || depthValue > threshold || !depthValue.isFinite || depthValue.isNaN {
                    let rectSize = CGSize(width: CGFloat(sampling) * scaleX, height: CGFloat(sampling) * scaleY)
                    let rect = CGRect(
                        x: CGFloat(x) * scaleX + offsetX,
                        y: CGFloat(y) * scaleY + offsetY,
                        width: rectSize.width,
                        height: rectSize.height
                    )
                    context.fill(rect)
                }
            }
        }
        
        // Get the masked image
        let maskedImage = UIGraphicsGetImageFromCurrentImageContext()
        
        return maskedImage
    }
    
    // Convert a Metal texture to a UIImage
    private func textureToUIImage(texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        
        // Create a bitmap context
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        
        // Get the bytes from the texture
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        texture.getBytes(&data, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        // Create a CGImage from the data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(data) as CFData) else {
            return nil
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        // Use up orientation to avoid SwiftUI rotation issues
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}