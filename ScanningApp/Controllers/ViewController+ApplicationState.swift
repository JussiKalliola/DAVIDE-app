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
        case saving
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
                        print("Camera tracking state is not normal.")
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
            case .saving:
                break
            }
            
            // 2. Apply changes as needed per state.
            internalState = newState
            
            switch newState {
            case .startARSession:
                print("State: Starting ARSession")
                if(self.videoCapture.ready) {
                    self.videoCapture.stop()
                }
                self.navBarBackground.isHidden = true
                self.navigationBar.isHidden=true
                self.setNavigationBarTitle("")
                instructionsVisible = false
                showBackButton(false)
                nextButton.isEnabled = true
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
                cancelMessageExpirationTimer()
            case .notReady:
                print("State: Not ready to scan")
                if(self.videoCapture.ready) {
                    self.videoCapture.stop()
                }
                self.setNavigationBarTitle("")
                self.navBarBackground.isHidden = false
                self.navigationBar.isHidden=false
                loadModelButton.isHidden = true
                flashlightButton.isHidden = true
                showBackButton(false)
                nextButton.isEnabled = false
                nextButton.setTitle("Start", for: [])
                displayInstruction(Message("Please wait for stable tracking"))
            case .scanning:
                if(!self.videoCapture.ready) {
                    self.videoCapture.start()
                }
                self.statsLabel.isHidden=false
                self.nextButton.setTitle("Stop", for: [])
                
                print("State: Scanning")
            case .saving:
                if(self.videoCapture.ready) {
                    self.videoCapture.stop()
                }
                
                self.navBarBackground.isHidden = false
                self.navigationBar.isHidden=false
                
                self.nextButton.isHidden = false
                nextButton.setTitle("Continue", for: [])
                loadModelButton.isHidden = false
                self.loadModelButton.setTitle("Save", for: [])
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
    
        
    func switchToPreviousState() {
        switch state {
        case .startARSession:
            break
        case .notReady:
            state = .startARSession
        case .scanning:
            print("scanning")
        case .saving:
            print("Saving: Restart session.")
            state = .startARSession
        }
    }
    
    func switchToNextState() {
        switch state {
        case .startARSession:
            state = .notReady
        case .notReady:
            state = .scanning
        case .scanning:
            state = .saving
            print("scanning")
        case .saving:
            state = .scanning
            print("saving")
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
