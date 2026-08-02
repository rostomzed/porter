import Foundation
import AppKit

/// Watches the "PDF Drop" folder: any supported file dropped into it is
/// converted automatically. Waits until a file stops growing before
/// converting, so half-copied files aren't picked up.
final class FolderWatcher {
    static let shared = FolderWatcher()

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var watchedURL: URL?

    /// Files already handled (path → modification date), so edits re-convert
    /// but repeated scans don't.
    private var handled: [String: Date] = [:]
    private let queue = DispatchQueue(label: "pdfconverter.watcher", qos: .utility)

    private init() {}

    func syncWithSettings() {
        queue.async {
            let settings = DispatchQueue.main.sync {
                (enabled: AppSettings.shared.watchEnabled, folder: AppSettings.shared.watchFolder)
            }
            if settings.enabled {
                self.start(watching: settings.folder)
            } else {
                self.stop()
            }
        }
    }

    // MARK: - Internals (all on `queue`)

    private func start(watching url: URL) {
        if watchedURL == url, source != nil { return }
        stop()

        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename],
            queue: queue)
        source.setEventHandler { [weak self] in
            self?.scheduleScan()
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()

        self.source = source
        self.watchedURL = url

        // Mark files already present as handled — only convert *new* drops.
        primeExistingFiles(in: url)
    }

    private func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
        watchedURL = nil
        handled.removeAll()
    }

    private func primeExistingFiles(in url: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        for file in files {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            handled[file.path] = date
        }
    }

    private var scanPending = false

    private func scheduleScan() {
        guard !scanPending else { return }
        scanPending = true
        // Small debounce; also gives copies a moment to finish.
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.scanPending = false
            self?.scan()
        }
    }

    private func scan() {
        guard let url = watchedURL else { return }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []

        var toConvert: [URL] = []
        for file in files {
            guard let values = try? file.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true else { continue }

            let ext = file.pathExtension.lowercased()
            guard ext != "pdf", Converter.supportedExtensions.contains(ext) else { continue }

            let modified = values.contentModificationDate ?? .distantPast
            if let seen = handled[file.path], seen >= modified { continue }

            // Wait until the file size is stable (finished copying/downloading).
            guard isStable(file, lastSize: values.fileSize ?? 0) else { continue }

            handled[file.path] = modified
            toConvert.append(file)
        }

        if !toConvert.isEmpty {
            ConversionManager.shared.enqueue(urls: toConvert, fromWatcher: true)
        }
    }

    private func isStable(_ file: URL, lastSize: Int) -> Bool {
        Thread.sleep(forTimeInterval: 0.5)
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
        if size == lastSize { return true }
        // Still growing — rescan shortly.
        scheduleScan()
        return false
    }
}
