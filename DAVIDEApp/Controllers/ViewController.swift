/*
See LICENSE folder for this sample’s licensing information.
 
Modified by Jussi Kalliola (TAU) on 9.1.2023.

Abstract:
Main view controller for the scanning UI.
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
    
    // UI Elements
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var navBarBackground: UIVisualEffectView!
    @IBOutlet weak var nextButton: RoundedButton!
    var backButton: UIBarButtonItem!
    var mergeScanButton: UIBarButtonItem!
    @IBOutlet weak var instructionView: UIVisualEffectView!
    @IBOutlet weak var instructionLabel: MessageLabel!
    @IBOutlet weak var loadModelButton: RoundedButton!
    @IBOutlet weak var saveButton: RoundedButton!
    @IBOutlet weak var navigationBar: UINavigationBar!
    @IBOutlet weak var sessionInfoView: UIVisualEffectView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var toggleInstructionsButton: RoundedButton!
    
    @IBOutlet weak var statsLabel: UILabel!
    @IBOutlet weak var timeSider: UISlider!
    internal var internalState: State = .notReady
    
    
    internal var messageExpirationTimer: Timer?
    internal var startTimeOfLastMessage: TimeInterval?
    internal var expirationTimeOfLastMessage: TimeInterval?
    
    internal var screenCenter = CGPoint()
    
    var timeOfRun: Double = 0.0
    
    var currentARFrame: ARFrame!
    
    var textureCache: CVMetalTextureCache!
    var fileCounter: Int = 0
    var savedFrames: [SavedFrame] = []
    
    var fileManager: FileManagerHelper! = nil
    
    var RGBTexture: MTLTexture! = nil
    var metalDevice: MTLDevice! = nil
    var computePipelineState: MTLComputePipelineState! = nil
    
    let queue = DispatchQueue(label: "DAVIDEApp.save-data", qos: .userInitiated)
    
    var capture: ARCapture?
    var motion: CMMotionManager!
    var motionData: CMDeviceMotion = CMDeviceMotion()
    var motionDataArr: [CMDeviceMotion] = []
    
    let captureSession = AVCaptureSession()
    let captureDevice = AVCaptureDevice.default(for: .video)
    var deviceInput: AVCaptureDeviceInput!
    let output = AVCaptureVideoDataOutput()
    
    // output 1080x1920 in H.264
    let outputSettings: [String: Any] = [
        AVVideoWidthKey: 1080,
        AVVideoHeightKey: 1920,
        AVVideoCodecKey: AVVideoCodecType.h264
    ]
    
    var assetWriterInput: AVAssetWriterInput!
    
    let sourcePixelBufferAttributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!

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
                    self.motionData = validData
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
    

    @IBAction func loadModelButtonTapped(_ sender: Any) {
        guard !loadModelButton.isHidden && loadModelButton.isEnabled else { return }
        
        self.videoCapture.finish()
        loadModelButton.isEnabled = false
        nextButton.isEnabled = false
        shareFiles()
        
        loadModelButton.isEnabled = true
        nextButton.isEnabled = true

    }
    
    @IBAction func leftButtonTouchAreaTapped(_ sender: Any) {
        // A tap in the extended hit area on the lower left should cause a tap
        //  on the button that is currently visible at that location.
        if !loadModelButton.isHidden {
            loadModelButtonTapped(self)
        }
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
        camPos.worldQuaternion = sceneView.pointOfView!.simdWorldOrientation
        camPos.worldPose = currentFrame.camera.transform
        camPos.intrinsics = currentFrame.camera.intrinsics
        
        return camPos
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame else { return }
        
        self.currentARFrame = frame
        
        if self.videoCapture.ready {
            self.videoCapture.appendToVideo(pixelBuffer: frame.capturedImage, frameCount: self.frameCount)
            self.cameraPoses.append(self.capturePose(currentFrame: frame, frameCount: self.frameCount, fps: self.fps))
            self.motionDataArr.append(self.motionData)
            
            if #available(iOS 14.0, *) {
                if let depth = frame.sceneDepth?.depthMap {
                    print("saving depth frame.")
                    _ = self.fileManager!.writeConfidence(pixelBuffer: frame.sceneDepth!.confidenceMap!, imageIdx: Int(self.frameCount))
                    _ = self.fileManager!.writeDepth(pixelBuffer: depth, imageIdx: Int(self.frameCount))
                }
            } else {
                // Fallback on earlier versions
            }

            self.frameCount += 1
            DispatchQueue.global().async(execute: {
                DispatchQueue.main.async {

                    let xyz = self.cameraPoses.last!.worldPose.columns.3.xyz
                    self.statsLabel.text = "Time: "+String(self.frameCount / Int64(self.fps))+" sec"+"\nFrames: "+String(self.frameCount)+"\nX="+String(round(100*xyz.x) / 100)+"\nY="+String(round(100*xyz.y) / 100)+"\nZ="+String(round(100*xyz.z) / 100)
                }
             })
        }

    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {

    }
    
    func readFile(_ url: URL) {

    }
    
    
    // Save files from temporary storage
    func shareFiles() {
        print("Share files....")
        
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 8

        do {
            operationQueue.addOperation {
                self.fileManager?.writeCameraPose(cameraPoses: self.cameraPoses, motionData: self.motionDataArr)
                self.fileManager?.writeFrameInfo(cameraPoses: self.cameraPoses)
            }
        } catch {
            print("error")
        }


        operationQueue.waitUntilAllOperationsAreFinished()
        
        
        var filesToShare = [Any]()
        filesToShare.append(self.fileManager!.path)
        let av = UIActivityViewController(activityItems: filesToShare, applicationActivities: nil)

        UIApplication.shared.keyWindow?.rootViewController?.present(av, animated: true, completion: nil)
    }
}
