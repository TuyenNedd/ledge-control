import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A view that manages the per-app exclusion list, allowing users to add and remove apps
/// whose frontmost status should disable gesture detection.
struct ExcludedAppsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.excludedApps.isEmpty {
                Text("No excluded apps.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.excludedApps, id: \.self) { bundleID in
                    HStack {
                        appIcon(for: bundleID)
                            .resizable()
                            .frame(width: 20, height: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(appName(for: bundleID))
                                .font(.body)
                            Text(bundleID)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            viewModel.removeExcludedApp(bundleID)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 12) {
                Button {
                    addAppFromFilePicker()
                } label: {
                    Label("Add App", systemImage: "plus")
                }

                if let previousApp = viewModel.previousFrontmostApp, !previousApp.isEmpty {
                    Button {
                        viewModel.addExcludedApp(previousApp)
                    } label: {
                        Label("Add Current App", systemImage: "app.badge.checkmark")
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    /// Open a file picker for .app bundles and extract the bundle ID.
    private func addAppFromFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select an application to exclude from gesture detection."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Read the bundle identifier from the selected .app
        if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
            viewModel.addExcludedApp(bundleID)
        }
    }

    /// Resolve an app icon from a bundle identifier.
    private func appIcon(for bundleID: String) -> Image {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "app")
    }

    /// Resolve an app name from a bundle identifier, falling back to the identifier itself.
    private func appName(for bundleID: String) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: appURL),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return bundleID
    }
}
