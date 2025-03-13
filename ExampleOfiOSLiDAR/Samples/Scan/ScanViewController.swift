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

        // Log when a new node is created
        let anchors = sceneView.session.currentFrame?.anchors ?? []
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        print("New node created. Current counts - Mesh anchors: \(meshAnchors.count)")
        
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
            print("Processing with current frame only. Mesh anchors: \(meshAnchors.count)")
            
            var nodeCount = 0
            for anchor in meshAnchors {
                guard let node = sceneView.node(for: anchor) else { continue }
                nodeCount += 1
                let geometry = scanGeometory(frame: currentFrame, anchor: anchor, node: node, needTexture: needTexture, cameraImage: cameraImage)
                node.geometry = geometry
            }
            print("Processed \(nodeCount) nodes out of \(meshAnchors.count) mesh anchors")
            return
        }
        
        print("Processing \(capturedFrames.count) frames for texture mapping...")
        
        // Get all mesh anchors from the current frame
        let anchors = currentFrame.anchors
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        print("Total mesh anchors found: \(meshAnchors.count)")
        
        // Dictionary to track the frame to use for each node
        var frameForNode: [SCNNode: FrameCapture] = [:]
        
        // Count valid nodes
        var validNodeCount = 0
        
        // Process each anchor
        for anchor in meshAnchors {
            guard let node = sceneView.node(for: anchor) else { continue }
            validNodeCount += 1
            
            // Get the center position of the mesh in world space
            let meshCenter = anchor.transform.columns.3
            let meshPosition = simd_float3(meshCenter.x, meshCenter.y, meshCenter.z)
            
            // Track frame filtering statistics for this node
            var totalFramesProcessed = 0
            var frameFound = false
            
            // Process each captured frame until we find one where the node is visible
            for frameCapture in capturedFrames {
                totalFramesProcessed += 1
                
                // Get camera position from the stored transform
                let cameraTransform = frameCapture.cameraTransform
                
                // First check: Is the node in front of the camera? (positive dot product)
                let cameraForward = simd_normalize(simd_float3(-cameraTransform.columns.2.x,
                                                             -cameraTransform.columns.2.y,
                                                             -cameraTransform.columns.2.z))
                let directionToMesh = simd_normalize(meshPosition - simd_float3(cameraTransform.columns.3.x, 
                                                          cameraTransform.columns.3.y,
                                                          cameraTransform.columns.3.z))
                let alignmentScore = simd_dot(directionToMesh, cameraForward)
                
                guard alignmentScore > 0 else { continue }
                
                // Second check: Is the node within the camera's field of view?
                let isVisible = isNodeVisibleInCamera(nodePosition: meshPosition, 
                                                     cameraTransform: cameraTransform)
                
                // Skip this frame if the node is not visible
                guard isVisible else { continue }
                
                // Found a frame where this node is visible - use it!
                frameForNode[node] = frameCapture
                frameFound = true
                break  // Stop processing more frames for this node
            }
            
            // Log statistics for this node
            if frameFound {
                print("Node \(node.description.prefix(20))... : Found frame after checking \(totalFramesProcessed) frames")
            } else {
                print("Node \(node.description.prefix(20))... : No suitable frame found after checking \(totalFramesProcessed) frames")
            }
        }
        
        print("Found \(frameForNode.count) nodes with viable frames out of \(validNodeCount) valid nodes")
        
        // Count nodes that received textures
        var texturedNodeCount = 0
        
        // Apply textures to each node
        for anchor in meshAnchors {
            guard let node = sceneView.node(for: anchor) else { continue }
            
            if let frameCapture = frameForNode[node] {
                texturedNodeCount += 1
                
                // Use the image directly - no blending needed
                let image = frameCapture.image
                
                // Apply the texture
                let geometry = scanGeometory(frame: currentFrame, anchor: anchor, node: node, needTexture: true, cameraImage: image)
                node.geometry = geometry
            }
        }
        
        print("Applied textures to \(texturedNodeCount) nodes out of \(validNodeCount) valid nodes")
        print("Finished texture mapping from \(capturedFrames.count) frames")
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

    // Helper function to determine if a node is visible in the camera's field of view
    private func isNodeVisibleInCamera(nodePosition: simd_float3, cameraTransform: simd_float4x4) -> Bool {
        // Create the view matrix (inverse of the camera transform)
        let viewMatrix = cameraTransform.inverse
        
        // Transform the node position into camera space
        var nodePositionVec = simd_float4(nodePosition.x, nodePosition.y, nodePosition.z, 1.0)
        nodePositionVec = viewMatrix * nodePositionVec
        
        // If node is behind the camera (negative z), it's not visible
        if nodePositionVec.z <= 0 {
            return false
        }
        
        // Approximate projection to check if within field of view
        // This uses a simplified perspective projection
        let aspectRatio: Float = 1.0  // Assuming square for simplicity, adjust if needed
        let fovY: Float = 60.0 * .pi / 180.0  // 60 degrees field of view, adjust if needed
        
        // Calculate normalized device coordinates (between -1 and 1)
        let tanHalfFov = tan(fovY / 2.0)
        let ndcX = nodePositionVec.x / (nodePositionVec.z * tanHalfFov * aspectRatio)
        let ndcY = nodePositionVec.y / (nodePositionVec.z * tanHalfFov)
        
        // Check if the point is within the normalized viewport (-1 to 1)
        // Adding some margin (0.9 instead of 1.0) to ensure good visibility
        return abs(ndcX) < 0.9 && abs(ndcY) < 0.9
    }
}
