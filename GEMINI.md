# GEMINI.md

This file provides guidance for working with the ARDepthStream project.

## Project Overview

ARDepthStream is an iOS app that visualizes LiDAR depth data in real-time. It overlays depth information on the RGB camera feed, offering multiple visualization modes (rainbow, grayscale, edge detection). The app uses ARKit for depth sensing and Metal for GPU-accelerated rendering. It also supports capturing and exporting depth data as colored PLY point clouds.

A more detailed project description can be found in `CLAUDE.md`.

**Technologies:**
*   Swift
*   SwiftUI
*   ARKit
*   Metal

## Building and Running

This project must be built and run on a physical iOS device with a LiDAR sensor (e.g., iPhone 12 Pro or later). It will not work in the simulator.

1.  **Open the project in Xcode:**
    ```bash
    open ARDepthStream.xcodeproj
    ```
2.  **Build and Run:**
    *   Connect a LiDAR-equipped iPhone or iPad.
    *   Select the device as the run target in Xcode.
    *   Press `Cmd+R` to build and run the app on the device.

## Architecture

The app follows the MVVM (Model-View-ViewModel) design pattern.

*   **`ARViewModel.swift`**: The core of the application. It manages the `ARSession`, processes incoming AR frames, and prepares data for display.
*   **`ContentView.swift`**: The main user interface, built with SwiftUI. It displays the camera feed and depth overlay, and provides controls for adjusting visualization parameters.
*   **`MetalRenderer.swift`**: Handles all GPU-accelerated rendering. It uses Metal compute shaders to process depth data and generate visualizations.
*   **`RGBDepthUtils.swift`**: Provides utility functions for converting depth and RGB data into a colored 3D point cloud and exporting it as a `.ply` file.
*   **`MetalShader.swift`**: Contains the Metal Shading Language (MSL) code for the compute shaders.

### Data Flow

1.  `ARKit` captures RGB and depth frames.
2.  `ARViewModel` receives the frames via `ARSessionDelegate`.
3.  `MetalRenderer` processes the depth data on the GPU to create a visualization.
4.  `ContentView` displays the RGB feed and the depth visualization as an overlay.
5.  On a double-tap gesture, `RGBDepthUtils` generates and saves a colored point cloud file.

## Development Conventions

*   **MVVM:** The code is structured around the Model-View-ViewModel pattern.
*   **Performance:** The app includes several optimizations for real-time performance, such as frame skipping and performing expensive calculations on background threads.
*   **File Naming:** Files are named clearly based on their primary class and functionality (e.g., `ARViewModel.swift`, `MetalRenderer.swift`).
