//
//  FileManagerHelper.swift
//  DAVIDEApp
//
//  Created by Jussi Kalliola (TAU) on 4.10.2022.
//

import Foundation
import ARKit
import Metal
import SwiftUI
import MetalKit
import VideoToolbox
import SceneKit.ModelIO
import CoreMotion

class FileManagerHelper {
    var path: URL?
    var fileCounter: Int = 0
    let fileManager: FileManager = FileManager.default
    var suffix: String = ""
    
    init(suffix: String = "test") {
        self.suffix=suffix
        createDirectory()
    }
    
    
    /// Write camera and IMU related data to text file
    func writeCameraPose(cameraPoses: [CameraPose], motionData: [CMDeviceMotion]) {
        
        guard let fileUrl = NSURL(fileURLWithPath: self.path!.path).appendingPathComponent("ARposes.txt") else { return }
        
        // Write header
        var csvString = "# timestamp, tx, ty, tz, qw, qx, qy, qz, attqw, attqx, attqy, attqz, attroll, attpitch, attyaw, rrx, rry, rrz, accx, accy, accz, gx, gy, gz\n"
        
        
        for i in 0...cameraPoses.count - 1 {
            
            let wQ = [cameraPoses[i].worldQuaternion.vector.w, cameraPoses[i].worldQuaternion.vector.x, cameraPoses[i].worldQuaternion.vector.y, cameraPoses[i].worldQuaternion.vector.z]
            let worldPose = (0..<4).flatMap { x in (0..<4).map { y in cameraPoses[i].worldPose[x][y] } }
            let t = cameraPoses[i].worldPose.columns.3
            
            let att = motionData[i].attitude
            
            let mQ = [motionData[i].attitude.quaternion.w, motionData[i].attitude.quaternion.x, motionData[i].attitude.quaternion.y, motionData[i].attitude.quaternion.z]
            let rR = motionData[i].rotationRate
            let uAcc = motionData[i].userAcceleration
            let gr = motionData[i].gravity
            
            csvString += "\(cameraPoses[i].timeStamp.value),\(t[0]),\(t[1]),\(t[2]),\(wQ[0]),\(wQ[1]),\(wQ[2]),\(wQ[3]),\(mQ[0]),\(mQ[1]),\(mQ[2]),\(mQ[3]),\(att.roll),\(att.pitch),\(att.yaw),\(rR.x),\(rR.y),\(rR.z),\(uAcc.x),\(uAcc.y),\(uAcc.z),\(gr.x),\(gr.y),\(gr.z)\n"
            
        }
        
        do {
            try csvString.write(to: fileUrl, atomically: true, encoding: .utf8)
        } catch {
            print("error writing file")
        }
    }
    
    /// Write camera intrinsics to txt file
    func writeFrameInfo(cameraPoses: [CameraPose]) {
        
        guard let fileUrl = NSURL(fileURLWithPath: self.path!.path).appendingPathComponent("Frames.txt") else { return }
        
        // Write header
        var csvString = "# timestamp, frame_index, fx, fy, cx, cy\n"
        
        
        for i in 0...cameraPoses.count - 1 {
            
            let fx = cameraPoses[i].intrinsics.columns.0[0]
            let fy = cameraPoses[i].intrinsics.columns.1[1]
            let cx = cameraPoses[i].intrinsics.columns.2[0]
            let cy = cameraPoses[i].intrinsics.columns.2[1]
            
            csvString += "\(cameraPoses[i].timeStamp.value),\(cameraPoses[i].timeStamp.value),\(fx),\(fy),\(cx),\(cy)\n"
            
        }
        
        do {
            try csvString.write(to: fileUrl, atomically: true, encoding: .utf8)
        } catch {
            print("error writing file")
        }
    }

    
    /// Write confidence data into temporary file storage
    func writeConfidence(pixelBuffer: CVPixelBuffer, imageIdx: Int) -> String? {
        // Depth map is 32 bit float
        
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == noErr else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let srcPtr = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("Failed to retrieve depth pointer.")
            return nil
        }
    
