//
//  ScanViewController.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/02/10.
//

import RealityKit
import ARKit

class LabelScene: SKScene {
    let label = SKLabelNode()
    var onTapped: (() -> Void)? = nil

    override public init(size: CGSize){
        super.init(size: size)

        self.scaleMode = SKSceneScaleMode.resizeFill

        label.fontSize = 65
        label.fontColor = .blue
        label.position = CGPoint(x:frame.midX, y: label.frame.size.height + 50)

        self.addChild(label)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Not been implemented")
    }
    
    convenience init(size: CGSize, onTapped: @escaping () -> Void) {
        self.init(size: size)
        self.onTapped = onTapped
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let onTapped = self.onTapped {
            onTapped()
        }
    }
    
    func setText(text: String) {
        label.text = text
    }
}
class ScanViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    // Custom structure to store only essential frame data
    struct FrameCapture {
        let image: UIImage
        let cameraTransform: simd_float4x4
        let timestamp: TimeInterval
    }
    
    enum ScanMode {
        case noneed
        case doing
        case done
    }
    
    @IBOutlet weak var sceneView: ARSCNView!
    var scanMode: ScanMode = .noneed
    var originalSource: Any? = nil
    var scanButton: UIButton!
    // Replace ARFrame array with our custom structure
    var capturedFrames: [FrameCapture] = []
    var isCapturingFrames: Bool = false
    var lastCaptureTime: TimeInterval = 0
    
    override func viewDidLoad() {
        func setARViewOptions() {
            sceneView.scene = SCNScene()
        }
        func buildConfigure() -> ARWorldTrackingConfiguration {
            let configuration = ARWorldTrackingConfiguration()

            configuration.environmentTexturing = .automatic
            configuration.sceneReconstruction = .mesh
            if type(of: configuration).supportsFrameSemantics(.sceneDepth) {
               configuration.frameSemantics = .sceneDepth
            }

            return configuration
        }
        func setControls() {
            // Create and configure the scan button
            scanButton = UIButton(type: .system)
            scanButton.setTitle("Scan Geometry", for: .normal)
            scanButton.backgroundColor = .systemBlue
            scanButton.setTitleColor(.white, for: .normal)
            scanButton.layer.cornerRadius = 10
            scanButton.translatesAutoresizingMaskIntoConstraints = false
            scanButton.addTarget(self, action: #selector(scanButtonTapped), for: .touchUpInside)
            
            // Add button to view and set constraints
            view.addSubview(scanButton)
            NSLayoutConstraint.activate([
                scanButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                scanButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                scanButton.widthAnchor.constraint(equalToConstant: 200),
                scanButton.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
        super.viewDidLoad()
        sceneView.delegate = self
        sceneView.session.delegate = self
        setARViewOptions()
        let configuration = buildConfigure()
        sceneView.session.run(configuration)
        setControls()
        isCapturingFrames = true
        capturedFrames.removeAll()
    }
    
    @objc func scanButtonTapped() {
        // Stop capturing frames
        isCapturingFrames = false
        
        // Set scan mode to stop anchor scanning
        scanMode = .done
        
        // Change background color for better visualization
        sceneView.scene.background.contents = UIColor.black
        
        print("Starting geometry scan with \(capturedFrames.count) captured frames. No new anchors will be processed.")
        
        // Process all existing anchors with the captured frames
        scanAllGeometry(needTexture: true)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        // Only process new anchors if we're in normal mode (not scanning or done)
        guard scanMode == .noneed else {
            return nil
        }
        guard let anchor = anchor as? ARMeshAnchor,
              let frame = sceneView.session.currentFrame else { return nil }

        let node = SCNNode()
        let geometry = scanGeometory(frame: frame, anchor: anchor, node: node)
        node.geometry = geometry

        return node
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Only update existing nodes if we're in normal mode (not scanning or done)
        guard scanMode == .noneed else {
            return
        }
        guard let frame = self.sceneView.session.currentFrame else { return }
        guard let anchor = anchor as? ARMeshAnchor else { return }
        let geometry = self.scanGeometory(frame: frame, anchor: anchor, node: node)
        node.geometry = geometry
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if isCapturingFrames, let currentFrame = sceneView.session.currentFrame {
            // Capture one frame every 1 second (was 10 seconds before)
            if time - lastCaptureTime >= 1 {
                // Extract only the necessary data from the frame
                if let image = extractImageFromFrame(currentFrame) {
                    let frameCapture = FrameCapture(
                        image: image,
                        cameraTransform: currentFrame.camera.transform,
                        timestamp: time
                    )
                    capturedFrames.append(frameCapture)
                    lastCaptureTime = time
                    print("Captured frame at time \(time). Total frames: \(capturedFrames.count)")
                }
            }
        }
    }
    
    // Helper function to extract UIImage from ARFrame
    private func extractImageFromFrame(_ frame: ARFrame) -> UIImage? {
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    func scanGeometory(frame: ARFrame, anchor: ARMeshAnchor, node: SCNNode, needTexture: Bool = false, cameraImage: UIImage? = nil) -> SCNGeometry {
        let camera = frame.camera
        let geometry = SCNGeometry(geometry: anchor.geometry, camera: camera, modelMatrix: anchor.transform, needTexture: needTexture)

        if let image = cameraImage, needTexture {
            geometry.firstMaterial?.diffuse.contents = image
        } else {
            geometry.firstMaterial?.diffuse.contents = UIColor(red: 0.5, green: 1.0, blue: 0.0, alpha: 0.7)
        }
        node.geometry = geometry

        return geometry
    }
    
    func scanAllGeometry(needTexture: Bool) {
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        // If we don't need textures or don't have captured frames, use the current frame
        if !needTexture || capturedFrames.isEmpty {
            guard let cameraImage = captureCamera() else { return }
            
            let anchors = currentFrame.anchors
            let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
            for anchor in meshAnchors {
                guard let node = sceneView.node(for: anchor) else { continue }
                let geometry = scanGeometory(frame: currentFrame, anchor: anchor, node: node, needTexture: needTexture, cameraImage: cameraImage)
                node.geometry = geometry
            }
            return
        }
        
        print("Processing \(capturedFrames.count) frames for optimal texturing...")
        
        // Get all mesh anchors from the current frame
        let anchors = currentFrame.anchors
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        
        // Dictionary to track the best frame for each node based on viewing angle
        var bestFrameForNode: [SCNNode: (frameCapture: FrameCapture, score: Float)] = [:]
        
        // Process each anchor
        for anchor in meshAnchors {
            guard let node = sceneView.node(for: anchor) else { continue }
            
            // Get the center position of the mesh in world space
            let meshCenter = anchor.transform.columns.3
            let meshPosition = simd_float3(meshCenter.x, meshCenter.y, meshCenter.z)
            
            // Process each captured frame to find the best one for this node
            for frameCapture in capturedFrames {
                // Get camera position from the stored transform
                let cameraTransform = frameCapture.cameraTransform
                let cameraPosition = simd_float3(cameraTransform.columns.3.x, 
                                                cameraTransform.columns.3.y,
                                                cameraTransform.columns.3.z)
                
                // Calculate direction vector from camera to mesh
                let directionToMesh = simd_normalize(meshPosition - cameraPosition)
                
                // Calculate camera forward vector (negative z-axis of camera transform)
                let cameraForward = simd_normalize(simd_float3(-cameraTransform.columns.2.x,
                                                             -cameraTransform.columns.2.y,
                                                             -cameraTransform.columns.2.z))
                
                // Calculate the dot product (higher value means better angle)
                let alignmentScore = simd_dot(directionToMesh, cameraForward)
                
                // Also consider distance (not too close, not too far)
                let distance = simd_length(meshPosition - cameraPosition)
                let distanceScore: Float = 1.0 / (1.0 + abs(distance - 0.5)) // 0.5m is ideal distance
                
                // Combined score
                let score = alignmentScore * distanceScore
                
                // Update if this is the best frame so far
                if let currentBest = bestFrameForNode[node], currentBest.score < score {
                    bestFrameForNode[node] = (frameCapture, score)
                } else if bestFrameForNode[node] == nil {
                    bestFrameForNode[node] = (frameCapture, score)
                }
            }
        }
        
        // Apply the best frame for each node
        for anchor in meshAnchors {
            guard let node = sceneView.node(for: anchor) else { continue }
            
            if let bestData = bestFrameForNode[node] {
                // Use the best frame's image directly - no need to extract it again
                let bestImage = bestData.frameCapture.image
                
                // For scan geometry we need an ARFrame, so use the current frame but with our texture
                let geometry = scanGeometory(frame: currentFrame, anchor: anchor, node: node, needTexture: true, cameraImage: bestImage)
                node.geometry = geometry
            }
        }
        
        print("Finished applying textures from \(capturedFrames.count) frames")
    }

    // Original method no longer needed as we extract images immediately during capture
    func captureCamera() -> UIImage? {
        guard let frame = sceneView.session.currentFrame else {return nil}
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options:nil)
        guard let cameraImage = context.createCGImage(ciImage, from: ciImage.extent) else {return nil}
        return UIImage(cgImage: cameraImage)
    }
}
