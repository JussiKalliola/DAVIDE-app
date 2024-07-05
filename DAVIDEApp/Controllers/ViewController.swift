/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the object scanning UI.
*/

import UIKit
import SceneKit
import ARKit
import MetalKit
import CoreMotion


@available(iOS 13.0, *)
class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, UIDocumentPickerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    static let appStateChangedNotification = Notification.Name("ApplicationStateChanged")
    static let appStateUserInfoKey = "AppState"
    
    static var instance: ViewController?
    
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var navBarBackground: UIVisualEffectView!
    @IBOutlet weak var nextButton: RoundedButton!
    var backButton: UIBarButtonItem!
    var mergeScanButton: UIBarButtonItem!
    @IBOutlet weak var instructionView: UIVisualEffectView!
    @IBOutlet weak var instructionLabel: MessageLabel!
    @IBOutlet weak var loadModelButton: RoundedButton!
    @IBOutlet weak var saveButton: RoundedButton!
    @IBOutlet weak var flashlightButton: FlashlightButton!
    @IBOutlet weak var navigationBar: UINavigationBar!
    @IBOutlet weak var sessionInfoView: UIVisualEffectView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var toggleInstructionsButton: RoundedButton!
    
    @IBOutlet weak var statsLabel: UILabel!
    @IBOutlet weak var timeSider: UISlider!
    internal var internalState: State = .notReady
    
    
    var referenceObjectToMerge: ARReferenceObject?
    var referenceObjectToTest: ARReferenceObject?
    
    internal var messageExpirationTimer: Timer?
    internal var startTimeOfLastMessage: TimeInterval?
    internal var expirationTimeOfLastMessage: TimeInterval?
    
    internal var screenCenter = CGPoint()
    
    var timeOfRun: Double = 0.0
    var labelTimer = Timer()
    
    var timer = Timer()
    var currentARFrame: ARFrame!
    
    var textureCache: CVMetalTextureCache!
    var fileCounter: Int = 0
    var savedFrames: [SavedFrame] = []
    
    var fileManager: FileManagerHelper! = nil
    
    var boxPose: BoxPose = BoxPose()
    
    var RGBTexture: MTLTexture! = nil
    var metalDevice: MTLDevice! = nil
    var computePipelineState: MTLComputePipelineState! = nil
    
    let queue = DispatchQueue(label: "save-data", qos: .userInitiated)
    
    var capture: ARCapture?
    var motion: CMMotionManager!
    var motionData: CMDeviceMotion = CMDeviceMotion()
    var motionDataArr: [CMDeviceMotion] = []
    
    // Motion data
    //let timestamp = validData.timestamp
    //let attitude = validData.attitude
    //let quaternion = validData.attitude.quaternion
    //let rotationRate = validData.rotationRate
    //let userAcceleration = validData.userAcceleration
    //let gravity = validData.gravity
    
    let captureSession = AVCaptureSession()
    let captureDevice = AVCaptureDevice.default(for: .video)
    var deviceInput: AVCaptureDeviceInput!
    let output = AVCaptureVideoDataOutput()
    
    // to prepare for output; I'll output 640x480 in H.264, via an asset writer
    let outputSettings: [String: Any] = [
        AVVideoWidthKey: 1080,
        AVVideoHeightKey: 1920,
        AVVideoCodecKey: AVVideoCodecType.h264
    ]
    
    var assetWriterInput: AVAssetWriterInput!
    
    // I'm going to push pixel buffers to it, so will need a
    // AVAssetWriterPixelBufferAdaptor, to expect the same 32BGRA input as I've
    // asked the AVCaptureVideDataOutput to supply
    let sourcePixelBufferAttributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!

    // that's going to go somewhere, I imagine you've got the URL for that sorted,
    // so create a suitable asset writer; we'll put our H.264 within the normal
    // MPEG4 container
    var assetWriter: AVAssetWriter!
    
    var videoCapture: VideoCapture!
    var frameCount: Int64 = 0
    var fps: Int32 = 30
    var cameraPoses: [CameraPose] = []
    
    // Create an empty texture.
    func createTexture(metalDevice: MTLDevice, width: Int, height: Int, usage: MTLTextureUsage, pixelFormat: MTLPixelFormat) -> MTLTexture {
        let descriptor: MTLTextureDescriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.usage = usage
        let resTexture = metalDevice.makeTexture(descriptor: descriptor)
        return resTexture!
    }
    
    
    var instructionsVisible: Bool = true {
        didSet {
            instructionView.isHidden = !instructionsVisible
            toggleInstructionsButton.toggledOn = instructionsVisible
        }
    }
    
    // MARK: - Application Lifecycle
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ViewController.instance = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        metalDevice = EnvironmentVariables.shared.metalDevice
        
        RGBTexture = self.createTexture(metalDevice: metalDevice!,
                                          width: 1920,
                                          height: 1440,
                                          usage: [.shaderRead, .shaderWrite],
                                          pixelFormat: .rgba8Unorm)
        
        fileManager = FileManagerHelper()
        CVMetalTextureCacheCreate(nil, nil, metalDevice!, nil, &self.textureCache)
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.preferredFramesPerSecond = Int(self.fps)
        
        
        // Prevent the screen from being dimmed after a while.
        UIApplication.shared.isIdleTimerDisabled = true
        
        let notificationCenter = NotificationCenter.default
        
        self.statsLabel.backgroundColor = UIColor(white: 0, alpha: 0.5)
        self.statsLabel.layer.cornerRadius = CGFloat(5)
        self.statsLabel.isHidden=true
        
        self.sessionInfoView.isHidden = true

        setupNavigationBar()
    
        
        self.startMotionCapture()
        
        //captureSession.sessionPreset = .hd1920x1080
        //deviceInput = try? AVCaptureDeviceInput(device: captureDevice!)
        //captureSession.addInput(deviceInput!)
        
        //output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        //output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "queue"))
        //captureSession.addOutput(output)
        
        //assetWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings)
        
        //pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        
        //assetWriter = try? AVAssetWriter(url: fileManager.path!, fileType: AVFileType.mp4)
        
        //assetWriter?.add(assetWriterInput)

        // we need to warn the input to expect real time data incoming, so that it tries
        // to avoid being unavailable at inopportune moments
        //assetWriterInput.expectsMediaDataInRealTime = true

        // eventually
        //assetWriter?.startWriting()
        //assetWriter?.startSession(atSourceTime: CMTime.zero)
        //captureSession.startRunning()
        
        self.videoCapture = VideoCapture(codec: .h264, width: 1920, height: 1440, path: fileManager.path!, fps: self.fps)
        
        // Make sure the application launches in .startARSession state.
        // Entering this state will run() the ARSession.
        state = .startARSession
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Store the screen center location after the view's bounds did change,
        // so it can be retrieved later from outside the main thread.
        screenCenter = sceneView.center
    }
    
    
    // MARK: Start Motion Capture
    private func startMotionCapture() {
        self.motion = CMMotionManager()
        
        if self.motion.isDeviceMotionAvailable { self.motion!.deviceMotionUpdateInterval = 1.0 / 200.0 // ask for 200Hz but max frequency is 100Hz for 14pro
            self.motion.showsDeviceMovementDisplay = true
            // get the attitude relative to the magnetic north reference frame
            self.motion.startDeviceMotionUpdates(using: .xArbitraryZVertical,
                                                 to: OperationQueue(), withHandler: { (data, error) in
                // make sure the data is valid before accessing it
                if let validData = data {
                    
                    let timestamp = validData.timestamp
                    
                    let attitude = validData.attitude
                    let quaternion = validData.attitude.quaternion
                    let rotationRate = validData.rotationRate
                    let userAcceleration = validData.userAcceleration
                    let gravity = validData.gravity
                    
                    self.motionData = validData
                    
                    
                    
//                    // generate header information to parse later in python
//                    var header = """
//                    <BEGINHEADER>
//                    frameCount:\(String(describing: self.frameCount)),timestamp:\(String(describing: timestamp)),
//                    quaternionX:\(String(describing: quaternion.x)),quaternionY:\(String(describing: quaternion.y)),
//                    quaternionZ:\(String(describing: quaternion.z)),quaternionW:\(String(describing: quaternion.w)),
//                    rotationRateX:\(String(describing: rotationRate.x)),rotationRateY:\(String(describing: rotationRate.y)),
//                    rotationRateZ:\(String(describing: rotationRate.z)),roll:\(String(describing: attitude.roll)),
//                    pitch:\(String(describing: attitude.pitch)),yaw:\(String(describing: attitude.yaw)),
//                    userAccelerationX:\(String(describing: userAcceleration.x)),userAccelerationY:\(String(describing: userAcceleration.y)),
//                    userAccelerationZ:\(String(describing: userAcceleration.z)),gravityX:\(String(describing: gravity.x)),
//                    gravityY:\(String(describing: gravity.y)),gravityZ:\(String(describing: gravity.z))
//                    <ENDHEADER>
//                    """
//
//                    print(header)
                }
            })
        }
    }

    
    // MARK: - UI Event Handling
    
    @IBAction func restartButtonTapped(_ sender: Any) {
        
        self.restartApp()
    }
    
    func restartApp() {
        
        if(state == .scanning || state == .saving) {
            self.fileManager.clearTempFolder()
            self.videoCapture.finish()
            self.videoCapture = VideoCapture(codec: .h264, width: 1920, height: 1440, path: fileManager.path!, fps: self.fps)
        }
        self.statsLabel.text = ""
        state = .startARSession
        
        self.frameCount = 0
        
        self.setNavigationBarTitle("")
        
        instructionsVisible = false
        showBackButton(false)
        nextButton.isEnabled = true
        nextButton.isHidden = false
        loadModelButton.isHidden = true
        flashlightButton.isHidden = true
        nextButton.setTitle("Start", for: [])
    }
    
    func backFromBackground() {
        if state == .scanning {
            let title = "Warning: Scan may be broken"
            let message = "The scan was interrupted. It is recommended to restart the scan."
            let buttonTitle = "Restart Scan"
            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: true) { _ in
                self.state = .notReady
            }
        }
    }
    
    @IBAction func previousButtonTapped(_ sender: Any) {
        switchToPreviousState()
    }
    
    @IBAction func nextButtonTapped(_ sender: Any) {
        guard !nextButton.isHidden && nextButton.isEnabled else { return }
        switchToNextState()
    }
    
    @IBAction func addScanButtonTapped(_ sender: Any) {
//        guard state == .testing else { return }

        let title = "Merge another scan?"
        let message = """
            Merging multiple scan results improves detection.
            You can start a new scan now to merge into this one, or load an already scanned *.arobject file.
            """
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        alertController.addAction(UIAlertAction(title: "Merge ARObject File…", style: .default) { _ in
            // Show a document picker to choose an existing scan
            self.showFilePickerForLoadingScan()
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func showFilePickerForLoadingScan() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["com.apple.arobject"], in: .import)
        documentPicker.delegate = self
        
        documentPicker.modalPresentationStyle = .overCurrentContext
        documentPicker.popoverPresentationController?.barButtonItem = mergeScanButton
        
        DispatchQueue.main.async {
            self.present(documentPicker, animated: true, completion: nil)
        }
    }
    

    func shareFiles() {
        print("Share files....")
        //arProvider.pause()
        //self.queue.async {
        
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 8

        do {

//            let savedFrames = self.savedFrames
//            var cameraPoses: [CameraPose] = []
//            for frame in savedFrames {
//                let sourceImgPath = self.fileManager!.path!.path + "/" + frame.rgbPath
//                let targetImgPath =  self.fileManager!.path!.path + "/rgb/" + frame.rgbPath.dropLast(4) + ".jpeg"
//
//                cameraPoses.append(frame.pose)
//
//                operationQueue.addOperation {
//                    self.fileManager?.convertBinToJpeg(sourceFilePath: sourceImgPath,
//                                                             targetFilePath: targetImgPath,
//                                                             width: frame.rgbResolution[1],
//                                                             height: frame.rgbResolution[0],
//                                                             orientation: .portrait)
//                }
//            }


            operationQueue.addOperation {
                self.fileManager?.writeCameraPose(cameraPoses: self.cameraPoses, motionData: self.motionDataArr)
                self.fileManager?.writeFrameInfo(cameraPoses: self.cameraPoses)
            }
        } catch {
            print("error")
        }


        operationQueue.waitUntilAllOperationsAreFinished()
        
        
        //DispatchQueue.main.async {
        var filesToShare = [Any]()
        filesToShare.append(self.fileManager!.path)
        let av = UIActivityViewController(activityItems: filesToShare, applicationActivities: nil)

        UIApplication.shared.keyWindow?.rootViewController?.present(av, animated: true, completion: nil)
        //}
        //}
    }
    

    @IBAction func loadModelButtonTapped(_ sender: Any) {
        guard !loadModelButton.isHidden && loadModelButton.isEnabled else { return }
        
        self.videoCapture.finish()
        loadModelButton.isEnabled = false
        nextButton.isEnabled = false
        shareFiles()
        
        loadModelButton.isEnabled = true
        nextButton.isEnabled = true
        
//        let documentPicker = UIDocumentPickerViewController(documentTypes: ["com.pixar.universal-scene-description-mobile"], in: .import)
//        documentPicker.delegate = self
//
//        documentPicker.modalPresentationStyle = .overCurrentContext
//        documentPicker.popoverPresentationController?.sourceView = self.loadModelButton
//        documentPicker.popoverPresentationController?.sourceRect = self.loadModelButton.bounds
//
//        DispatchQueue.main.async {
//            self.present(documentPicker, animated: true, completion: nil)
//        }
    }
    
    @IBAction func leftButtonTouchAreaTapped(_ sender: Any) {
        // A tap in the extended hit area on the lower left should cause a tap
        //  on the button that is currently visible at that location.
        if !loadModelButton.isHidden {
            loadModelButtonTapped(self)
        } else if !flashlightButton.isHidden {
            toggleFlashlightButtonTapped(self)
        }
    }
    
    @IBAction func toggleFlashlightButtonTapped(_ sender: Any) {
        guard !flashlightButton.isHidden && flashlightButton.isEnabled else { return }
        flashlightButton.toggledOn = !flashlightButton.toggledOn
    }
    
    @IBAction func toggleInstructionsButtonTapped(_ sender: Any) {
        guard !toggleInstructionsButton.isHidden && toggleInstructionsButton.isEnabled else { return }
        instructionsVisible.toggle()
    }
    
    func displayInstruction(_ message: Message) {
        instructionLabel.display(message)
        instructionsVisible = true
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        readFile(url)
    }
    
    func showAlert(title: String, message: String, buttonTitle: String? = "OK", showCancel: Bool = false, buttonHandler: ((UIAlertAction) -> Void)? = nil) {
        print(title + "\n" + message)
        
        var actions = [UIAlertAction]()
        if let buttonTitle = buttonTitle {
            actions.append(UIAlertAction(title: buttonTitle, style: .default, handler: buttonHandler))
        }
        if showCancel {
            actions.append(UIAlertAction(title: "Cancel", style: .cancel))
        }
        self.showAlert(title: title, message: message, actions: actions)
    }
    
    func showAlert(title: String, message: String, actions: [UIAlertAction]) {
        let showAlertBlock = {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            actions.forEach { alertController.addAction($0) }
            DispatchQueue.main.async {
                self.present(alertController, animated: true, completion: nil)
            }
        }
        
        if presentedViewController != nil {
            dismiss(animated: true) {
                showAlertBlock()
            }
        } else {
            showAlertBlock()
        }
    }
    
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        
    }
    
    func capturePose(currentFrame: ARFrame, frameCount: Int64, fps: Int32) -> CameraPose {
        var camPos = CameraPose()
        
        
        camPos.timeStamp = CMTimeMake(value: frameCount, timescale: fps)
//        camPos.eulerAngles = currentFrame.camera.eulerAngles
        camPos.worldQuaternion = sceneView.pointOfView!.simdWorldOrientation
//        camPos.localQuaternion = sceneView.pointOfView!.simdOrientation
        camPos.worldPose = currentFrame.camera.transform
        camPos.intrinsics = currentFrame.camera.intrinsics
//        camPos.projectionMatrix = currentFrame.camera.projectionMatrix
//        camPos.worldToCamera = currentFrame.camera.viewMatrix(for: UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? UIInterfaceOrientation.unknown)
//        camPos.translation = simd_float3(currentFrame.camera.transform.columns.3.x, currentFrame.camera.transform.columns.3.y, currentFrame.camera.transform.columns.3.z)
        
        return camPos
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame else { return }
        
        self.currentARFrame = frame
        
        if self.videoCapture.ready {
            //queue.async {
            self.videoCapture.appendToVideo(pixelBuffer: frame.capturedImage, frameCount: self.frameCount)
            self.cameraPoses.append(self.capturePose(currentFrame: frame, frameCount: self.frameCount, fps: self.fps))
            self.motionDataArr.append(self.motionData)
            //queue.async {
            if #available(iOS 14.0, *) {
                if let depth = frame.sceneDepth?.depthMap {
                    print("saving depth frame.")
                    _ = self.fileManager!.writeConfidence(pixelBuffer: frame.sceneDepth!.confidenceMap!, imageIdx: Int(self.frameCount))
                    _ = self.fileManager!.writeDepth(pixelBuffer: depth, imageIdx: Int(self.frameCount))
                }
            } else {
                // Fallback on earlier versions
            }
            //}
            self.frameCount += 1
            DispatchQueue.global().async(execute: {
                DispatchQueue.main.async {

                    let xyz = self.cameraPoses.last!.worldPose.columns.3.xyz
                    self.statsLabel.text = "Time: "+String(self.frameCount / Int64(self.fps))+" sec"+"\nFrames: "+String(self.frameCount)+"\nX="+String(round(100*xyz.x) / 100)+"\nY="+String(round(100*xyz.y) / 100)+"\nZ="+String(round(100*xyz.z) / 100)
                    // etc
                }
             })
            //}
        }
        //print(frame.camera.transform.columns.3)
        //print(sceneView.pointOfView?.simdWorldPosition)
        //print(self.scan?.scannedObject.boundingBox?.simdWorldPosition)

    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {

    }
    
    func readFile(_ url: URL) {

    }
}
