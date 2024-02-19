//
//  VideoCapture.swift
//  ScanningApp
//
//  Created by Jussi Kalliola (TAU) on 30.1.2023.
//  Copyright © 2023 Apple. All rights reserved.
//

import Foundation
import ARKit
import Photos

class VideoCapture {
    
    var assetWriterSettings: [String : Any]!
    var assetWriterInput: AVAssetWriterInput!
    var assetWriterAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    var assetwriter: AVAssetWriter!
    var outputVideoPath: URL!
    
    var fps: Int32 = 60
    
    var frameCount: Int64 = 0
    var frameTime: CMTime = CMTime.zero
    
    var ready: Bool = false
    
    
    public init?(codec: AVVideoCodecType, width: Int, height: Int, path: URL, fps: Int32) {
        
        let fileURL = URL(fileURLWithPath: "vid", relativeTo: path).appendingPathExtension("mov")
        
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            
        }
        
        guard let assetwriter = try? AVAssetWriter(outputURL: fileURL, fileType: .mov) else {
            return
        }
        
        self.fps = fps
        self.outputVideoPath = fileURL
        
        self.assetwriter=assetwriter
        
        self.assetWriterSettings = [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height] as [String : Any]
        self.assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: self.assetWriterSettings)
        self.assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.assetWriterInput)
        
        self.assetwriter.add(assetWriterInput)
        
        if self.assetwriter.startWriting() {
            print("starting writing")
        } else {
            print("something went wrong when starting writing")
        }
    }
    
    public func start() {
        self.assetwriter.startSession(atSourceTime: CMTime.zero)
        self.ready=true
    }
    
    public func stop() {
        self.ready=false
    }
    
    public func finish() {
        self.ready=false
        self.assetWriterInput.markAsFinished()
        self.assetwriter.finishWriting {
            print("Finished video location: \(self.outputVideoPath.path)")
        }
        
    }
    
    public func appendToVideo(pixelBuffer: CVPixelBuffer, frameCount: Int64) {
        if self.assetWriterInput.isReadyForMoreMediaData {
            let frameTime = CMTimeMake(value: frameCount, timescale: self.fps)
            
            assetWriterAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
            self.frameCount = frameCount
            self.frameTime = frameTime
            print("appended pixelbuffer at frame \(frameCount) at time \(frameTime)")
        } else {
            print("assetWriterInput is not ready for more media data now...")
        }
    }
    
    
    
    
}
