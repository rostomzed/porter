import Foundation
import AppKit
import Combine

/// Checks GitHub Releases for a newer Porter and offers the DMG.
/// No frameworks, no server of our own: one GET against the public
/// releases API, at most once a day.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Update: Equatable {
        let version: String      // e.g. "1.2.0"
        let releaseURL: URL      // release page
        let dmgURL: URL?         // direct DMG asset, when present
    }

    @Published var available: Update?
    @Published var isDownloading = false

    private static let apiURL = URL(string: "https://api.github.com/repos/rostomzed/porter/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private init() {}

    static var currentVersion: String {
        if let fake = ProcessInfo.processInfo.environment["PORTER_FAKE_VERSION"] { return fake }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Called at launch. Skips silently if a check ran within the last day.
    func checkSoon(force: Bool = false) {
        if !force {
            let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
            guard Date().timeIntervalSince(last) > Self.checkInterval else { return }
        }
        Task { [weak self] in
            let update = await Self.fetchLatest()
            await MainActor.run {
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                self?.available = update
            }
        }
    }

    /// Returns an Update only when the latest release is strictly newer.
    static func fetchLatest() async -> Update? {
        var request = URLRequest(url: apiURL)
        request.setValue("porter-app", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            return nil
        }

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isVersion(latest, newerThan: currentVersion) else { return nil }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets
            .compactMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
            .first { $0.pathExtension.lowercased() == "dmg" }

        return Update(version: latest, releaseURL: htmlURL, dmgURL: dmg)
    }

    /// Downloads the DMG into Porter's cache (no Downloads-folder permission
    /// needed) and opens it — the user drags the new Porter to Applications.
    /// Falls back to opening the release page in the browser.
    func downloadAndOpen() {
        guard let update = available else { return }
        guard let dmgURL = update.dmgURL else {
            NSWorkspace.shared.open(update.releaseURL)
            return
        }
        isDownloading = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.isDownloading = false } }
            do {
                let (temp, _) = try await URLSession.shared.download(from: dmgURL)
                let dir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Caches/Porter/updates", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent("Porter-v\(update.version).dmg")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: temp, to: dest)
                await MainActor.run { NSWorkspace.shared.open(dest) }
            } catch {
                await MainActor.run { NSWorkspace.shared.open(update.releaseURL) }
            }
        }
    }

    /// Strict numeric semver comparison ("1.10.0" > "1.9.9").
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
