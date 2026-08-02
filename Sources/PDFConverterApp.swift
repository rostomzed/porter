import SwiftUI
import AppKit

struct PDFConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ConversionManager.shared)
                .environmentObject(AppSettings.shared)
                .frame(minWidth: 480, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Convert Files…") {
                    AppDelegate.pickAndConvertFiles()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install the Finder right-click Quick Action on first launch (and
        // keep it up to date on subsequent launches).
        QuickActionInstaller.installIfNeeded()

        // Start the drop-folder watcher if enabled.
        FolderWatcher.shared.syncWithSettings()

        // Once a day, see if a newer release exists on GitHub.
        UpdateChecker.shared.checkSoon()
    }

    // Files opened via Finder ("Open With"), dock-icon drops, the Quick
    // Action, or `open -a "Porter" file...` all arrive here.
    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        ConversionManager.shared.enqueue(urls: urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running so the drop folder keeps working with the window closed.
        return !AppSettings.shared.watchEnabled
    }

    static func pickAndConvertFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Convert"
        panel.message = "Choose files to convert to PDF"
        if panel.runModal() == .OK {
            ConversionManager.shared.enqueue(urls: panel.urls)
        }
    }
}
