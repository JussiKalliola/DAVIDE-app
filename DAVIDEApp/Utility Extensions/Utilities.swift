/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extensions on system types used in this project.
*/

import Foundation
import ARKit

// Convenience accessors for Asset Catalog named colors.
extension UIColor {
    static let appYellow = UIColor(named: "appYellow")!
    static let appLightYellow = UIColor(named: "appLightYellow")!
    static let appBrown = UIColor(named: "appBrown")!
    static let appGreen = UIColor(named: "appGreen")!
    static let appBlue = UIColor(named: "appBlue")!
    static let appLightBlue = UIColor(named: "appLightBlue")!
    static let appGray = UIColor(named: "appGray")!
}

enum Axis {
    case x
    case y
    case z
    
    var normal: float3 {
        switch self {
        case .x:
            return float3(1, 0, 0)
        case .y:
            return float3(0, 1, 0)
        case .z:
            return float3(0, 0, 1)
        }
    }
}

extension simd_quatf {
    init(angle: Float, axis: Axis) {
        self.init(angle: angle, axis: axis.normal)
    }
}

extension float4x4 {
    var position: float3 {
        return columns.3.xyz
    }
}

extension float4 {
    var xyz: float3 {
        return float3(x, y, z)
    }

    init(_ xyz: float3, _ w: Float) {
        self.init(xyz.x, xyz.y, xyz.z, w)
    }
}
