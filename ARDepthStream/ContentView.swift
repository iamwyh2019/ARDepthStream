import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject private var arViewModel = ARViewModel()
    @State private var overlayOpacity: Double = 0.5
    @State private var depthThreshold: Double = 3.0  // Default 3 meters, max 5m
    @State private var visualizationMode: VisualizationMode = .rainbow
    @State private var selectedResolutionIndex: Int
    @State private var showInfo = false
    @State private var showResolutionPicker = false
    
    private let resolutionManager = ResolutionManager.shared
    
    // Initialize with default resolution index
    init() {
        _selectedResolutionIndex = State(initialValue: ResolutionManager.shared.indexOfDefaultFormat())
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Camera feed container
            GeometryReader { geometry in
                ZStack {
                    // Images container with fixed aspect ratio
                    VStack {
                        Spacer() // Center vertically
                        
                        // Camera feed with proper aspect ratio and rotation
                        ZStack {
                            // RGB image
                            if let rgbImage = arViewModel.rgbImage {
                                Image(uiImage: rgbImage)
                                    .resizable()
                                    .scaledToFit()
                                    .rotationEffect(.degrees(90)) // Rotate 90 degrees clockwise
                                    .frame(width: geometry.size.width)
                            }
                            
                            // Depth overlay
                            if let depthImage = arViewModel.depthImage {
                                Image(uiImage: depthImage)
                                    .resizable()
                                    .scaledToFit()
                                    .rotationEffect(.degrees(90)) // Rotate 90 degrees clockwise
                                    .frame(width: geometry.size.width)
                                    .opacity(overlayOpacity)
                            }
                        }
                        
                        Spacer() // Center vertically
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            
            // UI Controls as overlay
            VStack {
                // Status at top
                HStack {
                    Text(arViewModel.statusMessage)
                        .font(.footnote)
                        .padding(8)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    Button(action: { showInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.7)))
                    }
                }
                .padding()
                
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
                            showResolutionPicker = true
                        }) {
                            if let format = resolutionManager.format(at: selectedResolutionIndex) {
                                Text(resolutionManager.formatDescription(format))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Color.blue.opacity(0.5))
                                    .cornerRadius(8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .statusBar(hidden: true)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            resolutionManager.refreshSupportedFormats()
            if let format = resolutionManager.format(at: selectedResolutionIndex) {
                arViewModel.setVideoFormat(format)
            }
            arViewModel.startSession()
        }
        .onDisappear {
            arViewModel.pauseSession()
        }
        .actionSheet(isPresented: $showResolutionPicker) {
            var buttons: [ActionSheet.Button] = []
            
            // Add available formats
            for i in 0..<resolutionManager.formatCount {
                if let format = resolutionManager.format(at: i) {
                    let description = resolutionManager.formatDescription(format)
                    buttons.append(.default(Text(description)) {
                        selectedResolutionIndex = i
                        if let selectedFormat = resolutionManager.format(at: i) {
                            arViewModel.setVideoFormat(selectedFormat)
                        }
                    })
                }
            }
            
            buttons.append(.cancel())
            
            return ActionSheet(
                title: Text("Select Resolution"),
                message: Text("Higher resolutions may reduce performance"),
                buttons: buttons
            )
        }
        .alert(isPresented: $showInfo) {
            Alert(
                title: Text("Depth Visualization Info"),
                message: Text("This app shows RGB and depth data alignment from iPhone LiDAR.\n\n- Opacity: Adjust overlay transparency\n- Max Depth: Set maximum distance (0.5-5m)\n- Resolution: Select camera resolution and frame rate\n- Visualization modes for different views"),
                dismissButton: .default(Text("OK"))
            )
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
