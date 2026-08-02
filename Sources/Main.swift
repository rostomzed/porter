import Foundation

/// Single entry point. The same binary is both the GUI app and the `porter`
/// command-line tool:
///   - launched by Finder/Dock/`open` → SwiftUI app
///   - invoked as `porter` (symlink) or with file arguments → CLI
@main
enum Main {
    static func main() {
        if CLI.isCommandLineInvocation(CommandLine.arguments) {
            CLI.run(CommandLine.arguments)
        }
        PDFConverterApp.main()
    }
}
