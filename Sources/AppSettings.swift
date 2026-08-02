import Foundation
import Combine

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// Where converted PDFs are written.
    enum OutputMode: String {
        case sameFolder   // next to the original file
        case customFolder // a single fixed folder
    }

    @Published var outputMode: OutputMode {
        didSet { defaults.set(outputMode.rawValue, forKey: "outputMode") }
    }

    @Published var customOutputFolder: URL {
        didSet { defaults.set(customOutputFolder.path, forKey: "customOutputFolder") }
    }

    /// Drop-folder watching.
    @Published var watchEnabled: Bool {
        didSet {
            defaults.set(watchEnabled, forKey: "watchEnabled")
            FolderWatcher.shared.syncWithSettings()
        }
    }

    @Published var watchFolder: URL {
        didSet {
            defaults.set(watchFolder.path, forKey: "watchFolder")
            FolderWatcher.shared.syncWithSettings()
        }
    }

    /// Reveal the PDF in Finder after a manual (window / right-click) conversion.
    @Published var revealAfterConvert: Bool {
        didSet { defaults.set(revealAfterConvert, forKey: "revealAfterConvert") }
    }

    static var defaultWatchFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/PDF Drop", isDirectory: true)
    }

    private init() {
        let mode = OutputMode(rawValue: defaults.string(forKey: "outputMode") ?? "") ?? .sameFolder
        outputMode = mode

        if let path = defaults.string(forKey: "customOutputFolder") {
            customOutputFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            customOutputFolder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Converted PDFs", isDirectory: true)
        }

        watchEnabled = defaults.object(forKey: "watchEnabled") as? Bool ?? true

        if let path = defaults.string(forKey: "watchFolder") {
            watchFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            watchFolder = Self.defaultWatchFolder
        }

        revealAfterConvert = defaults.object(forKey: "revealAfterConvert") as? Bool ?? true
    }

    /// Resolve the output PDF URL for a given input, honoring settings and
    /// never overwriting an existing file.
    func outputURL(for input: URL) -> URL {
        let directory: URL
        switch outputMode {
        case .sameFolder:
            directory = input.deletingLastPathComponent()
        case .customFolder:
            directory = customOutputFolder
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = input.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(base).appendingPathExtension("pdf")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension("pdf")
            counter += 1
        }
        return candidate
    }
}
