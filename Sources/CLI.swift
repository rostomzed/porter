import Foundation

/// Terminal interface: `porter [options] <file>...`
/// Installed as a symlink at /usr/local/bin/porter pointing to the app binary.
enum CLI {

    /// GUI launches have no meaningful arguments (Finder passes none; the
    /// Quick Action delivers files via Apple Events, not argv). Anything else
    /// — a file path, a flag, or being invoked through the `porter` symlink —
    /// means the user is in a terminal.
    static func isCommandLineInvocation(_ args: [String]) -> Bool {
        if URL(fileURLWithPath: args[0]).lastPathComponent == "porter" { return true }
        let meaningful = args.dropFirst().filter { !$0.hasPrefix("-psn") }
        return !meaningful.isEmpty
    }

    static func run(_ args: [String]) -> Never {
        var outputDir: URL?
        var files: [URL] = []
        var quiet = false

        var iterator = args.dropFirst().makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "-h", "--help":
                printUsage()
                exit(0)
            case "-V", "--version":
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                print("porter \(version)")
                exit(0)
            case "-q", "--quiet":
                quiet = true
            case "--check-update":
                let semaphore = DispatchSemaphore(value: 0)
                var result: UpdateChecker.Update?
                Task { result = await UpdateChecker.fetchLatest(); semaphore.signal() }
                semaphore.wait()
                if let update = result {
                    print("update available: \(update.version) (current \(UpdateChecker.currentVersion))")
                    print(update.releaseURL.absoluteString)
                } else {
                    print("porter \(UpdateChecker.currentVersion) is up to date")
                }
                exit(0)
            case "-o", "--output":
                guard let path = iterator.next() else {
                    fail("missing directory after \(arg)")
                }
                outputDir = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            case _ where arg.hasPrefix("-") && arg != "-":
                fail("unknown option “\(arg)” (see porter --help)")
            default:
                files.append(URL(fileURLWithPath: (arg as NSString).expandingTildeInPath))
            }
        }

        if files.isEmpty {
            printUsage()
            exit(64)
        }

        if let dir = outputDir {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                fail("couldn’t create output directory: \(error.localizedDescription)")
            }
        }

        var failures = 0
        for file in files {
            guard FileManager.default.fileExists(atPath: file.path) else {
                failures += 1
                fputs("porter: no such file: \(file.path)\n", stderr)
                continue
            }
            if file.pathExtension.lowercased() == "pdf" {
                if !quiet { print("skip  \(file.lastPathComponent) (already a PDF)") }
                continue
            }
            let output = outputURL(for: file, in: outputDir)
            do {
                try Converter.convert(input: file, output: output)
                if !quiet { print("ok    \(file.lastPathComponent) → \(output.path)") }
            } catch {
                failures += 1
                fputs("fail  \(file.lastPathComponent): \(error.localizedDescription)\n", stderr)
            }
        }
        exit(failures == 0 ? 0 : 1)
    }

    /// Next to the original (or in `directory`), never overwriting.
    private static func outputURL(for input: URL, in directory: URL?) -> URL {
        let dir = directory ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(base).appendingPathExtension("pdf")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(counter)").appendingPathExtension("pdf")
            counter += 1
        }
        return candidate
    }

    private static func printUsage() {
        print("""
        porter — convert documents to PDF

        Usage: porter [options] <file>...

        Options:
          -o, --output <dir>   Write PDFs into <dir> (default: next to each file)
          -q, --quiet          Only report errors
          --check-update       Check GitHub for a newer release
          -V, --version        Print version
          -h, --help           Show this help

        Supported: Word (.doc/.docx/.rtf/.odt), Excel (.xls/.xlsx/.csv/.ods),
        PowerPoint (.ppt/.pptx/.odp), Pages/Numbers/Keynote, images, HTML,
        Markdown, and plain text. Office formats convert through the installed
        Microsoft Office / iWork apps for full fidelity.
        """)
    }

    private static func fail(_ message: String) -> Never {
        fputs("porter: \(message)\n", stderr)
        exit(64)
    }
}
