import SwiftUI

// MARK: - DevicePickerView

/// Compact toolbar view for selecting a device model, orientation,
/// and toggling safe-area / frame-chrome visibility.
struct DevicePickerView: View {
    @ObservedObject var catalogService: DeviceCatalogService

    var body: some View {
        HStack(spacing: 8) {
            familyPicker
            deviceMenu
            Divider()
                .frame(height: 16)
                .opacity(0.3)
            orientationToggle
            safeAreaToggle
            frameToggle
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Family Segmented Picker

    private var familyPicker: some View {
        Picker("Device", selection: familyBinding) {
            ForEach(DeviceFamily.allCases) { family in
                Label(family.displayName, systemImage: family.symbolName)
                    .tag(family)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .labelsHidden()
    }

    // MARK: - Device Model Menu

    private var deviceMenu: some View {
        Menu {
            ForEach(catalogService.devicesInCurrentFamily) { device in
                Button(action: { catalogService.selectDevice(device.id) }) {
                    HStack {
                        Text(device.name)
                        if device.id == catalogService.selectedDeviceID {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(catalogService.selectedDevice.name)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Orientation Toggle

    private var orientationToggle: some View {
        Button(action: { catalogService.toggleOrientation() }) {
            Image(systemName: orientationIcon)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help("Toggle orientation (\(catalogService.orientation == .portrait ? "Portrait" : "Landscape"))")
    }

    private var orientationIcon: String {
        catalogService.orientation == .portrait ? "rectangle.portrait" : "rectangle.landscape.rotate"
    }

    // MARK: - Safe Area Toggle

    private var safeAreaToggle: some View {
        Button(action: { catalogService.showSafeAreas.toggle() }) {
            Image(systemName: safeAreaIcon)
                .font(.system(size: 13))
                .foregroundStyle(catalogService.showSafeAreas ? Color.blue : Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help(catalogService.showSafeAreas ? "Hide safe areas" : "Show safe areas")
    }

    private var safeAreaIcon: String {
        catalogService.showSafeAreas ? "rectangle.inset.filled.and.person.filled" : "rectangle.dashed"
    }

    // MARK: - Frame Toggle

    private var frameToggle: some View {
        Button(action: { catalogService.showDeviceFrame.toggle() }) {
            Image(systemName: frameIcon)
                .font(.system(size: 13))
                .foregroundStyle(catalogService.showDeviceFrame ? Color.blue : Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help(catalogService.showDeviceFrame ? "Hide device frame" : "Show device frame")
    }

    private var frameIcon: String {
        catalogService.showDeviceFrame ? "iphone" : "rectangle"
    }

    // MARK: - Family Binding

    /// Two-way binding that maps between the published selectedDeviceID and DeviceFamily.
    private var familyBinding: Binding<DeviceFamily> {
        Binding<DeviceFamily>(
            get: { catalogService.selectedFamily },
            set: { newFamily in
                catalogService.selectFamily(newFamily)
            }
        )
    }
}
