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
        
        print("Processing \(capturedFrames.count) frames for texture blending...")
        
        // Get all mesh anchors from the current frame
        let anchors = currentFrame.anchors
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        print("Total mesh anchors found: \(meshAnchors.count)")
        
        // Dictionary to track frames for each node with their scores
        var framesForNode: [SCNNode: [(frameCapture: FrameCapture, score: Float)]] = [:]
        
        // Count valid nodes
        var validNodeCount = 0
        
        // Process each anchor
        for anchor in meshAnchors {
            guard let node = sceneView.node(for: anchor) else { continue }
            validNodeCount += 1
            
            // Get the center position of the mesh in world space
            let meshCenter = anchor.transform.columns.3
            let meshPosition = simd_float3(meshCenter.x, meshCenter.y, meshCenter.z)
            
            // Array to collect all frames for this node with their scores
            var frameScores: [(frameCapture: FrameCapture, score: Float)] = []
            
            // Process each captured frame to find good views for this node
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
                
                // Only include frames that have a reasonable view of the node
                // (where the object is somewhat in front of the camera)
                if alignmentScore > 0.6 { // Adjust this threshold as needed
                    frameScores.append((frameCapture, score))
                }
            }
            
            // Sort frames by score (best first)
            frameScores.sort { $0.score > $1.score }
            
            // Store frames for this node (up to a reasonable number to blend)
            framesForNode[node] = Array(frameScores.prefix(5)) // Use up to 5 frames for blending
        }
        
        print("Found \(validNodeCount) valid nodes out of \(meshAnchors.count) mesh anchors")
        print("Node texture stats: " + framesForNode.map { "Node: \($0.key.description) - \($0.value.count) frames" }.joined(separator: ", "))
        
        // Count nodes that received textures
        var texturedNodeCount = 0
        
        // Apply blended textures to each node
        for anchor in meshAnchors {
            guard let node = sceneView.node(for: anchor) else { continue }
            
            if let nodeScoredFrames = framesForNode[node], !nodeScoredFrames.isEmpty {
                texturedNodeCount += 1
                
                // Create a blended image from all good frames for this node
                let blendedImage = blendImagesForNode(frames: nodeScoredFrames)
                
                // For scan geometry we need an ARFrame, so use the current frame but with our blended texture
                let geometry = scanGeometory(frame: currentFrame, anchor: anchor, node: node, needTexture: true, cameraImage: blendedImage)
                node.geometry = geometry
            }
        }
        
        print("Applied blended textures to \(texturedNodeCount) nodes out of \(validNodeCount) valid nodes")
        print("Finished blending textures from \(capturedFrames.count) frames")
    }
    
    // Helper function to blend multiple images together with weighting based on scores
    private func blendImagesForNode(frames: [(frameCapture: FrameCapture, score: Float)]) -> UIImage {
        // If we only have one frame, just return its image
        if frames.count == 1 {
            return frames[0].frameCapture.image
        }
        
        // Calculate total weight for normalization
        let totalWeight = frames.reduce(0) { $0 + $1.score }
        
        // Start with the first image
        guard let firstImage = frames[0].frameCapture.image.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return frames[0].frameCapture.image // Fallback if we can't blend
        }
        
        // Get dimensions from the first image (these are non-optional)
        let width = firstImage.width
        let height = firstImage.height
        
        // Create a bitmap context to draw our blended result
        guard let context = CGContext(data: nil,
                                     width: width,
                                     height: height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: 0,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return frames[0].frameCapture.image // Fallback if we can't create context
        }
        
        // Clear context
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Normalize weights
        let normalizedWeights = frames.map { $0.score / totalWeight }
        
        // Blend images by painting them with their weights as alpha
        for (index, frame) in frames.enumerated() {
            if let cgImage = frame.frameCapture.image.cgImage {
                context.saveGState()
                context.setAlpha(CGFloat(normalizedWeights[index]))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                context.restoreGState()
            }
        }
        
        // Get the blended image
        if let blendedCGImage = context.makeImage() {
            return UIImage(cgImage: blendedCGImage)
        }
        
        // Fallback to the highest scored image if blending fails
        return frames[0].frameCapture.image
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
