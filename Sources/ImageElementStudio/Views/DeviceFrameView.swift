import SwiftUI

// MARK: - DeviceFrameView

/// Renders a device frame chrome (bezel, status bar, home indicator, Dynamic Island)
/// around arbitrary content, scaled to fit available space.
struct DeviceFrameView<Content: View>: View {
    let device: DeviceSpec
    let orientation: DeviceOrientation
    let showFrame: Bool
    let showSafeAreas: Bool
    @ViewBuilder let content: () -> Content

    // MARK: - Colors

    private let bezelColor = Color(hex: "#2A2A2E", fallback: .gray)
    private let screenBorderColor = Color(hex: "#1A1A1E", fallback: .black)
    private let safeAreaTint = Color.blue.opacity(0.12)

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let screen = device.screenSize(for: orientation)
            let totalSize = outerSize(screen: screen)
            let scale = fitScale(outer: totalSize, container: geometry.size)

            ZStack {
                if showFrame {
                    framedDevice(screen: screen, scale: scale)
                } else {
                    bareScreen(screen: screen, scale: scale)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Framed device (with bezel)

    @ViewBuilder
    private func framedDevice(screen: CGSize, scale: CGFloat) -> some View {
        let bezel = device.bezelWidth
        let outerW = screen.width + bezel * 2
        let outerH = screen.height + bezel * 2
        let outerCorner = device.cornerRadius + bezel * 0.6
        let scaledOuterW = outerW * scale
        let scaledOuterH = outerH * scale

        ZStack {
            // Bezel body
            RoundedRectangle(cornerRadius: outerCorner * scale, style: .continuous)
                .fill(bezelColor)
                .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)
                .frame(width: scaledOuterW, height: scaledOuterH)

            // Screen area
            ZStack {
                // Screen background
                Color.black

                // User content
                content()
                    .frame(width: screen.width * scale, height: screen.height * scale)
                    .clipped()

                // Safe area overlays
                if showSafeAreas {
                    SafeAreaOverlay(
                        device: device,
                        orientation: orientation,
                        screenSize: screen,
                        scale: scale,
                        tint: safeAreaTint
                    )
                }

                // Status bar overlay
                StatusBarOverlay(
                    device: device,
                    orientation: orientation,
                    scale: scale,
                    screenWidth: screen.width
                )

                // Home indicator
                if !device.hasHomeButton {
                    HomeIndicatorOverlay(
                        orientation: orientation,
                        scale: scale,
                        bottomInset: device.homeIndicatorHeight
                    )
                }

                // Dynamic Island
                if device.hasDynamicIsland && orientation == .portrait {
                    DynamicIslandView(scale: scale)
                }

                // Notch (for older Face ID devices)
                if device.hasNotch && !device.hasDynamicIsland && orientation == .portrait {
                    NotchView(scale: scale, screenWidth: screen.width)
                }
            }
            .frame(width: screen.width * scale, height: screen.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: device.cornerRadius * scale, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: device.cornerRadius * scale, style: .continuous)
                    .stroke(screenBorderColor, lineWidth: 1)
            )

            // Side button accents on the bezel
            if orientation == .portrait {
                bezelButtons(outerW: scaledOuterW, outerH: scaledOuterH, scale: scale)
            }
        }
    }

    // MARK: - Bare screen (no bezel)

