import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject private var arViewModel = ARViewModel()
    @State private var overlayOpacity: Double = 0.5
    @State private var depthThreshold: Double = 3.0  // Default 3 meters, max 5m
    @State private var visualizationMode: VisualizationMode = .rainbow
    @State private var selectedResolutionIndex: Int
    @State private var showResolutionPicker = false
    @State private var isChangingResolution = false
    @State private var statusHeight: CGFloat = 0
    
    private let resolutionManager = ResolutionManager.shared
    
    // Initialize with default resolution index
    init() {
        _selectedResolutionIndex = State(initialValue: ResolutionManager.shared.indexOfDefaultFormat())
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.edgesIgnoringSafeArea(.all)
            
            GeometryReader { geometry in
                ZStack {
                    // Camera feed container that fills from top to bottom
                    VStack(spacing: 0) {
                        // Status at top - measure its height
                        HStack {
                            Text(arViewModel.statusMessage)
                                .font(.footnote)
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.onAppear {
                                            statusHeight = proxy.size.height + 16 // Height + padding
                                        }
                                    }
                                )
                            
                            Spacer()
                        }
                        .padding()
                        
                        // Camera feed that fills the space between status and controls
                        ZStack {
                            // RGB image
                            if let rgbImage = arViewModel.rgbImage {
                                Image(uiImage: rgbImage)
                                    .resizable()
                                    .scaledToFit()
                                    .rotationEffect(.degrees(90)) // Rotate 90 degrees clockwise
                                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height - statusHeight - 180) // Subtract status height and control height
                            }
                            
                            // Depth overlay
                            if let depthImage = arViewModel.depthImage {
                                Image(uiImage: depthImage)
                                    .resizable()
                                    .scaledToFit()
                                    .rotationEffect(.degrees(90)) // Rotate 90 degrees clockwise
                                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height - statusHeight - 180)
                                    .opacity(overlayOpacity)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        Spacer()
                        
                        // Bottom controls panel with fixed width
                        VStack(spacing: 12) {
                            // Opacity slider
                            HStack {
                                Text("Opacity")
                                    .foregroundColor(.white)
                                    .frame(width: 80, alignment: .leading)
                                
                                Slider(value: $overlayOpacity, in: 0...1)
                                    .accentColor(.blue)
                                
                                Text(String(format: "%.1f", overlayOpacity))
                                    .foregroundColor(.white)
                                    .frame(width: 35)
                            }
                            .padding(.horizontal)
                            
                            // Depth threshold slider
                            HStack {
                                Text("Max Depth")
                                    .foregroundColor(.white)
                                    .frame(width: 80, alignment: .leading)
                                
                                Slider(value: $depthThreshold, in: 0.5...5.0)
                                    .accentColor(.blue)
                                    .onChange(of: depthThreshold) { newThreshold in
                                        arViewModel.depthThreshold = Float(newThreshold)
                                    }
                                
                                Text(String(format: "%.1fm", depthThreshold))
                                    .foregroundColor(.white)
                                    .frame(width: 35)
                            }
                            .padding(.horizontal)
                            
                            // Resolution button
                            HStack {
                                Text("Resolution")
                                    .foregroundColor(.white)
                                    .frame(width: 80, alignment: .leading)
                                
                                Button(action: {
                                    if !isChangingResolution {
                                        showResolutionPicker = true
                                    }
                                }) {
                                    if isChangingResolution {
                                        HStack {
                                            Text("Changing...")
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(Color.orange.opacity(0.5))
                                        .cornerRadius(8)
                                    } else if let format = resolutionManager.format(at: selectedResolutionIndex) {
                                        Text(resolutionManager.formatDescription(format))
                                            .foregroundColor(.white)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 12)
                                            .background(Color.blue.opacity(0.5))
                                            .cornerRadius(8)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .disabled(isChangingResolution)
                            }
                            .padding(.horizontal)
                            
                            // Visualization mode picker - fixed width buttons
                            HStack(spacing: 8) {
                                ForEach(VisualizationMode.allCases, id: \.self) { mode in
                                    Button(action: {
                                        visualizationMode = mode
                                        arViewModel.visualizationMode = mode
                                    }) {
                                        Text(mode.description)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity)
                                            .background(visualizationMode == mode ? Color.blue : Color.gray.opacity(0.3))
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxWidth: 500) // Limit max width of controls
                        .padding(.vertical, 16)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            
            // Loading indicator overlay when changing resolution
            if isChangingResolution {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .allowsHitTesting(false)
            }
        }
        .statusBar(hidden: true)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // Apply initial settings
            resolutionManager.refreshSupportedFormats()
            if let format = resolutionManager.format(at: selectedResolutionIndex) {
                arViewModel.setVideoFormat(format)
            }
            arViewModel.startSession()
        }
        .onDisappear {
            arViewModel.pauseSession()
        }
        .confirmationDialog("Select Resolution", isPresented: $showResolutionPicker, titleVisibility: .visible) {
            // Only show unique resolutions
            ForEach(resolutionManager.uniqueFormats.indices, id: \.self) { i in
                Button(resolutionManager.formatDescription(resolutionManager.uniqueFormats[i])) {
                    // Only change if different
                    let newFormat = resolutionManager.uniqueFormats[i]
                    if let currentFormat = resolutionManager.format(at: selectedResolutionIndex),
                       currentFormat != newFormat {
                        // Mark as changing resolution
                        isChangingResolution = true
                        
                        // Get index of this format in the main formats array
                        if let mainIndex = resolutionManager.indexOfFormat(newFormat) {
                            selectedResolutionIndex = mainIndex
                            
                            // Apply on background thread
                            DispatchQueue.global(qos: .userInitiated).async {
                                arViewModel.setVideoFormat(newFormat)
                                
                                // Reset changing flag after a delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isChangingResolution = false
                                }
                            }
                        } else {
                            isChangingResolution = false
                        }
                    }
                }
            }
        } message: {
            Text("Higher resolutions may reduce performance")
        }
    }
}

// Add description to visualization mode
extension VisualizationMode: CaseIterable {
    static var allCases: [VisualizationMode] = [.rainbow, .heat, .grayscale, .edge]
    
    var description: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .heat: return "Heat"
        case .grayscale: return "Gray"
        case .edge: return "Edge"
        }
    }
}
