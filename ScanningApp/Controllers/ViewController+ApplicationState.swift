/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Management of the UI steps for scanning an object in the main view controller.
*/

import Foundation
import ARKit
import SceneKit
import MetalKit

import Combine
import ARKit
import ModelIO
import MetalKit

final class MetalTextureContent {
    var texture: MTLTexture?
}

// Enable `CVPixelBuffer` to output an `MTLTexture`.
extension CVPixelBuffer {
    
    func texture(withFormat pixelFormat: MTLPixelFormat, planeIndex: Int, addToCache cache: CVMetalTextureCache) -> MTLTexture? {
        let width =  CVPixelBufferGetWidthOfPlane(self, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(self, planeIndex)
        
        var cvtexture: CVMetalTexture?
        _ = CVMetalTextureCacheCreateTextureFromImage(nil, cache, self, nil, pixelFormat, width, height, planeIndex, &cvtexture)
        let texture = CVMetalTextureGetTexture(cvtexture!)
        
        return texture
        
    }
    
}

@available(iOS 13.0, *)
extension ViewController {
    
    enum State {
        case startARSession
        case notReady
        case scanning
        case testing
    }
    
    /// - Tag: ARObjectScanningConfiguration
    // The current state the application is in
    var state: State {
        get {
            return self.internalState
        }
        set {
            // 1. Check that preconditions for the state change are met.
            var newState = newValue
            switch newValue {
            case .startARSession:
                break
            case .notReady:
                // Immediately switch to .ready if tracking state is normal.
                if let camera = self.sceneView.session.currentFrame?.camera {
                    switch camera.trackingState {
                    case .normal:
                        newState = .scanning
                    default:
                        break
                    }
                } else {
                    newState = .startARSession
                }
            case .scanning:
                // Immediately switch to .notReady if tracking state is not normal.
                if let camera = self.sceneView.session.currentFrame?.camera {
                    switch camera.trackingState {
                    case .normal:
                        break
                    default:
                        newState = .notReady
                    }
                } else {
                    newState = .startARSession
                }
            case .testing:
                guard scan?.boundingBoxExists == true || referenceObjectToTest != nil else {
                    print("Error: Scan is not ready to be tested.")
                    return
                }
            }
            
            // 2. Apply changes as needed per state.
            internalState = newState
            
            switch newState {
            case .startARSession:
                print("State: Starting ARSession")
                scan = nil
                testRun = nil
                modelURL = nil
                self.setNavigationBarTitle("")
                instructionsVisible = false
                showBackButton(false)
                nextButton.isEnabled = false
                loadModelButton.isHidden = true
                flashlightButton.isHidden = true
                
                // Make sure the SCNScene is cleared of any SCNNodes from previous scans.
                sceneView.scene = SCNScene()
                
                let configuration = ARWorldTrackingConfiguration()
                configuration.planeDetection = .horizontal
                
                if #available(iOS 14.0, *) {
                    configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth, .personSegmentationWithDepth]
                } else {
                    // Fallback on earlier versions
                }
                sceneView.session.run(configuration, options: .resetTracking)
                cancelMaxScanTimeTimer()
                cancelMessageExpirationTimer()
            case .notReady:
                print("State: Not ready to scan")
                scan = nil
                testRun = nil
                self.setNavigationBarTitle("")
                loadModelButton.isHidden = true
                flashlightButton.isHidden = true
                showBackButton(false)
                nextButton.isEnabled = false
                nextButton.setTitle("Next", for: [])
                displayInstruction(Message("Please wait for stable tracking"))
                cancelMaxScanTimeTimer()
            case .scanning:
                print("State: Scanning")
                if scan == nil {
                    self.scan = Scan(sceneView)
                    self.scan?.state = .ready
                }
                
                testRun = nil
                
                startMaxScanTimeTimer()
            case .testing:
                print("State: Testing")
                self.setNavigationBarTitle("Test")
                loadModelButton.isHidden = true
                flashlightButton.isHidden = false
                showMergeScanButton()
                nextButton.isEnabled = true
                nextButton.setTitle("Share", for: [])
                
                testRun = TestRun(sceneView: sceneView)
                testObjectDetection()
                cancelMaxScanTimeTimer()
            }
            
