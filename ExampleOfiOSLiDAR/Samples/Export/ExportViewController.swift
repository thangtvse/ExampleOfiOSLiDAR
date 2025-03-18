//
//  ExportViewController.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/02/10.
//

import RealityKit
import ARKit

class ExportViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!
    
    // Properties to store captured images and transforms
    private var capturedImages: [UIImage] = []
    private var capturedTransforms: [simd_float4x4] = []
    private var captureTimer: Timer?
    
    var orientation: UIInterfaceOrientation {
        guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
            fatalError()
        }
        return orientation
    }
    @IBOutlet weak var imageViewHeight: NSLayoutConstraint!
    lazy var imageViewSize: CGSize = {
        CGSize(width: view.bounds.size.width, height: imageViewHeight.constant)
    }()

    override func viewDidLoad() {
        func setARViewOptions() {
            arView.debugOptions.insert(.showSceneUnderstanding)
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
        func initARView() {
            setARViewOptions()
            let configuration = buildConfigure()
            arView.session.run(configuration)
        }
        arView.session.delegate = self
        super.viewDidLoad()
        initARView()
        
        // Start the image capture timer
        startImageCaptureTimer()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop the timer when view disappears
        stopImageCaptureTimer()
    }
    
    // MARK: - Image Capture
    
    private func startImageCaptureTimer() {
        // Create a timer that fires every 5 seconds
        captureTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(captureImageAndTransform), userInfo: nil, repeats: true)
        // Also capture one image immediately
        captureImageAndTransform()
    }
    
    private func stopImageCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    @objc private func captureImageAndTransform() {
        guard let currentFrame = arView.session.currentFrame else { return }
        
        // Get the camera transform
        let cameraTransform = currentFrame.camera.transform
        
        // Create a CIImage from the AR frame's captured image
        let pixelBuffer = currentFrame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Convert to UIImage in the correct orientation
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientationFromDeviceOrientation())
        
        // Save the image and transform
        capturedImages.append(image)
        capturedTransforms.append(cameraTransform)
        
        print("Captured image \(capturedImages.count) with transform")
    }
    
    private func imageOrientationFromDeviceOrientation() -> UIImage.Orientation {
        switch orientation {
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        default:
            return .right
        }
    }

    @IBAction func tappedExportButton(_ sender: UIButton) {
        guard let camera = arView.session.currentFrame?.camera else {return}

        func convertToAsset(meshAnchors: [ARMeshAnchor]) -> MDLAsset? {
            guard let device = MTLCreateSystemDefaultDevice() else {return nil}

            let asset = MDLAsset()

            for anchor in meshAnchors {
                let mdlMesh = anchor.geometry.toMDLMesh(device: device, camera: camera, modelMatrix: anchor.transform)
                asset.add(mdlMesh)
            }
            
            return asset
        }
        
        func exportMesh() throws -> URL {
            guard let meshAnchors = arView.session.currentFrame?.anchors.compactMap({ $0 as? ARMeshAnchor }),
                  let asset = convertToAsset(meshAnchors: meshAnchors) else {
                throw NSError(domain: "ExportViewController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create asset"])
            }
            
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = directory.appendingPathComponent("scaned.obj")

            try asset.export(to: url)

            return url
        }
        
        func exportImagesAndTransforms() throws -> URL {
            // Create a directory to store all exported files
            let fileManager = FileManager.default
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let exportDirectoryURL = documentsDirectory.appendingPathComponent("ARExport_\(Date().timeIntervalSince1970)")
            
            try fileManager.createDirectory(at: exportDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            
            // Export all images
            for (index, image) in capturedImages.enumerated() {
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    let imageURL = exportDirectoryURL.appendingPathComponent("image_\(index).jpg")
                    try imageData.write(to: imageURL)
                }
            }
            
            // Export transforms as JSON
            let transformsData: [[Float]] = capturedTransforms.map { transform in
                // Convert 4x4 matrix to array of 16 floats
                var floatArray: [Float] = []
                for row in 0..<4 {
                    for col in 0..<4 {
                        floatArray.append(transform[row][col])
                    }
                }
                return floatArray
            }
            
            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = .prettyPrinted
            let transformsJSON = try jsonEncoder.encode(transformsData)
            let transformsURL = exportDirectoryURL.appendingPathComponent("camera_transforms.json")
            try transformsJSON.write(to: transformsURL)
            
            // Create info file
            let infoDict: [String: Any] = [
                "totalImages": capturedImages.count,
                "exportDate": Date().description,
                "exportTimestamp": Date().timeIntervalSince1970
            ]
            
            if let infoData = try? JSONSerialization.data(withJSONObject: infoDict, options: .prettyPrinted) {
                let infoURL = exportDirectoryURL.appendingPathComponent("export_info.json")
                try infoData.write(to: infoURL)
            }
            
            return exportDirectoryURL
        }
        
        func share(url: URL) {
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = sender
            self.present(vc, animated: true, completion: nil)
        }
        
        // First check if we have captured any images
        if capturedImages.isEmpty {
            let alert = UIAlertController(
                title: "No Images Captured",
                message: "Wait for at least one image capture before exporting.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            return
        }
        
        do {
            // Export mesh
            let meshURL = try exportMesh()
            
            // Export images and transforms
            let exportDirectoryURL = try exportImagesAndTransforms()
            
            // Copy mesh to the export directory
            let fileManager = FileManager.default
            let destinationMeshURL = exportDirectoryURL.appendingPathComponent("scaned.obj")
            try fileManager.copyItem(at: meshURL, to: destinationMeshURL)
            
            // Share the export directory
            share(url: exportDirectoryURL)
            
            // Show success message
            let alert = UIAlertController(
                title: "Export Successful",
                message: "Exported \(capturedImages.count) images with camera transforms and 3D mesh.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            
        } catch {
            print("Export error: \(error.localizedDescription)")
            
            // Show error message
            let alert = UIAlertController(
                title: "Export Failed",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
}
