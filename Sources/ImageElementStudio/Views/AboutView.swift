import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 48))
                .foregroundStyle(.linearGradient(
                    colors: [Color(red: 0.23, green: 0.46, blue: 0.94),
                             Color(red: 0.10, green: 0.23, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("Image Element Studio")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("AI-powered design analysis and\napp generation tool.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 200)

            VStack(spacing: 6) {
                Link("Privacy Policy", destination: AboutView.privacyPolicyURL)
                Link("Terms of Service", destination: AboutView.termsOfServiceURL)
                Link("Support", destination: AboutView.supportURL)
            }
            .font(.caption)

            Text("Copyright 2025-2026. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 320, height: 360)
    }

    // MARK: - URLs

    static let privacyPolicyURL = URL(string: "https://imageelementstudio.com/privacy")!
    static let termsOfServiceURL = URL(string: "https://imageelementstudio.com/terms")!
    static let supportURL = URL(string: "https://imageelementstudio.com/support")!
}
