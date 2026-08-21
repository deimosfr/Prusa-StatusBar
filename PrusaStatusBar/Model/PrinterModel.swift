import Foundation

/// Printer illustrations bundled from Prusa Connect. The raw value is kept
/// stable because it is stored in `UserDefaults`.
public enum PrinterModel: String, CaseIterable, Sendable, Hashable {
    case coreOne
    case coreOneL
    case coreOneLINDX
    case coreOneLMMU3
    case coreOneMMU3
    case coreOneOak
    case coreOnePlusINDX
    case mini
    case mk25
    case mk25S
    case mk3
    case mk3MMU2
    case mk3S
    case mk3SMMU3
    case mk35
    case mk35MMU3
    case mk35S
    case mk35SMMU3
    case mk39
    case mk39MMU3
    case mk39S
    case mk39SMMU3
    case mk4
    case mk4MMU3
    case mk4S
    case mk4SMMU3
    case sl1
    case sl1S
    case slx
    case xl
    case xlEnclosure
    case xlMultiTool2
    case xlMultiTool3
    case xlMultiTool4
    case xlMultiTool5
    case xlMultiTool2Enclosure
    case xlMultiTool3Enclosure
    case xlMultiTool4Enclosure
    case xlMultiTool5Enclosure

    public var displayName: String {
        switch self {
        case .coreOne: "CORE One"
        case .coreOneL: "CORE One L"
        case .coreOneLINDX: "CORE One L INDX"
        case .coreOneLMMU3: "CORE One L MMU3"
        case .coreOneMMU3: "CORE One MMU3"
        case .coreOneOak: "CORE One OAK"
        case .coreOnePlusINDX: "CORE One+ INDX"
        case .mini: "MINI"
        case .mk25: "MK2.5"
        case .mk25S: "MK2.5S"
        case .mk3: "MK3"
        case .mk3MMU2: "MK3 + MMU2"
        case .mk3S: "MK3S"
        case .mk3SMMU3: "MK3S + MMU3"
        case .mk35: "MK3.5"
        case .mk35MMU3: "MK3.5 + MMU3"
        case .mk35S: "MK3.5S"
        case .mk35SMMU3: "MK3.5S + MMU3"
        case .mk39: "MK3.9"
        case .mk39MMU3: "MK3.9 + MMU3"
        case .mk39S: "MK3.9S"
        case .mk39SMMU3: "MK3.9S + MMU3"
        case .mk4: "MK4"
        case .mk4MMU3: "MK4 + MMU3"
        case .mk4S: "MK4S"
        case .mk4SMMU3: "MK4S + MMU3"
        case .sl1: "SL1"
        case .sl1S: "SL1S"
        case .slx: "SLX"
        case .xl: "XL"
        case .xlEnclosure: "XL Enclosure"
        case .xlMultiTool2: "XL 2-tool"
        case .xlMultiTool3: "XL 3-tool"
        case .xlMultiTool4: "XL 4-tool"
        case .xlMultiTool5: "XL 5-tool"
        case .xlMultiTool2Enclosure: "XL 2-tool Enclosure"
        case .xlMultiTool3Enclosure: "XL 3-tool Enclosure"
        case .xlMultiTool4Enclosure: "XL 4-tool Enclosure"
        case .xlMultiTool5Enclosure: "XL 5-tool Enclosure"
        }
    }

    public var assetName: String {
        "PrinterModel_\(rawValue)"
    }
}
