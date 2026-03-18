import XCTest
@testable import ImageElementStudio

@MainActor
final class DeviceCatalogServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> DeviceCatalogService {
        DeviceCatalogService()
    }

    // MARK: - Initial State

    func testInitialDeviceIsDefaultDevice() {
        let service = makeService()
        XCTAssertEqual(service.selectedDeviceID, Constants.Device.defaultDeviceID)
    }

    func testInitialOrientationIsPortrait() {
        let service = makeService()
        XCTAssertEqual(service.orientation, .portrait)
    }

    func testInitialShowDeviceFrameIsTrue() {
        let service = makeService()
        XCTAssertTrue(service.showDeviceFrame)
    }

    func testInitialShowSafeAreasIsTrue() {
        let service = makeService()
        XCTAssertTrue(service.showSafeAreas)
    }

    // MARK: - Device Catalog

    func testCatalogContainsMultipleDevices() {
        XCTAssertGreaterThanOrEqual(DeviceSpec.catalog.count, 6)
    }

    func testCatalogContainsiPhoneAndIPad() {
        let families = Set(DeviceSpec.catalog.map(\.family))
        XCTAssertTrue(families.contains(.iPhone))
        XCTAssertTrue(families.contains(.iPad))
    }

    func testSelectedDeviceReturnsValidDevice() {
        let service = makeService()
        let device = service.selectedDevice
        XCTAssertFalse(device.name.isEmpty)
        XCTAssertGreaterThan(device.screenWidth, 0)
        XCTAssertGreaterThan(device.screenHeight, 0)
    }

    // MARK: - Device Selection

    func testSelectDeviceChangesSelectedID() {
        let service = makeService()
        guard DeviceSpec.catalog.count >= 2 else { return }

        let otherDevice = DeviceSpec.catalog.first { $0.id != service.selectedDeviceID }!
        service.selectDevice(otherDevice.id)
        XCTAssertEqual(service.selectedDeviceID, otherDevice.id)
    }

    func testSelectFamilyPicksFirstDeviceInFamily() {
        let service = makeService()
        service.selectFamily(.iPad)
        let selected = service.selectedDevice
        XCTAssertEqual(selected.family, .iPad)
    }

    func testSelectFamilyiPhonePicksFirstiPhone() {
        let service = makeService()
        service.selectFamily(.iPad)
        service.selectFamily(.iPhone)
        XCTAssertEqual(service.selectedDevice.family, .iPhone)
    }

    // MARK: - Orientation

    func testToggleOrientationSwitchesToLandscape() {
        let service = makeService()
        XCTAssertEqual(service.orientation, .portrait)
        service.toggleOrientation()
        XCTAssertEqual(service.orientation, .landscape)
    }

    func testToggleOrientationTwiceReturnsToPortrait() {
        let service = makeService()
        service.toggleOrientation()
        service.toggleOrientation()
        XCTAssertEqual(service.orientation, .portrait)
    }

    // MARK: - Effective Screen Size

    func testEffectiveScreenSizePortrait() {
        let service = makeService()
        service.selectFamily(.iPhone)
        let device = service.selectedDevice
        let size = service.effectiveScreenSize
        XCTAssertEqual(size.width, device.screenWidth)
        XCTAssertEqual(size.height, device.screenHeight)
    }

    func testEffectiveScreenSizeLandscape() {
        let service = makeService()
        service.selectFamily(.iPhone)
        service.toggleOrientation()
        let device = service.selectedDevice
        let size = service.effectiveScreenSize
        XCTAssertEqual(size.width, device.screenHeight)
        XCTAssertEqual(size.height, device.screenWidth)
    }

    // MARK: - DeviceSpec Properties

    func testDeviceSpecHasNonNegativeCornerRadius() {
        for device in DeviceSpec.catalog {
            XCTAssertGreaterThanOrEqual(device.cornerRadius, 0, "Device \(device.name) has negative corner radius")
        }
    }

    func testDeviceSpecSafeAreaInsetsNonNegative() {
        for device in DeviceSpec.catalog {
            let sa = device.safeAreaInsets(for: .portrait)
            XCTAssertGreaterThanOrEqual(sa.top, 0)
            XCTAssertGreaterThanOrEqual(sa.bottom, 0)
            XCTAssertGreaterThanOrEqual(sa.left, 0)
            XCTAssertGreaterThanOrEqual(sa.right, 0)
        }
    }

    func testDeviceFamilyFilterReturnsOnlyMatchingFamily() {
        let iphones = DeviceSpec.devices(for: .iPhone)
        for device in iphones {
            XCTAssertEqual(device.family, .iPhone)
        }
        let ipads = DeviceSpec.devices(for: .iPad)
        for device in ipads {
            XCTAssertEqual(device.family, .iPad)
        }
    }

    func testDeviceLookupByID() {
        let device = DeviceSpec.device(for: "iphone16")
        XCTAssertNotNil(device)
        XCTAssertEqual(device?.name, "iPhone 16")
    }

    func testDeviceLookupInvalidIDReturnsNil() {
        let device = DeviceSpec.device(for: "nonexistent_device")
        XCTAssertNil(device)
    }

    func testSelectInvalidDeviceIDIsNoop() {
        let service = makeService()
        let originalID = service.selectedDeviceID
        service.selectDevice("invalid_id")
        XCTAssertEqual(service.selectedDeviceID, originalID)
    }
}
