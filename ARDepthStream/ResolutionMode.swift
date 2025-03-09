import Foundation
import ARKit

// Wrapper for supported ARKit video formats
class ResolutionManager {
    // Singleton instance
    static let shared = ResolutionManager()
    
    // Available formats from the device
    private(set) var availableFormats: [ARConfiguration.VideoFormat] = []
    
    // Currently selected format
    private(set) var currentFormat: ARConfiguration.VideoFormat?
    
    private init() {
        // Initialize with supported formats
        refreshSupportedFormats()
    }
    
    func refreshSupportedFormats() {
        availableFormats = ARWorldTrackingConfiguration.supportedVideoFormats
        
        // Sort by quality (resolution * framerate)
        availableFormats.sort { format1, format2 in
            let quality1 = format1.imageResolution.width * format1.imageResolution.height * CGFloat(format1.framesPerSecond)
            let quality2 = format2.imageResolution.width * format2.imageResolution.height * CGFloat(format2.framesPerSecond)
            return quality1 > quality2
        }
        
        // Find and set the default format (1920x1440@60fps if available)
        let preferredFormat = availableFormats.first { format in
            let width = Int(format.imageResolution.width)
            let height = Int(format.imageResolution.height)
            return width == 1920 && height == 1440 && format.framesPerSecond == 60
        }
        
        // Set to preferred format or highest quality if not found
        currentFormat = preferredFormat ?? availableFormats.first
    }
    
    // Get format at specific index
    func format(at index: Int) -> ARConfiguration.VideoFormat? {
        guard index >= 0 && index < availableFormats.count else {
            return nil
        }
        return availableFormats[index]
    }
    
    // Find index of a specific format
    func indexOfFormat(_ format: ARConfiguration.VideoFormat) -> Int? {
        return availableFormats.firstIndex { $0 == format }
    }
    
    // Find index of the default format (1920x1440@60fps)
    func indexOfDefaultFormat() -> Int {
        if let preferredFormat = availableFormats.first(where: { format in
            let width = Int(format.imageResolution.width)
            let height = Int(format.imageResolution.height)
            return width == 1920 && height == 1440 && format.framesPerSecond == 60
        }), let index = indexOfFormat(preferredFormat) {
            return index
        }
        return 0 // Default to first format if preferred not found
    }
    
    // Set current format by index
    func setFormat(at index: Int) -> Bool {
        guard let format = format(at: index) else {
            return false
        }
        currentFormat = format
        return true
    }
    
    // Generate a display string for a format
    func formatDescription(_ format: ARConfiguration.VideoFormat) -> String {
        let width = Int(format.imageResolution.width)
        let height = Int(format.imageResolution.height)
        return "\(width)×\(height) @\(format.framesPerSecond)fps"
    }
    
    // Number of available formats
    var formatCount: Int {
        return availableFormats.count
    }
}
