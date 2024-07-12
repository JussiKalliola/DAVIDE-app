//
//  structures.swift
//  DAVIDEApp
//
//  Created by Jussi Kalliola (TAU) on 9.1.2023.
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

struct SavedFrame {
    var pose: CameraPose!
    var rgbPath: String
    var rgbResolution: [Int]
}