    @ViewBuilder
    private func bareScreen(screen: CGSize, scale: CGFloat) -> some View {
        ZStack {
            Color.black

            content()
                .frame(width: screen.width * scale, height: screen.height * scale)
                .clipped()

            if showSafeAreas {
                SafeAreaOverlay(
                    device: device,
                    orientation: orientation,
                    screenSize: screen,
                    scale: scale,
                    tint: safeAreaTint
                )
            }

            StatusBarOverlay(
                device: device,
                orientation: orientation,
                scale: scale,
                screenWidth: screen.width
            )

            if !device.hasHomeButton {
                HomeIndicatorOverlay(
                    orientation: orientation,
                    scale: scale,
                    bottomInset: device.homeIndicatorHeight
                )
            }

            if device.hasDynamicIsland && orientation == .portrait {
                DynamicIslandView(scale: scale)
            }

            if device.hasNotch && !device.hasDynamicIsland && orientation == .portrait {
                NotchView(scale: scale, screenWidth: screen.width)
            }
        }
        .frame(width: screen.width * scale, height: screen.height * scale)
        .clipShape(RoundedRectangle(cornerRadius: device.cornerRadius * scale, style: .continuous))
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    // MARK: - Bezel side buttons

    @ViewBuilder
    private func bezelButtons(outerW: CGFloat, outerH: CGFloat, scale: CGFloat) -> some View {
        let buttonColor = Color(hex: "#3A3A3E", fallback: .gray)
        let buttonWidth: CGFloat = 3 * scale
        let powerHeight: CGFloat = 46 * scale
        let volumeHeight: CGFloat = 32 * scale

        // Power button (right side)
        RoundedRectangle(cornerRadius: 1.5 * scale)
            .fill(buttonColor)
            .frame(width: buttonWidth, height: powerHeight)
            .offset(x: outerW / 2 + buttonWidth * 0.3, y: -outerH * 0.12)

        // Volume up (left side)
        RoundedRectangle(cornerRadius: 1.5 * scale)
            .fill(buttonColor)
            .frame(width: buttonWidth, height: volumeHeight)
            .offset(x: -outerW / 2 - buttonWidth * 0.3, y: -outerH * 0.15)

        // Volume down (left side)
        RoundedRectangle(cornerRadius: 1.5 * scale)
            .fill(buttonColor)
            .frame(width: buttonWidth, height: volumeHeight)
            .offset(x: -outerW / 2 - buttonWidth * 0.3, y: -outerH * 0.08)
    }

    // MARK: - Sizing helpers

    /// Total outer size of the device including bezel.
    private func outerSize(screen: CGSize) -> CGSize {
        if showFrame {
            let bezel = device.bezelWidth
            return CGSize(
                width: screen.width + bezel * 2,
                height: screen.height + bezel * 2
            )
        }
        return screen
    }

    /// Scale factor to fit the device proportionally inside the container,
    /// leaving a small margin for shadows and breathing room.
    private func fitScale(outer: CGSize, container: CGSize) -> CGFloat {
        let margin: CGFloat = 24
        let availW = max(1, container.width - margin)
        let availH = max(1, container.height - margin)
        let scaleX = availW / outer.width
        let scaleY = availH / outer.height
        return min(scaleX, scaleY, 1.0)
    }
}

// MARK: - StatusBarOverlay

/// Renders a simulated iOS status bar at the top of the screen area.
private struct StatusBarOverlay: View {
    let device: DeviceSpec
    let orientation: DeviceOrientation
    let scale: CGFloat
    let screenWidth: CGFloat

