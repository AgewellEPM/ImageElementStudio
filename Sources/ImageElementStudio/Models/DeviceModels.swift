import SwiftUI

// MARK: - DeviceFamily

/// Represents the broad device family: iPhone or iPad.
enum DeviceFamily: String, Codable, CaseIterable, Hashable, Identifiable {
    case iPhone
    case iPad

    var id: String { rawValue }

    var displayName: String { rawValue }

    var symbolName: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        }
    }
}

// MARK: - DeviceOrientation

/// Physical orientation of the device.
enum DeviceOrientation: String, Codable, CaseIterable, Hashable, Identifiable {
    case portrait
    case landscape

    var id: String { rawValue }
}

// MARK: - DeviceSpec

/// Specification for a single device model.
/// All dimensions are in logical points assuming portrait orientation.
struct DeviceSpec: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var family: DeviceFamily
    var screenWidth: CGFloat
    var screenHeight: CGFloat
    var cornerRadius: CGFloat
    var statusBarHeight: CGFloat
    var homeIndicatorHeight: CGFloat
    var bezelWidth: CGFloat
    var hasDynamicIsland: Bool
    var hasNotch: Bool
    var hasHomeButton: Bool
    var simulatorName: String

    /// Effective screen size accounting for orientation.
    func screenSize(for orientation: DeviceOrientation) -> CGSize {
        switch orientation {
        case .portrait:
            return CGSize(width: screenWidth, height: screenHeight)
        case .landscape:
            return CGSize(width: screenHeight, height: screenWidth)
        }
    }

    /// Safe area insets for the given orientation.
    func safeAreaInsets(for orientation: DeviceOrientation) -> NSEdgeInsets {
        switch orientation {
        case .portrait:
            return NSEdgeInsets(
                top: statusBarHeight,
                left: 0,
                bottom: homeIndicatorHeight,
                right: 0
            )
        case .landscape:
            let sideInset: CGFloat = hasDynamicIsland || hasNotch ? 59 : 0
            return NSEdgeInsets(
                top: 0,
                left: sideInset,
                bottom: 21,
                right: sideInset
            )
        }
    }
}

// MARK: - Device Catalog

extension DeviceSpec {

    /// Built-in catalog of common Apple devices.
    static let catalog: [DeviceSpec] = [
        // iPhones
        DeviceSpec(
            id: "iphone16",
            name: "iPhone 16",
            family: .iPhone,
            screenWidth: 393,
            screenHeight: 852,
            cornerRadius: 55,
            statusBarHeight: 59,
            homeIndicatorHeight: 34,
            bezelWidth: 12,
            hasDynamicIsland: true,
            hasNotch: false,
            hasHomeButton: false,
            simulatorName: "iPhone 16"
        ),
        DeviceSpec(
            id: "iphone16pro",
            name: "iPhone 16 Pro",
            family: .iPhone,
            screenWidth: 402,
            screenHeight: 874,
            cornerRadius: 55,
            statusBarHeight: 59,
            homeIndicatorHeight: 34,
            bezelWidth: 12,
            hasDynamicIsland: true,
            hasNotch: false,
            hasHomeButton: false,
            simulatorName: "iPhone 16 Pro"
        ),
        DeviceSpec(
            id: "iphone16promax",
            name: "iPhone 16 Pro Max",
            family: .iPhone,
            screenWidth: 430,
            screenHeight: 932,
            cornerRadius: 55,
            statusBarHeight: 59,
            homeIndicatorHeight: 34,
            bezelWidth: 12,
            hasDynamicIsland: true,
            hasNotch: false,
            hasHomeButton: false,
            simulatorName: "iPhone 16 Pro Max"
        ),
        DeviceSpec(
            id: "iphonese",
            name: "iPhone SE",
            family: .iPhone,
            screenWidth: 375,
            screenHeight: 667,
            cornerRadius: 0,
            statusBarHeight: 20,
            homeIndicatorHeight: 0,
            bezelWidth: 16,
            hasDynamicIsland: false,
            hasNotch: false,
            hasHomeButton: true,
            simulatorName: "iPhone SE (3rd generation)"
        ),
        // iPads
        DeviceSpec(
            id: "ipadpro11",
            name: "iPad Pro 11\"",
            family: .iPad,
            screenWidth: 834,
            screenHeight: 1194,
            cornerRadius: 18,
            statusBarHeight: 24,
            homeIndicatorHeight: 20,
            bezelWidth: 18,
            hasDynamicIsland: false,
            hasNotch: false,
            hasHomeButton: false,
            simulatorName: "iPad Pro 11-inch (M4)"
        ),
        DeviceSpec(
            id: "ipadpro13",
            name: "iPad Pro 13\"",
            family: .iPad,
            screenWidth: 1024,
            screenHeight: 1366,
            cornerRadius: 18,
            statusBarHeight: 24,
            homeIndicatorHeight: 20,
            bezelWidth: 18,
            hasDynamicIsland: false,
            hasNotch: false,
            hasHomeButton: false,
            simulatorName: "iPad Pro 13-inch (M4)"
        ),
        DeviceSpec(
            id: "ipadair",
            name: "iPad Air",
            family: .iPad,
            screenWidth: 820,
            screenHeight: 1180,
            cornerRadius: 18,
            statusBarHeight: 24,
            homeIndicatorHeight: 20,
            bezelWidth: 18,
            hasDynamicIsland: false,
            hasNotch: false,
            hasHomeButton: false,
            simulatorName: "iPad Air (M2)"
        ),
    ]

    /// Default device identifier used when no selection has been made.
    static let defaultDeviceID = "iphone16"

    /// Look up a device by its identifier.
    static func device(for id: String) -> DeviceSpec? {
        catalog.first { $0.id == id }
    }

    /// All devices belonging to the given family.
    static func devices(for family: DeviceFamily) -> [DeviceSpec] {
        catalog.filter { $0.family == family }
    }
}
