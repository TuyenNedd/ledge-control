import SwiftUI
import AppKit

/// The About tab in Settings, showing app info, version, and a link to the GitHub repository.
/// Redesigned with more breathing room and a subtitle description.
struct AboutTab: View {
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // UNVERIFIED: NSImage(named: NSImage.applicationIconName) bridged to SwiftUI Image.
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)

            Text("Ledge")
                .font(.title)
                .fontWeight(.semibold)

            Text("Trackpad edge gestures for volume & brightness")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Slide along the edges of your trackpad to adjust volume and brightness without taking your hands off the keyboard area.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Text(versionString)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            // UNVERIFIED: Link view opening a URL on macOS 14+.
            Link("GitHub Repository", destination: URL(string: "https://github.com/TuyenNedd/ledge-control")!)
                .font(.callout)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
