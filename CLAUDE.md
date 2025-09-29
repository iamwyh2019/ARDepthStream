# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ARDepthStream is an iOS app that visualizes LiDAR depth data from iPhone in real-time, overlaying it on RGB camera feed with multiple visualization modes (rainbow, grayscale, edge detection). The app uses ARKit for depth sensing and Metal for GPU-accelerated processing. It also supports capturing and exporting depth data as PLY point clouds with RGB color information.

## Build and Run

**Open in Xcode:**
```bash
open ARDepthStream.xcodeproj
```

**Build and run:**
- Select a physical device (iPhone/iPad with LiDAR) as the target - this app requires actual hardware with depth sensors
- Press Cmd+R to build and run
- The app will not work in the simulator due to ARKit depth requirements

**Run tests:**
- Cmd+U to run unit tests (ARDepthStreamTests)
- Cmd+U with UI testing scheme for UI tests (ARDepthStreamUITests)

## Architecture

### Core Components

**ARViewModel** (`ARViewModel.swift`)
- Central MVVM view model managing AR session and frame processing
- Implements `ARSessionDelegate` to receive depth and RGB frames from ARKit
- Coordinates between ARKit data capture and Metal rendering
- Handles frame rate optimization (processes every Nth frame)
- Manages depth range calculation for visualization normalization
- Double-tap gesture triggers frame capture and PLY export to Documents/Saves/

**MetalRenderer** (`MetalRenderer.swift`)
- GPU-accelerated depth visualization using Metal compute shaders
- Creates and manages Metal textures, pipeline states, command buffers
- Two main processing functions:
  - `processDepth()`: Converts depth buffer to visualization (rainbow/grayscale/edge)
  - `processRGBWithDepthMask()`: Masks RGB image based on depth threshold
- Uses `CVMetalTextureCache` for efficient pixel buffer to texture conversion

**MetalShaders** (`MetalShader.swift`)
- Contains Metal Shading Language (MSL) code as Swift string literals
- `processDepth` kernel: Per-pixel depth visualization with non-linear color mapping
- `depthToRainbow()`: Maps depth values to rainbow spectrum with emphasis on close objects (power 1.5)
- `maskRGBWithDepth` kernel: Applies depth-based masking to RGB feed
- Supports three visualization modes matching VisualizationMode enum

**ContentView** (`ContentView.swift`)
- SwiftUI main interface with real-time camera feed, depth overlay, and controls
- Sliders for opacity (0-1) and max depth threshold (0.5-5m)
- Resolution picker using ResolutionManager for dynamic format selection
- Visualization mode buttons (Rainbow/Gray/Edge)
- DepthLegend shows color-to-distance mapping
- Double-tap on camera feed captures frame and saves RGB+PLY

**ResolutionManager** (`ResolutionMode.swift`)
- Singleton managing ARKit video format selection
- Queries `ARWorldTrackingConfiguration.supportedVideoFormats`
- Removes duplicate resolutions, sorts by quality (resolution × framerate)
- Default preference: 1920×1440@60fps if available

**RGBDepthUtils** (`RGBDepthUtils.swift`)
- `generateColoredPointCloud()`: Converts depth + RGB buffers to 3D point cloud
- Uses camera intrinsics to unproject depth pixels to 3D space
- Maps depth coordinates to RGB coordinates for color assignment
- `writePLY()`: Exports ASCII PLY format with position (x,y,z) and color (r,g,b)
- `saveRGBImage()`: Saves RGB frame as PNG

### Data Flow

1. ARKit captures synchronized RGB and depth frames → `ARSessionDelegate.session(_:didUpdate:)`
2. ARViewModel stores latest buffers and schedules processing (every Nth frame for performance)
3. MetalRenderer processes depth buffer → GPU compute shader → UIImage visualization
4. MetalRenderer masks RGB buffer based on depth threshold → UIImage
5. SwiftUI ContentView displays both images with opacity blending
6. On double-tap: RGBDepthUtils generates colored point cloud + saves PNG and PLY files

### Coordinate Systems

- ARKit depth: Right-handed coordinate system, Y-up
- Point cloud export: Z-axis inverted (`-z`) for standard PLY convention
- Image rotation: 90° clockwise rotation applied in UI to account for camera orientation
- Depth-to-RGB alignment: Scale factors and offsets calculated based on resolution differences

## Key Implementation Details

**Performance Optimizations:**
- Frame skipping: Process every 2nd frame (`frameProcessingInterval = 2`)
- Status updates: Only refresh stats every 30 frames
- Depth range calculation: Sparse sampling (every 16th pixel) on background thread
- Metal texture caching: Reuse textures when dimensions unchanged

**Depth Visualization:**
- Non-linear color mapping emphasizes close objects: `normalizedDepth^1.5`
- Rainbow spectrum divided into 5 bands (0-20%, 20-40%, 40-60%, 60-80%, 80-100%)
- Edge detection: Calculates depth differences with neighboring pixels, multiplied by 50

**Resolution Handling:**
- Supports dynamic resolution changes during runtime
- UI shows loading animation during format switch
- Depth and RGB resolutions may differ - coordinate mapping handles scaling

## Device Requirements

- iPhone or iPad with LiDAR sensor (iPhone 12 Pro and later, iPad Pro 2020 and later)
- iOS/iPadOS 14.0+ (ARKit with sceneDepth support)
- Metal-compatible GPU (all devices with LiDAR support Metal)