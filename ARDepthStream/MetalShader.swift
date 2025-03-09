import Foundation

// Metal shaders for depth visualization
struct MetalShaders {
    static let depthVisualizationShader = """
    #include <metal_stdlib>
    using namespace metal;

    // Visualization modes match our Swift enum
    typedef enum {
        VisualizationModeRainbow = 0,
        VisualizationModeGrayscale = 1,
        VisualizationModeEdge = 2
    } VisualizationMode;

    // Convert depth to rainbow colors
    float3 depthToRainbow(float depth, float maxDepthThreshold) {
        // Map depth to the fixed range defined by the slider
        float normalizedDepth = clamp(depth / maxDepthThreshold, 0.0, 1.0);
        
        // Use a non-linear mapping to emphasize close objects
        // This will dedicate more of the color spectrum to closer distances
        normalizedDepth = pow(normalizedDepth, 1.5); // Non-linear emphasis on close objects
        
        // Apply rainbow coloring with more bands for closer objects
        if (normalizedDepth < 0.2) {
            // Very close: deep red to red (0-20% of range)
            float t = normalizedDepth / 0.2;
            return float3(0.5 + 0.5 * t, 0.0, 0.0);
        } else if (normalizedDepth < 0.4) {
            // Close: red to orange to yellow (20-40% of range)
            float t = (normalizedDepth - 0.2) / 0.2;
            return float3(1.0, t * 0.8, 0.0);
        } else if (normalizedDepth < 0.6) {
            // Medium: yellow to green (40-60% of range)
            float t = (normalizedDepth - 0.4) / 0.2;
            return float3(1.0 - t, 0.8 + 0.2 * t, 0.0);
        } else if (normalizedDepth < 0.8) {
            // Medium-far: green to cyan (60-80% of range)
            float t = (normalizedDepth - 0.6) / 0.2;
            return float3(0.0, 1.0, t);
        } else {
            // Far: cyan to blue (80-100% of range)
            float t = (normalizedDepth - 0.8) / 0.2;
            return float3(0.0, 1.0 - t, 1.0);
        }
    }

    // Kernel function to process depth data
    kernel void processDepth(texture2d<float, access::read> depthTexture [[texture(0)]],
                            texture2d<float, access::write> outTexture [[texture(1)]],
                            constant float &minDepth [[buffer(0)]],
                            constant float &maxDepth [[buffer(1)]],
                            constant float &threshold [[buffer(2)]],
                            constant int &mode [[buffer(3)]],
                            uint2 gid [[thread_position_in_grid]]) {
        
        // Check if this thread is within bounds
        if (gid.x >= depthTexture.get_width() || gid.y >= depthTexture.get_height()) {
            return;
        }

        // Read depth value
        float depthValue = depthTexture.read(gid).r;
        
        // Initialize output color with transparency
        float4 outColor = float4(0, 0, 0, 0);
        
        // Process valid depth values within threshold
        if (depthValue > 0 && depthValue <= threshold && isfinite(depthValue)) {
            // Normalize depth
            float normalizedDepth = (depthValue - minDepth) / (maxDepth - minDepth);
            normalizedDepth = clamp(normalizedDepth, 0.0f, 1.0f);
            
            float3 rgb;
            
            // Apply different visualization modes
            switch (mode) {
                case VisualizationModeRainbow:
                    rgb = depthToRainbow(depthValue, threshold);
                    break;
                    
                case VisualizationModeGrayscale:
                    rgb = float3(normalizedDepth);
                    break;
                    
                case VisualizationModeEdge: {
                    // Simple edge detection based on local depth differences
                    // Read neighboring pixels if within bounds
                    float leftDepth = (gid.x > 0) ? depthTexture.read(uint2(gid.x - 1, gid.y)).r : depthValue;
                    float topDepth = (gid.y > 0) ? depthTexture.read(uint2(gid.x, gid.y - 1)).r : depthValue;
                    
                    // Calculate depth difference
                    float depthDiff = max(abs(depthValue - leftDepth), abs(depthValue - topDepth));
                    float edgeValue = min(depthDiff * 50.0f, 1.0f);
                    rgb = float3(edgeValue);
                    break;
                }
                
                default:
                    rgb = float3(normalizedDepth);
                    break;
            }
            
            outColor = float4(rgb, 1.0);
        }
        
        // Write output color to the texture
        outTexture.write(outColor, gid);
    }

    // RGB masking kernel
    kernel void maskRGBWithDepth(texture2d<float, access::read> rgbTexture [[texture(0)]],
                                texture2d<float, access::read> depthTexture [[texture(1)]],
                                texture2d<float, access::write> outTexture [[texture(2)]],
                                constant float &threshold [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
        
        // Check if this thread is within bounds
        if (gid.x >= rgbTexture.get_width() || gid.y >= rgbTexture.get_height()) {
            return;
        }
        
        // Read RGB value
        float4 rgbValue = rgbTexture.read(gid);
        
        // Calculate depth texture coordinates (may have different dimensions)
        uint2 depthCoords;
        depthCoords.x = (gid.x * depthTexture.get_width()) / rgbTexture.get_width();
        depthCoords.y = (gid.y * depthTexture.get_height()) / rgbTexture.get_height();
        
        // Read depth value
        float depthValue = depthTexture.read(depthCoords).r;
        
        // Mask RGB based on depth threshold
        if (depthValue <= 0 || depthValue > threshold || !isfinite(depthValue)) {
            outTexture.write(float4(0, 0, 0, 1), gid); // Black for masked areas
        } else {
            outTexture.write(rgbValue, gid);
        }
    }
    """
}
