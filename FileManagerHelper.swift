//
//  FileManagerHelper.swift
//  DigitalMicroAirport
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
    
    
    // Create new directory in the temporary directory where all the data from the session is captured.
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
        print(self.path)
    }
    
    func get_quaternion_from_euler(roll: Float, pitch: Float, yaw: Float) -> SIMD4<Float> {
        var quartenion: SIMD4<Float> = SIMD4<Float>(0.0, 0.0, 0.0, 0.0)
        quartenion.x = sin(roll/2) * cos(pitch/2) * cos(yaw/2) - cos(roll/2) * sin(pitch/2) * sin(yaw/2)
        quartenion.y = cos(roll/2) * sin(pitch/2) * cos(yaw/2) + sin(roll/2) * cos(pitch/2) * sin(yaw/2)
        quartenion.z = cos(roll/2) * cos(pitch/2) * sin(yaw/2) - sin(roll/2) * sin(pitch/2) * cos(yaw/2)
        quartenion.w = cos(roll/2) * cos(pitch/2) * cos(yaw/2) + sin(roll/2) * sin(pitch/2) * sin(yaw/2)
        
        return quartenion
    }
    
    func convert_rotation_matrix_to_quaternion(worldPose: float4x4) -> (SIMD4<Float>, SIMD3<Float>) {
        var qvec = SIMD4<Float>(0.0, 0.0, 0.0, 0.0)
        var tvec = SIMD3<Float>(0.0, 0.0, 0.0)
        var rotation = simd_float3x3(SIMD3<Float>(worldPose.columns.0.x, worldPose.columns.0.y, worldPose.columns.0.z),
                                     SIMD3<Float>(worldPose.columns.1.x, worldPose.columns.1.y, worldPose.columns.1.z),
                                     SIMD3<Float>(worldPose.columns.2.x, worldPose.columns.2.y, worldPose.columns.2.z))
        var translation = SIMD3<Float>(worldPose.columns.3.x, worldPose.columns.3.y, worldPose.columns.3.z)
        // simd_float3(1.0, 1.0, 1.0)
        var q = simd_quatf(rotation) // simd_quatf(ix: 1.0, iy: 0.0, iz: 1.0, r: 0.0)
        
        var normQ = q.normalized
        
        let (x,y,z,w) = (normQ.imag.x, normQ.imag.y, normQ.imag.z, normQ.real)
        
        let tx: Float = 2.0 * x
        let ty: Float = 2.0 * y
        let tz: Float = 2.0 * z
        let twx: Float = tx * w
        let twy: Float = ty * w
        let twz: Float = tz * w
        let txx: Float = tx * x
        let txy: Float = ty * x
        let txz: Float = tz * x
        let tyy: Float = ty * y
        let tyz: Float = tz * y
        let tzz: Float = tz * z
        let one: Float = 1.0
        
        let qM = float4x4(rows: [simd_float4((one - (tyy + tzz)), (txy-twz), (txz + twy), translation.x),
                                simd_float4((txy + twz), (one - (txx+tzz)), (tyz - twx), translation.y),
                                simd_float4((txz - twy), (tyz+twx), (one-(txx+tyy)), translation.z),
                                simd_float4(0.0, 0.0, 0.0, 1.0)])
        
        
        // Flip the y and z axes
        let flipYZ = matrix_float4x4(
            [1, 0, 0, 0],
            [0, -1, 0, 0],
            [0, 0, -1, 0],
            [0, 0, 0, 1])
        
        var flipR = simd_mul(qM, flipYZ)
        
        var R = simd_float3x3(SIMD3<Float>(flipR.columns.0.x, flipR.columns.0.y, flipR.columns.0.z),
                         SIMD3<Float>(flipR.columns.1.x, flipR.columns.1.y, flipR.columns.1.z),
                         SIMD3<Float>(flipR.columns.2.x, flipR.columns.2.y, flipR.columns.2.z))
        var t = SIMD3<Float>(flipR.columns.3.x, flipR.columns.3.y, flipR.columns.3.z)
        
        // Project from world to camera coordinate system
        var R_inv = R.inverse//R.inverse
        var negRinv = -R_inv
        
        for i in 0..<3 {
            print(negRinv[0][i], negRinv[1][i], negRinv[2][i])
            tvec[i] = negRinv[0][i] * t.x + negRinv[1][i] * t.y + negRinv[2][i] * t.z
        }
        
        
        // Convert 3x3 rotation matrix to 4D quaternion vector
        
        var (m00, m01, m02, m10, m11, m12, m20, m21, m22) = (Float(R_inv[0][0]), Float(R_inv[1][0]), Float(R_inv[2][0]), Float(R_inv[0][1]), Float(R_inv[1][1]), Float(R_inv[2][1]), Float(R_inv[0][2]), Float(R_inv[1][2]), Float(R_inv[2][2]))
        var trace = m00 + m11 + m22
        var eps = Float(1.0e-8)
        
        if trace > 0.0 {
            trace_pos_cond()
            
        } else {
            if (m00 > m11) && (m00 > m22) {
                cond1()
                
            } else {
                if m11 > m22 {
                    cond2()
                    
                } else {
                    cond3()
                    
                }
            }
        }
        
        func trace_pos_cond(){
            print("trace_pos_cond")
            var sq = sqrt(trace + 1.0 + eps) * 2.0
            var qw = 0.25 * sq
            var qx = (m21-m12)/sq
            var qy = (m02-m20)/sq
            var qz = (m10-m01)/sq
            qvec = SIMD4<Float>(qx, qy, qz, qw)
        }
        
        func cond1(){
            print("cond1")
            var sq = sqrt(1.0 + m00 - m11 - m22 + eps) * 2.0
            var qw = (m21-m12)/sq
            var qx = 0.25 * sq
            var qy = (m01+m10)/sq
            var qz = (m02+m20)/sq
            qvec = SIMD4<Float>(qx, qy, qz, qw)
        }
        
        func cond2(){
            print("cond2")
            var sq = sqrt(1.0 + m11 - m00 - m22 + eps) * 2.0
            var qw = (m02-m20)/sq
            var qx = (m01+m10)/sq
            var qy = 0.25 * sq
            var qz = (m12+m21)/sq
            qvec = SIMD4<Float>(qx, qy, qz, qw)
        }
        
        func cond3(){
            print("cond3")
            var sq = sqrt(1.0 + m22 - m00 - m11 + eps) * 2.0
            var qw = (m10-m01)/sq
            var qx = (m02+m20)/sq
            var qy = (m12+m21)/sq
            var qz = 0.25 * sq
            qvec = SIMD4<Float>(qx, qy, qz, qw)
        }

        print(q.axis.x, q.axis.y, q.axis.z, q.angle)
        print(qvec)
        
//        qvec.x = q.axis.x
//        qvec.y = q.axis.y
//        qvec.z = q.axis.z
//        qvec.w = q.angle
        
        return (qvec, tvec)
    }
    
    func writeBoxPose(box: BoxPose) {
        
        do {
            guard let fileUrl = NSURL(fileURLWithPath: self.path!.path + "/").appendingPathComponent("BoundingBox.txt") else { return }
            
            var txtString = "# px(position_x), py, pz, ex(extent_x), ey, ez, qw(quaternion_w), qx, qy, qz\n"
            
            let flatExtent = (0..<3).flatMap { x in box.extent[x] }
            let flatQuat = [box.worldOrientation.vector.w, box.worldOrientation.vector.x, box.worldOrientation.vector.y, box.worldOrientation.vector.z]
            let flatOrigin = (0..<3).flatMap { x in box.origin[x] }
            txtString += "\(flatOrigin[0]),\(flatOrigin[1]),\(flatOrigin[2]),\(flatExtent[0]),\(flatExtent[1]),\(flatExtent[2]),\(flatQuat[0]),\(flatQuat[1]),\(flatQuat[2]),\(flatQuat[3])"
            
            try txtString.write(to: fileUrl, atomically: true, encoding: .utf8)
        } catch {
            print("error creating file")
        }
        
    }
    
    func writeCameraPose(cameraPoses: [CameraPose], motionData: [CMDeviceMotion]) {
        
        guard let fileUrl = NSURL(fileURLWithPath: self.path!.path).appendingPathComponent("ARposes.txt") else { return }
        
        // Motion data
        //let timestamp = validData.timestamp
        //let attitude = validData.attitude xyz
        //let quaternion = validData.attitude.quaternion xyzw
        //let rotationRate = validData.rotationRate roll pitch yaw
        //let userAcceleration = validData.userAcceleration xyz
        //let gravity = validData.gravity xyz
        
//                    var header = """
//                    <BEGINHEADER>
//                    frameCount:\(String(describing: self.frameCount)),
    //                timestamp:\(String(describing: timestamp)),
//                    quaternionX:\(String(describing: quaternion.x)),quaternionY:\(String(describing: quaternion.y)),
//                    quaternionZ:\(String(describing: quaternion.z)),quaternionW:\(String(describing: quaternion.w)),
//                    rotationRateX:\(String(describing: rotationRate.x)),rotationRateY:\(String(describing: rotationRate.y)),
//                    rotationRateZ:\(String(describing: rotationRate.z)),
    //                roll:\(String(describing: attitude.roll)),
//                    pitch:\(String(describing: attitude.pitch)),yaw:\(String(describing: attitude.yaw)),
//                    userAccelerationX:\(String(describing: userAcceleration.x)),userAccelerationY:\(String(describing: userAcceleration.y)),
//                    userAccelerationZ:\(String(describing: userAcceleration.z)),
    //                gravityX:\(String(describing: gravity.x)),
//                    gravityY:\(String(describing: gravity.y)),gravityZ:\(String(describing: gravity.z))
//                    <ENDHEADER>
//                    """
        
        
        // Write header
        var csvString = "# timestamp, tx, ty, tz, qw, qx, qy, qz, attqw, attqx, attqy, attqz, attroll, attpitch, attyaw, rrx, rry, rrz, accx, accy, accz, gx, gy, gz\n"
        
        
        for i in 0...cameraPoses.count - 1 {
            
            let flatWorldQuat = [cameraPoses[i].worldQuaternion.vector.w, cameraPoses[i].worldQuaternion.vector.x, cameraPoses[i].worldQuaternion.vector.y, cameraPoses[i].worldQuaternion.vector.z]
            let worldPose = (0..<4).flatMap { x in (0..<4).map { y in cameraPoses[i].worldPose[x][y] } }
            let t = cameraPoses[i].worldPose.columns.3
            
            let att = motionData[i].attitude
            
            let mQ = [motionData[i].attitude.quaternion.w, motionData[i].attitude.quaternion.x, motionData[i].attitude.quaternion.y, motionData[i].attitude.quaternion.z]
            let rR = motionData[i].rotationRate
            let uAcc = motionData[i].userAcceleration
            let gr = motionData[i].gravity
            
            csvString += "\(cameraPoses[i].timeStamp.value),\(t[0]),\(t[1]),\(t[2]),\(flatWorldQuat[0]),\(flatWorldQuat[1]),\(flatWorldQuat[2]),\(flatWorldQuat[3]),\(mQ[0]),\(mQ[1]),\(mQ[2]),\(mQ[3]),\(att.roll),\(att.pitch),\(att.yaw),\(rR.x),\(rR.y),\(rR.z),\(uAcc.x),\(uAcc.y),\(uAcc.z),\(gr.x),\(gr.y),\(gr.z)\n"
            
        }
        
        do {
            try csvString.write(to: fileUrl, atomically: true, encoding: .utf8)
        } catch {
            print("error writing file")
        }
    }
    
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
    
    
    func moveFileToFolder(sourcePath: String, targetPath: String) {
        do {
             try fileManager.moveItem(atPath: sourcePath, toPath: targetPath)
            
         } catch {
             print(error.localizedDescription)
         }
    }
    
    
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
    
    
    // Write depth data into temporary file storage
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
    
    
    // Write RGB image to temporary directory.
    func writeImage(metalTexture: MTLTexture?, imageIdx: Int, imageIdentifier: String) -> String? {
        
        guard let texture = metalTexture else { return nil }
        //MTLTexture.get
        //let bytes = metalTexture.getBytes(T##pixelBytes: UnsafeMutableRawPointer##UnsafeMutableRawPointer, bytesPerRow: <#T##Int#>, from: <#T##MTLRegion#>, mipmapLevel: <#T##Int#>)
        
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
    
    
    // Write YUV image to temporary directory.
    func writeImageYUV(pixelBuffer: CVPixelBuffer, imageIdx: Int) {
        // Image is 2 Plane YUV, shape HxW, H/2 x W/2

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == noErr else { return }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let srcPtrP0 = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
          return
        }
        guard let srcPtrP1 = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
          return
        }

        let rowBytesP0 : Int = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let rowBytesP1 : Int = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let widthP0 = Int(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        let widthP1 = Int(CVPixelBufferGetWidthOfPlane(pixelBuffer, 1))
        let heightP0 = Int(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))
        let heightP1 = Int(CVPixelBufferGetHeightOfPlane(pixelBuffer, 1))

        let uint8PointerP0 = srcPtrP0.bindMemory(to: UInt8.self, capacity: heightP0 * rowBytesP0)
        let uint8PointerP1 = srcPtrP1.bindMemory(to: UInt8.self, capacity: heightP1 * rowBytesP1)

        let s = "image_P0_\(widthP0)x\(heightP0)_P1_\(widthP1)x\(heightP1)_\(imageIdx)"
        let fileURL = URL(fileURLWithPath: s, relativeTo: self.path).appendingPathExtension("bin")

        let stream = OutputStream(url: fileURL, append: false)
        stream?.open()

        for y in 0 ..< heightP0{
            stream?.write(uint8PointerP0 + (y * rowBytesP0), maxLength: Int(rowBytesP0))
        }

        for y in 0 ..< heightP1{
            stream?.write(uint8PointerP1 + (y * rowBytesP1), maxLength: Int(rowBytesP1))
        }

        stream?.close()
        
        print("YUV image saved.")
    }
    
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
    
    func convertBinToJpeg(sourceFilePath: String, targetFilePath: String, width: Int, height: Int, orientation: UIDeviceOrientation) {
        
        print(sourceFilePath, targetFilePath, width, height, orientation)
        
        do {
            let sourceFilePathURL = URL(fileURLWithPath: sourceFilePath)
            let targetFilePathURL = URL(fileURLWithPath: targetFilePath)
            print(sourceFilePath, targetFilePath)
            
            let rawData: Data = try Data(contentsOf: sourceFilePathURL)
            let byteArray = [UInt8](rawData)
            
            //let intRawData = [UInt8](rawData)
            let image = mask(from: byteArray, width: width, height: height)
            var rotationDeg: CGFloat = 0
            
            //UIDeviceOrientation
            
            if orientation == .portrait {
                rotationDeg = 90
            }
            
            guard let data = image?.imageRotated(on: rotationDeg).jpegData(compressionQuality: 1.0) else { return }
            
            try? data.write(to: targetFilePathURL)
            
            //moveFileToFolder(sourcePath: sourceFilePath, targetPath: targetFilePath)
            
            try? fileManager.removeItem(at: URL(fileURLWithPath: sourceFilePath))
            
        } catch {
            fatalError("Couldnt read the file.")
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
