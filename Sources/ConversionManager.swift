import Foundation
import AppKit

struct ConversionItem: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case converting
        case done(URL)
        case failed(String)
        case skipped(String)
    }

    let id = UUID()
    let source: URL
    var status: Status = .pending

    var fileName: String { source.lastPathComponent }
}

/// Owns the conversion queue. UI state lives on the main actor; the actual
/// conversions run one at a time on a background queue (Office apps don't
/// like being scripted concurrently).
final class ConversionManager: ObservableObject {
    static let shared = ConversionManager()

    @Published private(set) var items: [ConversionItem] = []

    private let workQueue = DispatchQueue(label: "pdfconverter.work", qos: .userInitiated)

    private init() {}

    var isWorking: Bool {
        items.contains { $0.status == .pending || $0.status == .converting }
    }

    func enqueue(urls: [URL], fromWatcher: Bool = false) {
        let expanded = expandDirectories(urls)
        guard !expanded.isEmpty else { return }

        DispatchQueue.main.async {
            for url in expanded {
                let item = ConversionItem(source: url)
                self.items.insert(item, at: 0)
                self.process(itemID: item.id, url: url, fromWatcher: fromWatcher)
            }
        }
    }

    func clearFinished() {
        items.removeAll {
            if case .converting = $0.status { return false }
            if case .pending = $0.status { return false }
            return true
        }
    }

    // MARK: - Internals

    /// Dropping a folder converts everything inside it (one level of recursion
    /// is plenty for the drop-zone use case — we go fully recursive).
    private func expandDirectories(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let child as URL in enumerator {
                        if (try? child.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                            result.append(child)
                        }
                    }
                }
            } else {
                result.append(url)
            }
        }
        return result
    }

    private func process(itemID: UUID, url: URL, fromWatcher: Bool) {
        workQueue.async {
            self.updateStatus(itemID, .converting)

            if url.pathExtension.lowercased() == "pdf" {
                self.updateStatus(itemID, .skipped("Already a PDF"))
                return
            }

            let output = DispatchQueue.main.sync { AppSettings.shared.outputURL(for: url) }
            do {
                try Converter.convert(input: url, output: output)
                self.updateStatus(itemID, .done(output))
                DispatchQueue.main.async {
                    if !fromWatcher && AppSettings.shared.revealAfterConvert {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                }
            } catch {
                self.updateStatus(itemID, .failed(error.localizedDescription))
            }
        }
    }

    private func updateStatus(_ id: UUID, _ status: ConversionItem.Status) {
        DispatchQueue.main.async {
            if let index = self.items.firstIndex(where: { $0.id == id }) {
                self.items[index].status = status
            }
        }
    }
}
