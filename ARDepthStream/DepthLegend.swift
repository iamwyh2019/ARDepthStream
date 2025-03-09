import SwiftUI

struct DepthLegend: View {
    var maxDepth: Float
    var mode: VisualizationMode
    var steps: Int = 5
    
    var body: some View {
        if showsLegend(mode) {
            VStack(spacing: 4) {
                Text("Depth Scale (meters)")
                    .foregroundColor(.white)
                    .font(.footnote)
                    .padding(.bottom, 2)
                
                // Legend with depth markers
                ZStack(alignment: .top) {
                    // Rainbow gradient with non-linear distribution
                    if mode == .rainbow {
                        // Non-linear gradient to match shader
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color(red: 0.5, green: 0, blue: 0), location: 0),     // Deep red
                                .init(color: Color.red, location: 0.2),                            // Bright red
                                .init(color: Color(red: 1, green: 0.8, blue: 0), location: 0.4),   // Orange-yellow
                                .init(color: Color.green, location: 0.6),                          // Green
                                .init(color: Color.cyan, location: 0.8),                           // Cyan
                                .init(color: Color.blue, location: 1.0)                            // Blue
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 15)
                        .cornerRadius(4)
                    } else if mode == .grayscale {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white, Color.gray, Color.black
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 15)
                        .cornerRadius(4)
                    } else {
                        // Edge detection has no meaningful color gradient
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 15)
                            .cornerRadius(4)
                    }
                    
                    // Non-linear depth markers to match the power function
                    HStack(alignment: .center, spacing: 0) {
                        // Non-linear depth markers
                        Text("0")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                        
                        Text(String(format: "%.1f", Double(maxDepth) * 0.2))
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                        
                        Text(String(format: "%.1f", Double(maxDepth) * 0.4))
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                        
                        Text(String(format: "%.1f", Double(maxDepth) * 0.6))
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                        
                        Text(String(format: "%.1f", Double(maxDepth) * 0.8))
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                        
                        Text(String(format: "%.1f", Double(maxDepth)))
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                    .padding(.top, 16)
                }
            }
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
    
    // Only show legend for visualization modes that use color gradients
    private func showsLegend(_ mode: VisualizationMode) -> Bool {
        return mode != .edge
    }
}
