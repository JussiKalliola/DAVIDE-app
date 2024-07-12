//
//  ARAssetCreator.swift
//  DAVIDEApp
//
//  Created by Volkov Alexander on 6/6/21.
//  Modified by Jussi Kalliola (TAU) on 9.1.2023.
//

import Foundation
import AVFoundation

// Assert creator
@available(iOS 13.0, *)
class ARAssetCreator: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// the last occured error
    var lastError: Error?
    
    ///
    private var assetWriter: AVAssetWriter!
    private var videoInput: AVAssetWriterInput!
    private var session: AVCaptureSession!
    
    private var buffer: AVAssetWriterInputPixelBufferAdaptor!
    private var startTime: CMTime?
    
    init(outputURL: URL, size: CGSize, captureType: ARFrameGenerator.CaptureType, optimizeForNetworkUs: Bool, audioEnabled: Bool, queue: DispatchQueue, mixWithOthers: Bool) throws {
        super.init()
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4)
        
        var effectiveSize = size
        if size.height < size.width && captureType == .renderWithDeviceRotation {
            effectiveSize = CGSize(width: size.height, height: size.width)
        }
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264 as AnyObject,
            AVVideoWidthKey: Int(effectiveSize.width) as AnyObject,
            AVVideoHeightKey: Int(effectiveSize.height) as AnyObject
        ])
        videoInput.expectsMediaDataInRealTime = true
        buffer = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        
        // Apply transformation
        var transform: CGAffineTransform = .identity
        videoInput.transform = transform
        
        if assetWriter.canAdd(videoInput) {
            assetWriter.add(videoInput)
        } else if let error = assetWriter.error {
            throw error
        }
        assetWriter.shouldOptimizeForNetworkUse = optimizeForNetworkUs
    }
    
    /// Append buffer
    /// - Parameters:
    ///   - buffer: the buffer
    ///   - time: the effective time
    func append(buffer: CVImageBuffer, with time: CMTime) {
        if assetWriter.status == .unknown {
            guard startTime == nil else { return }
            startTime = time
            if assetWriter.startWriting() {
                assetWriter.startSession(atSourceTime: time)
            } else {
                lastError = assetWriter.error
                print("ERROR: \(String(describing: assetWriter.error))")
            }
        } else if assetWriter.status == .failed {
            lastError = assetWriter.error
            print("ERROR: \(String(describing: assetWriter.error))")
            return
        }
        
        if videoInput.isReadyForMoreMediaData {
            self.buffer.append(buffer, withPresentationTime: time)
        }
    }    
    
    /// Pause audio recording
    func pause() {

    }
    
    /// Stop writing video
    /// - Parameter completed: the completion callback
    func stop(completed: @escaping () -> ()) {
        if let session = session, session.isRunning {
            session.stopRunning()
        }

        if assetWriter.status == .writing {
            assetWriter.finishWriting(completionHandler: completed)
        }
    }
    
    
    /// Cancel writing video
    func cancel() {
        if let session = session, session.isRunning {
            session.stopRunning()
        }
        assetWriter.cancelWriting()
    }
}