    var body: some View {
        VStack {
            if orientation == .portrait {
                portraitStatusBar
            } else {
                landscapeStatusBar
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var portraitStatusBar: some View {
        let barHeight = device.statusBarHeight * scale
        let topPad: CGFloat = device.hasDynamicIsland ? 14 * scale : (device.hasNotch ? 12 * scale : 2 * scale)

        HStack {
            // Left cluster: time
            Text("9:41")
                .font(.system(size: max(8, 14 * scale), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.leading, 24 * scale)

            Spacer()

            // Right cluster: signal, wifi, battery
            HStack(spacing: 5 * scale) {
                Image(systemName: "cellularbars")
                    .font(.system(size: max(6, 12 * scale)))
                Image(systemName: "wifi")
                    .font(.system(size: max(6, 12 * scale)))
                BatteryIcon(scale: scale)
            }
            .foregroundStyle(Color.white)
            .padding(.trailing, 16 * scale)
        }
        .frame(height: barHeight)
        .padding(.top, topPad)
    }

    @ViewBuilder
    private var landscapeStatusBar: some View {
        // Landscape status bar is minimal: just time + battery in the top-right area
        HStack {
            Spacer()
            HStack(spacing: 5 * scale) {
                Text("9:41")
                    .font(.system(size: max(7, 11 * scale), weight: .semibold, design: .rounded))
                Image(systemName: "cellularbars")
                    .font(.system(size: max(5, 10 * scale)))
                Image(systemName: "wifi")
                    .font(.system(size: max(5, 10 * scale)))
                BatteryIcon(scale: scale)
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.trailing, 12 * scale)
            .padding(.top, 4 * scale)
        }
    }
}

// MARK: - BatteryIcon

/// Simple battery icon built from SF Symbols.
private struct BatteryIcon: View {
    let scale: CGFloat

    var body: some View {
        Image(systemName: "battery.75percent")
            .font(.system(size: max(6, 13 * scale)))
    }
}

// MARK: - HomeIndicatorOverlay

/// Renders the bottom home indicator pill found on Face ID devices.
private struct HomeIndicatorOverlay: View {
    let orientation: DeviceOrientation
    let scale: CGFloat
    let bottomInset: CGFloat

    private let pillWidth: CGFloat = 134
    private let pillHeight: CGFloat = 5

    var body: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: pillHeight * scale / 2, style: .continuous)
                .fill(Color.white.opacity(0.35))
                .frame(
                    width: pillWidth * scale,
                    height: pillHeight * scale
                )
                .padding(.bottom, indicatorBottomPadding)
        }
    }

    private var indicatorBottomPadding: CGFloat {
        switch orientation {
        case .portrait:
            return max(4 * scale, (bottomInset * 0.25) * scale)
        case .landscape:
            return 4 * scale
        }
    }
}

// MARK: - DynamicIslandView

/// Renders the Dynamic Island pill shape at the top center of the screen.
private struct DynamicIslandView: View {
    let scale: CGFloat

    private let islandWidth: CGFloat = 126
    private let islandHeight: CGFloat = 37
    private let islandTopOffset: CGFloat = 11

    var body: some View {
        VStack {
            Capsule(style: .continuous)
                .fill(Color.black)
                .frame(
                    width: islandWidth * scale,
                    height: islandHeight * scale
                )
                .padding(.top, islandTopOffset * scale)
            Spacer()
        }
    }
}

// MARK: - NotchView

/// Renders the classic notch shape for older Face ID iPhones (iPhone X through 13).
private struct NotchView: View {
    let scale: CGFloat
    let screenWidth: CGFloat

    private let notchWidthFraction: CGFloat = 0.42
    private let notchHeight: CGFloat = 34

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                .fill(Color.black)
                .frame(
                    width: screenWidth * notchWidthFraction * scale,
                    height: notchHeight * scale
                )
            Spacer()
        }
    }
}

// MARK: - SafeAreaOverlay

/// Draws translucent tinted bands over the safe area insets to visualize them.
private struct SafeAreaOverlay: View {
    let device: DeviceSpec
    let orientation: DeviceOrientation
    let screenSize: CGSize
    let scale: CGFloat
    let tint: Color

    var body: some View {
        let insets = device.safeAreaInsets(for: orientation)
        let w = screenSize.width * scale
        let h = screenSize.height * scale

        ZStack(alignment: .topLeading) {
            // Top safe area band
            if insets.top > 0 {
                tint
                    .frame(width: w, height: insets.top * scale)
                    .position(x: w / 2, y: insets.top * scale / 2)
            }

            // Bottom safe area band
            if insets.bottom > 0 {
                tint
                    .frame(width: w, height: insets.bottom * scale)
                    .position(x: w / 2, y: h - insets.bottom * scale / 2)
            }

            // Left safe area band
            if insets.left > 0 {
                tint
                    .frame(width: insets.left * scale, height: h)
                    .position(x: insets.left * scale / 2, y: h / 2)
            }

            // Right safe area band
            if insets.right > 0 {
                tint
                    .frame(width: insets.right * scale, height: h)
                    .position(x: w - insets.right * scale / 2, y: h / 2)
            }
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }
}
