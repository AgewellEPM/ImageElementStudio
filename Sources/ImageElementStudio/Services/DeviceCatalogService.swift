import Combine
import SwiftUI

/// Service that manages the currently selected device, orientation, and display options
/// for the device emulator feature.
@MainActor
final class DeviceCatalogService: ObservableObject {

    // MARK: - Published State

    @Published var selectedDeviceID: String = DeviceSpec.defaultDeviceID
    @Published var orientation: DeviceOrientation = .portrait
    @Published var showSafeAreas: Bool = true
    @Published var showDeviceFrame: Bool = true

    // MARK: - Computed Properties

    /// The full spec for the currently selected device, falling back to the first catalog entry.
    var selectedDevice: DeviceSpec {
        DeviceSpec.device(for: selectedDeviceID) ?? DeviceSpec.catalog[0]
    }

    /// Screen size of the selected device in the current orientation.
    var effectiveScreenSize: CGSize {
        selectedDevice.screenSize(for: orientation)
    }

    /// Safe area insets of the selected device in the current orientation.
    var effectiveSafeArea: NSEdgeInsets {
        selectedDevice.safeAreaInsets(for: orientation)
    }

    /// The device family of the currently selected device.
    var selectedFamily: DeviceFamily {
        selectedDevice.family
    }

    /// All devices that share the same family as the current selection.
    var devicesInCurrentFamily: [DeviceSpec] {
        DeviceSpec.devices(for: selectedFamily)
    }

    // MARK: - Actions

    /// Select a device by its identifier. No-op if the identifier is not in the catalog.
    func selectDevice(_ id: String) {
        guard DeviceSpec.device(for: id) != nil else { return }
        selectedDeviceID = id
    }

    /// Switch to a different device family, selecting the first device in that family.
    func selectFamily(_ family: DeviceFamily) {
        guard let firstDevice = DeviceSpec.devices(for: family).first else { return }
        selectedDeviceID = firstDevice.id
    }

    /// Toggle between portrait and landscape orientation.
    func toggleOrientation() {
        orientation = orientation == .portrait ? .landscape : .portrait
    }
}