            NotificationCenter.default.post(name: ViewController.appStateChangedNotification,
                                            object: self,
                                            userInfo: [ViewController.appStateUserInfoKey: self.state])
        }
    }
    
    func getCameraPose(currentFrame: ARFrame) -> CameraPose {
        var camPos = CameraPose()
        
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
    
    func captureFrameData() {
        print("Capture frame data...")
        print(self.currentARFrame.camera.eulerAngles)
        var currentFrame = currentARFrame!
        
        var colorYTexture: MetalTextureContent = MetalTextureContent()
        var colorCbCrTexture: MetalTextureContent = MetalTextureContent()
        var colorRGBATexture: MetalTextureContent = MetalTextureContent()
        
        /// RGBA
        colorYTexture.texture = currentFrame.capturedImage.texture(withFormat: .r8Unorm,
                                                                            planeIndex: 0,
                                                                            addToCache: self.textureCache)!
        colorCbCrTexture.texture = currentFrame.capturedImage.texture(withFormat: .rg8Unorm,
                                                                               planeIndex: 1,
                                                                               addToCache: self.textureCache)!
        colorRGBATexture.texture = currentFrame.capturedImage.texture(withFormat: .rgba8Unorm,
                                                                              planeIndex: 0,
                                                                              addToCache: self.textureCache!)!

        guard let cmdBuffer = EnvironmentVariables.shared.metalCommandQueue.makeCommandBuffer() else { return }
        
        /// FOR RGBA
        if let computeFunction = EnvironmentVariables.shared.metalLibrary.makeFunction(name: "YUVColorConversion") {
            do {
                self.computePipelineState = try metalDevice?.makeComputePipelineState(function: computeFunction)
            } catch let error as NSError {
                fatalError("Error: \(error.localizedDescription)")
            }
        } else {
            fatalError("Kernel function not found at runtime.")
        }
        
        guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }
        
        computeEncoder.setComputePipelineState(computePipelineState)
        
        computeEncoder.setTexture(colorYTexture.texture, index: 0)
        computeEncoder.setTexture(colorCbCrTexture.texture, index: 1)
        computeEncoder.setTexture(RGBTexture, index: 2)
        
        var threadgroupSize = MTLSizeMake(computePipelineState!.threadExecutionWidth,
                                          computePipelineState!.maxTotalThreadsPerThreadgroup / computePipelineState!.threadExecutionWidth, 1)
        
        var threadgroupCount = MTLSize(width: Int(ceil(Float(colorRGBATexture.texture!.width) / Float(threadgroupSize.width))),
                                       height: Int(ceil(Float(colorRGBATexture.texture!.height) / Float(threadgroupSize.height))),
                                       depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        
        computeEncoder.endEncoding()
        
        cmdBuffer.commit()
        colorRGBATexture.texture = RGBTexture
        
//
//        self.mpsScaleFilter?.encode(commandBuffer: cmdBuffer, sourceTexture: self.lastArData!.colorRGBTexture.texture! ,
//                                    destinationTexture: self.downscaledRGBTexture)
//
//        cmdBuffer.commit()
//
//        self.lastArData!.downscaledRGBTexture.texture = self.downscaledRGBTexture
//
//        self.fileManager!.writeImage(metalTexture: self.lastArData!.downscaledRGBTexture.texture,
//                                     imageIdx: self.fileCounter,
//                                     imageIdentifier: "downscaledImage")
//
//
//        let depthPath = self.fileManager!.writeImage(metalTexture: self.lastArData!.depthRGBATexture.texture,
//                                     imageIdx: self.fileCounter,
//                                     imageIdentifier: "depth")
//
//        let confPathBin = self.fileManager!.writeConfidence(pixelBuffer: self.lastArData!.confidenceImage!, imageIdx: self.fileCounter)
//
//        let depthPathBin = self.fileManager!.writeDepth(pixelBuffer: self.lastArData!.depthImage!, imageIdx: self.fileCounter)
//
        let rgbPath = self.fileManager!.writeImage(metalTexture: colorRGBATexture.texture,
                                     imageIdx: self.fileCounter,
                                     imageIdentifier: "image")
//
//        let confPath = self.fileManager!.writeImage(metalTexture: self.lastArData!.confRGBATexture.texture,
//                                     imageIdx: self.fileCounter,
//                                     imageIdentifier: "confidence")
        
        
        let curCamPose = self.getCameraPose(currentFrame: currentFrame)

        let savedFrameData = SavedFrame(pose: curCamPose,
                                        rgbPath: rgbPath!,
                                        rgbResolution: [RGBTexture.height,
                                                        RGBTexture.width])
        print(self.scan!.scannedObject.boundingBox?.extent)
        print(self.scan!.scannedObject.boundingBox?.simdWorldPosition)
        print(self.scan!.scannedObject.boundingBox?.simdWorldOrientation)
        print(self.scan?.scannedObject.origin?.simdWorldPosition)
//
        self.savedFrames.append(savedFrameData)
//
//        self.lastArData?.cameraPoses.append(curCamPose)
//        self.lastArData?.sampleTimes.append(self.lastArData!.sampleTime!)
//        if projectDepthMap {
//            self.depthMapToPointcloud(filteringPhase: 1)
//        }
//
        self.fileCounter += 1
    }
    
//    func startTimer() {
//        self.timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true, block: { _ in
//            print("Timer...")
//            self.captureFrameData()
//
//        })
//    }
//    
//    func stopTimer() {
//        //arReceiver.scanState = scanState
//        print("stop timer....")
//        self.timer.invalidate()
//    }
    
    @objc
    func scanningStateChanged(_ notification: Notification) {
        guard self.state == .scanning, let scan = notification.object as? Scan, scan === self.scan else { return }
        guard let scanState = notification.userInfo?[Scan.stateUserInfoKey] as? Scan.State else { return }
        
        DispatchQueue.main.async {
            switch scanState {
            case .ready:
                print("Scanning state changed: ready")
                //self.stopTimer()
                print("State: Ready to scan")
                self.setNavigationBarTitle("Ready to scan")
                self.showBackButton(false)
                self.nextButton.setTitle("Next", for: [])
                self.loadModelButton.isHidden = true
                self.flashlightButton.isHidden = true
                if scan.ghostBoundingBoxExists {
                    self.displayInstruction(Message("Tap 'Next' to create an approximate bounding box around the object you want to scan."))
                    self.nextButton.isEnabled = true
                } else {
                    self.displayInstruction(Message("Point at a nearby object to scan."))
                    self.nextButton.isEnabled = false
                }
            case .defineBoundingBox:
                print("Scanning state changed: defineBoundingBox")
                //self.stopTimer()
                print("State: Define bounding box")
                self.displayInstruction(Message("Position and resize bounding box using gestures.\n" +
                    "Long press sides to push/pull them in or out. "))
                self.setNavigationBarTitle("Define bounding box")
                self.showBackButton(true)
                self.nextButton.isEnabled = scan.boundingBoxExists
                self.loadModelButton.isHidden = true
                self.flashlightButton.isHidden = true
                self.nextButton.setTitle("Scan", for: [])
            case .scanning:
                print("Scanning state changed: Scanning")
                print("start scanning timer.")
                self.scheduledTimerWithTimeInterval()
                self.videoCapture.start()
                //self.startTimer()
                //self.capture = ARCapture(view: self.sceneView)
                //self.capture?.start(captureType: .imageCapture)
                self.displayInstruction(Message("Scan the object from all sides that you are " +
                    "interested in. Do not move the object while scanning!"))
                if let boundingBox = scan.scannedObject.boundingBox {
                    self.setNavigationBarTitle("Scan (\(boundingBox.progressPercentage)%)")
                } else {
                    self.setNavigationBarTitle("Scan 0%")

                }
                                
                self.showBackButton(true)
                self.nextButton.isEnabled = true
                self.loadModelButton.isHidden = true
                self.flashlightButton.isHidden = true
                self.nextButton.setTitle("Finish", for: [])
                // Disable plane detection (even if no plane has been found yet at this time) for performance reasons.
                self.sceneView.stopPlaneDetection()
            case .adjustingOrigin:
                print("Scanning state changed: adjustingOrigin")
                self.stopTimer()
                self.videoCapture.stop()
                //self.capture?.stop({ (status) in
                //    print("Video exported: \(status)")
                //})
                //self.stopTimer()
                print("State: Adjusting Origin")
                self.displayInstruction(Message("Adjust origin using gestures.\n" +
                                                "Save data after adjusting origin."))
                    //"You can load a *.usdz 3D model overlay."))
                self.setNavigationBarTitle("Adjust origin")
                self.showBackButton(true)
                self.nextButton.isEnabled = true
                self.loadModelButton.isHidden = false
                self.loadModelButton.setTitle("Save", for: [])
                self.flashlightButton.isHidden = true
                self.nextButton.setTitle("Test", for: [])
            }
        }
    }
    
    func switchToPreviousState() {
        switch state {
        case .startARSession:
            break
        case .notReady:
            state = .startARSession
        case .scanning:
            if let scan = scan {
                switch scan.state {
                case .ready:
                    restartButtonTapped(self)
                case .defineBoundingBox:
                    scan.state = .ready
                case .scanning:
                    scan.state = .defineBoundingBox
                case .adjustingOrigin:
                    scan.state = .scanning
                }
            }
        case .testing:
            state = .scanning
            scan?.state = .adjustingOrigin
        }
    }
    
    func switchToNextState() {
        switch state {
        case .startARSession:
            state = .notReady
        case .notReady:
            state = .scanning
        case .scanning:
            if let scan = scan {
                switch scan.state {
                case .ready:
                    scan.state = .defineBoundingBox
                case .defineBoundingBox:
                    scan.state = .scanning
                case .scanning:
                    scan.state = .adjustingOrigin
                case .adjustingOrigin:
                    state = .testing
                }
            }
        case .testing:
            // Testing is the last state, show the share sheet at the end.
            createAndShareReferenceObject()
        }
    }
    
    @objc
    func ghostBoundingBoxWasCreated(_ notification: Notification) {
        if let scan = scan, scan.state == .ready {
            DispatchQueue.main.async {
                self.nextButton.isEnabled = true
                self.displayInstruction(Message("Tap 'Next' to create an approximate bounding box around the object you want to scan."))
            }
        }
    }
    
    @objc
    func ghostBoundingBoxWasRemoved(_ notification: Notification) {
        if let scan = scan, scan.state == .ready {
            DispatchQueue.main.async {
                self.nextButton.isEnabled = false
                self.displayInstruction(Message("Point at a nearby object to scan."))
            }
        }
    }
    
    @objc
    func boundingBoxWasCreated(_ notification: Notification) {
        if let scan = scan, scan.state == .defineBoundingBox {
            DispatchQueue.main.async {
                self.nextButton.isEnabled = true
            }
        }
    }
}

@available(iOS 13.0, *)
extension UIApplication {
    
    var keyWindow: UIWindow? {
        // Get connected scenes
        return UIApplication.shared.connectedScenes
            // Keep only active scenes, onscreen and visible to the user
            .filter { $0.activationState == .foregroundActive }
            // Keep only the first `UIWindowScene`
            .first(where: { $0 is UIWindowScene })
            // Get its associated windows
            .flatMap({ $0 as? UIWindowScene })?.windows
            // Finally, keep only the key window
            .first(where: \.isKeyWindow)
    }
    
}