        let rowBytes : Int = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = Int(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int(CVPixelBufferGetHeight(pixelBuffer))
        let capacity = CVPixelBufferGetDataSize(pixelBuffer)
        let uint8Pointer = srcPtr.bindMemory(to: UInt8.self, capacity: capacity)
        
        let s =  "c_\(width)x\(height)_\(String(format: "%05d", imageIdx))"
        let fileURL = URL(fileURLWithPath: s, relativeTo: URL(fileURLWithPath: self.path!.path + "/confidence/")).appendingPathExtension("bin")
        
        guard let stream = OutputStream(url: fileURL, append: false) else {
            print("Failed to open depth stream.")
            return nil
        }
        stream.open()
        
        for y in 0 ..< height{
            stream.write(uint8Pointer + (y * rowBytes), maxLength: Int(rowBytes))
        }
        
        stream.close()
        
        return s  + ".bin"
    }
    
    
    /// Write depth data into temporary file storage
    public func writeDepth(pixelBuffer: CVPixelBuffer, imageIdx: Int) -> String? {
        
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == noErr else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        
        guard let srcPtr = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("Failed to retrieve depth pointer.")
            return nil
        }

        let rowBytes : Int = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = Int(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int(CVPixelBufferGetHeight(pixelBuffer))
        let capacity = CVPixelBufferGetDataSize(pixelBuffer)
        let uint8Pointer = srcPtr.bindMemory(to: UInt8.self, capacity: capacity)


        let s =  "d_\(width)x\(height)_\(String(format: "%05d", imageIdx))"
        
        let fileURL = URL(fileURLWithPath: s, relativeTo: URL(fileURLWithPath: self.path!.path + "/depth/")).appendingPathExtension("bin")
        
        print("Fileurl: ", fileURL.path)

        guard let stream = OutputStream(url: fileURL, append: false) else {
            print("Failed to open depth stream.")
            return nil
        }
        stream.open()

        for y in 0 ..< height{
            stream.write(uint8Pointer + (y * rowBytes), maxLength: Int(rowBytes))
        }

        stream.close()
        print("Depth image saved.")
        
        return s  + ".bin"
        
    }
    
    
    /// Write RGB image to temporary directory.
    func writeImage(metalTexture: MTLTexture?, imageIdx: Int, imageIdentifier: String) -> String? {
        
        guard let texture = metalTexture else { return nil }
        
        let width = texture.width
        let height = texture.height
        
        let bytesPerPixel = 4

        // The total number of bytes of the texture
        let imageByteCount = width * height * bytesPerPixel

        // The number of bytes for each image row
        let bytesPerRow = width * bytesPerPixel

        // An empty buffer that will contain the image
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))

        // Gets the bytes from the texture
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        
        
        let data = Data(bytes: src, count: imageByteCount)
        var s: String = ""
        
        if imageIdentifier == "depth" {
            s =  "depth_\(texture.width)x\(texture.height)_\(String(format: "%05d", imageIdx))"
        } else if imageIdentifier == "confidence" {
            s = "conf_\(texture.width)x\(texture.height)_\(String(format: "%05d", imageIdx))"
        } else if imageIdentifier == "image" {
            s = "rgb_\(texture.width)x\(texture.height)_\(String(format: "%05d", imageIdx))"
        } else if imageIdentifier == "downscaledImage" {
            s = "downscaled_rgb_\(texture.width)x\(texture.height)_\(String(format: "%05d", imageIdx))"
        }
        
        let fileURL = URL(fileURLWithPath: s, relativeTo: self.path).appendingPathExtension("bin")
        
        
        try? data.write(to: fileURL)
        
        print("\(imageIdentifier) image saved.")
        
        return s + ".bin"
    }
    
    /// convert byte array to UIIMage
    func mask(from data: [UInt8], width: Int, height: Int) -> UIImage? {
        guard data.count >= 8 else {
            print("data too small")
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB() //Gray()

        let bpc = 8
        let bpr = width * 4
        let colorSpace3: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bmpinfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        var context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: bpc,
                                bytesPerRow: bpr,
                                space: colorSpace3,
                                bitmapInfo: bmpinfo.rawValue)
        var buffer = context!.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        
        for index in 0 ..< width * height * 4 {
            buffer[index] = data[index]
        }

        return context!.makeImage().flatMap { UIImage(cgImage: $0) }
    }
    
    /// Convert binary file to jpeg
    func convertBinToJpeg(sourceFilePath: String, targetFilePath: String, width: Int, height: Int, orientation: UIDeviceOrientation) {
        
        print(sourceFilePath, targetFilePath, width, height, orientation)
        
        do {
            let sourceFilePathURL = URL(fileURLWithPath: sourceFilePath)
            let targetFilePathURL = URL(fileURLWithPath: targetFilePath)
            print(sourceFilePath, targetFilePath)
            
            let rawData: Data = try Data(contentsOf: sourceFilePathURL)
            let byteArray = [UInt8](rawData)
            
            let image = mask(from: byteArray, width: width, height: height)
            var rotationDeg: CGFloat = 0
            
            if orientation == .portrait {
                rotationDeg = 90
            }
            
            guard let data = image?.imageRotated(on: rotationDeg).jpegData(compressionQuality: 1.0) else { return }
            
            try? data.write(to: targetFilePathURL)
            try? fileManager.removeItem(at: URL(fileURLWithPath: sourceFilePath))
            
        } catch {
            fatalError("Couldnt read the file.")
        }
    }
    
    /// Create new directory in the temporary directory where all the data from the session is captured.
    public func createDirectory() {
        let currDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let currDateString = dateFormatter.string(from : currDate)
        
        let TemporaryDirectory = URL(string: NSTemporaryDirectory())!
        let DirPath = TemporaryDirectory.appendingPathComponent("bundle-" + currDateString + "_" + self.suffix + "/")
        
        do {
            try fileManager.createDirectory(atPath: DirPath.path, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(atPath: DirPath.path + "/depth/", withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(atPath: DirPath.path + "/confidence/", withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            print("Unable to create directory \(error.debugDescription)")
        }
        
        self.path = URL(fileURLWithPath: DirPath.path)
    }
    
    func moveFileToFolder(sourcePath: String, targetPath: String) {
        do {
             try fileManager.moveItem(atPath: sourcePath, toPath: targetPath)
            
         } catch {
             print(error.localizedDescription)
         }
    }
    
    public func removeFile(targetFile: URL) {
        
    }
    
    // Clear the temporary folder if images are saved somewhere else.
    public func clearTempFolder() -> Void {
        print(self.path!.relativeString)
        print(self.path!.absoluteString)
        do {
            let folderPaths = try self.fileManager.contentsOfDirectory(atPath: NSTemporaryDirectory())
            

            for folderPath in folderPaths {
                
                let combinedFolderPath = NSTemporaryDirectory() + folderPath
                
                let filePaths = try self.fileManager.contentsOfDirectory(atPath: NSTemporaryDirectory() + folderPath)
                
                for filePath in filePaths {
                    try fileManager.removeItem(at: URL(fileURLWithPath: NSTemporaryDirectory() + folderPath + "/" + filePath))
                }
            }
            
            
        } catch {
            print("Could not clear temp folder: \(error)\n\n")
            
        }
        
        // Create a new folder into temporary directory for new data.
        self.createDirectory()
    }
    
}


extension UIImage {

  func imageRotated(on degrees: CGFloat) -> UIImage {
    // Following code can only rotate images on 90, 180, 270.. degrees.
    let degrees = round(degrees / 90) * 90
    let sameOrientationType = Int(degrees) % 180 == 0
    let radians = CGFloat.pi * degrees / CGFloat(180)
    let newSize = sameOrientationType ? size : CGSize(width: size.height, height: size.width)

    UIGraphicsBeginImageContext(newSize)
    defer {
      UIGraphicsEndImageContext()
    }

    guard let ctx = UIGraphicsGetCurrentContext(), let cgImage = cgImage else {
      return self
    }

    ctx.translateBy(x: newSize.width / 2, y: newSize.height / 2)
    ctx.rotate(by: radians)
    ctx.scaleBy(x: 1, y: -1)
    let origin = CGPoint(x: -(size.width / 2), y: -(size.height / 2))
    let rect = CGRect(origin: origin, size: size)
    ctx.draw(cgImage, in: rect)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    return image ?? self
  }

}
