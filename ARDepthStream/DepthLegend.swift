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
                    // Gradient based on visualization mode
                    if mode == .rainbow {
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.red, location: 0),
                                .init(color: Color.yellow, location: 0.25),
                                .init(color: Color.green, location: 0.5),
                                .init(color: Color.cyan, location: 0.75),
                                .init(color: Color.blue, location: 1.0)
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
                    
                    // Depth markers
                    HStack(alignment: .center, spacing: 0) {
                        ForEach(0...steps, id: \.self) { i in
                            Text(String(format: "%.1f", Double(i) * Double(maxDepth) / Double(steps)))
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                        }
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

// Preview
struct DepthLegend_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            VStack {
                DepthLegend(maxDepth: 5.0, mode: .rainbow)
                DepthLegend(maxDepth: 5.0, mode: .grayscale)
                DepthLegend(maxDepth: 5.0, mode: .edge)
            }
        }
    }
}
