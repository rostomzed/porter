import Foundation
import AppKit

/// Converts documents by scripting the real applications (Microsoft Office /
/// iWork). This is what makes legacy .doc conversion pixel-perfect: the file
/// is rendered by Word itself.
enum OfficeConverter {

    enum OfficeApp: String {
        case word = "com.microsoft.Word"
        case excel = "com.microsoft.Excel"
        case powerPoint = "com.microsoft.Powerpoint"
        case pages = "com.apple.iWork.Pages"
        case numbers = "com.apple.iWork.Numbers"
        case keynote = "com.apple.iWork.Keynote"
    }

    static func isInstalled(_ app: OfficeApp) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.rawValue) != nil
    }

    // MARK: - Microsoft Word

    static func convertWithWord(input: URL, output: URL) throws {
        let script = """
        with timeout of 600 seconds
            tell application id "com.microsoft.Word"
                launch
                open (POSIX file \(quoted(input.path)))
                set theDoc to active document
                save as theDoc file name \(quoted(output.path)) file format format PDF
                close theDoc saving no
            end tell
        end timeout
        """
        try runAppleScript(script, engine: "Microsoft Word")
    }

    // MARK: - Microsoft Excel

    static func convertWithExcel(input: URL, output: URL) throws {
        let script = """
        with timeout of 600 seconds
            tell application id "com.microsoft.Excel"
                launch
                open (POSIX file \(quoted(input.path)))
                set theBook to active workbook
                save workbook as theBook filename \(quoted(output.path)) file format PDF file format
                close theBook saving no
            end tell
        end timeout
        """
        try runAppleScript(script, engine: "Microsoft Excel")
    }

    // MARK: - Microsoft PowerPoint

    static func convertWithPowerPoint(input: URL, output: URL) throws {
        let script = """
        with timeout of 600 seconds
            tell application id "com.microsoft.Powerpoint"
                launch
                open (POSIX file \(quoted(input.path)))
                set thePres to active presentation
                save thePres in (POSIX file \(quoted(output.path))) as save as PDF
                close thePres saving no
            end tell
        end timeout
        """
        try runAppleScript(script, engine: "Microsoft PowerPoint")
    }

    // MARK: - iWork (Pages / Numbers / Keynote)

    static func convertWithIWork(app: OfficeApp, input: URL, output: URL) throws {
        guard isInstalled(app) else {
            throw ConversionError.engineUnavailable(
                "This file type requires \(displayName(app)) to be installed")
        }
        let script = """
        with timeout of 600 seconds
            tell application id \(quoted(app.rawValue))
                launch
                set theDoc to open (POSIX file \(quoted(input.path)))
                export theDoc to (POSIX file \(quoted(output.path))) as PDF
                close theDoc saving no
            end tell
        end timeout
        """
        try runAppleScript(script, engine: displayName(app))
    }

    // MARK: - Plumbing

    private static func displayName(_ app: OfficeApp) -> String {
        switch app {
        case .word: return "Microsoft Word"
        case .excel: return "Microsoft Excel"
        case .powerPoint: return "Microsoft PowerPoint"
        case .pages: return "Pages"
        case .numbers: return "Numbers"
        case .keynote: return "Keynote"
        }
    }

    /// AppleScript string literal with escaping.
    private static func quoted(_ string: String) -> String {
        "\"" + string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }

    /// Runs a script via `osascript` as a child process. macOS attributes the
    /// Apple-events permission to this app (the responsible process), so the
    /// user gets a single "Porter would like to control ..." prompt
    /// per target app the first time.
    private static func runAppleScript(_ script: String, engine: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw ConversionError.engineFailed("Couldn’t launch osascript: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            var message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // osascript errors look like "123:145: execution error: ... (-1743)"
            if let range = message.range(of: "execution error: ") {
                message = String(message[range.upperBound...])
            }
            if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") {
                message = "Permission needed: open System Settings → Privacy & Security → Automation and allow Porter to control \(engine)."
            }
            if message.isEmpty { message = "\(engine) failed to convert the file" }
            throw ConversionError.engineFailed(message)
        }
    }
}

/// Optional fallback engine if LibreOffice is installed.
enum LibreOfficeConverter {
    static var sofficeURL: URL? {
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "\(NSHomeDirectory())/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    static var isInstalled: Bool { sofficeURL != nil }

    static func convert(input: URL, output: URL) throws {
        guard let soffice = sofficeURL else {
            throw ConversionError.engineUnavailable("LibreOffice is not installed")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfconvert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = soffice
        process.arguments = ["--headless", "--norestore", "--convert-to", "pdf",
                             "--outdir", tempDir.path, input.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        let produced = tempDir
            .appendingPathComponent(input.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")
        guard FileManager.default.fileExists(atPath: produced.path) else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "LibreOffice failed"
            throw ConversionError.engineFailed(message)
        }
        try FileManager.default.moveItem(at: produced, to: output)
    }
}
