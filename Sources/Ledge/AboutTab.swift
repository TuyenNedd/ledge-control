import SwiftUI
import AppKit

/// The About tab in Settings, showing app info, version, and a link to the GitHub repository.
struct AboutTab: View {
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // UNVERIFIED: NSImage(named: NSImage.applicationIconName) bridged to SwiftUI Image.
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)

            Text("Ledge")
                .font(.title)
                .fontWeight(.semibold)

            Text("Trackpad edge gestures for volume & brightness")
                .font(.body)
                .foregroundStyle(.secondary)

            Text(versionString)
                .font(.caption)
                .foregroundStyle(.tertiary)

            // UNVERIFIED: Link view opening a URL on macOS 14+.
            Link("GitHub Repository", destination: URL(string: "https://github.com/TuyenNedd/ledge-control")!)
                .font(.callout)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
