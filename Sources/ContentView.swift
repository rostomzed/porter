import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var manager: ConversionManager
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var updates = UpdateChecker.shared
    @State private var isDropTargeted = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if let update = updates.available {
                updateBanner(update)
            }

            dropZone
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)

            if !manager.items.isEmpty {
                resultsList
            } else {
                hintArea
            }

            Divider()
            footer
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
    }

    // MARK: - Update banner

    private func updateBanner(_ update: UpdateChecker.Update) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("Porter \(update.version) is available")
                .font(.callout.weight(.medium))
            Spacer()
            if updates.isDownloading {
                ProgressView().controlSize(.small)
            } else {
                Button("Download") { updates.downloadAndOpen() }
                    .controlSize(.small)
            }
            Button {
                updates.available = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 42))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
            Text("Drop files here to convert to PDF")
                .font(.title3.weight(.medium))
            Text("Word · Excel · PowerPoint · Pages · Images · HTML · Markdown · Text")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose Files…") {
                AppDelegate.pickAndConvertFiles()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [7]))
        )
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var found = false
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            found = true
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            ConversionManager.shared.enqueue(urls: urls)
        }
        return found
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(manager.items) { item in
                    ConversionRow(item: item)
                    Divider().padding(.leading, 44)
                }
            }
        }
    }

    private var hintArea: some View {
        VStack(spacing: 8) {
            Spacer()
            if settings.watchEnabled {
                Label {
                    Text("Auto-converting anything dropped into **\(settings.watchFolder.lastPathComponent)**")
                } icon: {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(Color.accentColor)
                }
                .font(.callout)
                Button("Open Drop Folder") {
                    try? FileManager.default.createDirectory(
                        at: settings.watchFolder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(settings.watchFolder)
                }
                .buttonStyle(.link)
            }
            Text("Tip: right-click any file in Finder → Quick Actions → Convert to PDF")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            if manager.isWorking {
                ProgressView().controlSize(.small)
            }
            if !manager.items.isEmpty {
                Button("Clear") { manager.clearFinished() }
            }
        }
        .padding(10)
    }
}

// MARK: - Row

struct ConversionRow: View {
    let item: ConversionItem

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if case .done(let url) = item.status {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .help("Open PDF")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .converting:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch item.status {
        case .pending: Text("Waiting…")
        case .converting: Text("Converting…")
        case .done(let url): Text(url.deletingLastPathComponent().path)
        case .failed(let message): Text(message).foregroundStyle(.red)
        case .skipped(let reason): Text(reason)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.title2.bold())

            GroupBox("Save converted PDFs") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: Binding(
                        get: { settings.outputMode },
                        set: { settings.outputMode = $0 })) {
                        Text("Next to the original file").tag(AppSettings.OutputMode.sameFolder)
                        Text("In one folder").tag(AppSettings.OutputMode.customFolder)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    if settings.outputMode == .customFolder {
                        HStack {
                            Text(settings.customOutputFolder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Change…") { pickFolder { settings.customOutputFolder = $0 } }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Drop folder") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Watch a folder and auto-convert new files", isOn: Binding(
                        get: { settings.watchEnabled },
                        set: { settings.watchEnabled = $0 }))
                    if settings.watchEnabled {
                        HStack {
                            Text(settings.watchFolder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Change…") { pickFolder { settings.watchFolder = $0 } }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox {
                Toggle("Reveal PDF in Finder after converting", isOn: Binding(
                    get: { settings.revealAfterConvert },
                    set: { settings.revealAfterConvert = $0 }))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack {
                Button("Reinstall Right-Click Action") {
                    QuickActionInstaller.installIfNeeded()
                }
                .help("Reinstalls the Finder Quick Action if it went missing")
                Button("Check for Updates") {
                    UpdateChecker.shared.checkSoon(force: true)
                }
                .help("Looks for a newer release on GitHub")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 4) {
                Text("Porter · MIT · authored by")
                Link("Rostom Zouaghi", destination: URL(string: "https://github.com/rostomzed")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .frame(width: 430)
    }

    private func pickFolder(_ apply: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            apply(url)
        }
    }
}
