//
//  structures.swift
//  ScanningApp
//
//  Created by Jussi Kalliola (TAU) on 9.1.2023.
//  Copyright © 2023 Apple. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import ARKit
import ModelIO
import MetalKit


struct CameraPose {
    var timeStamp: CMTime!
    var worldPose = simd_float4x4()
    var worldQuaternion = simd_quatf()
    var intrinsics  = simd_float3x3()
}

struct BoxPose {
    var extent = simd_float3()
    var worldPosition = simd_float3()
    var worldOrientation = simd_quatf()
    var origin = simd_float3()
}


struct SavedFrame {
    var pose: CameraPose!
    var rgbPath: String
    var rgbResolution: [Int]
//    var depthPath: String
//    var depthPathBin: String
//    var depthResolution: [Int]
//    var confPath: String
//    var confPathBin: String
//    var confResolution: [Int]
//    var pointCloud: [PointCloud]?
//    var orientation: UIDeviceOrientation!
}
