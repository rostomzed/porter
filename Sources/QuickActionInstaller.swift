import Foundation

/// Installs a Finder Quick Action ("Convert to PDF") into ~/Library/Services
/// so it appears when right-clicking files in Finder, under Quick Actions.
/// The action simply opens the selected files with this app, which converts
/// them.
enum QuickActionInstaller {

    static let workflowName = "Convert to PDF.workflow"

    static var workflowURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/\(workflowName)", isDirectory: true)
    }

    static func installIfNeeded() {
        let contents = workflowURL.appendingPathComponent("Contents", isDirectory: true)
        let infoURL = contents.appendingPathComponent("Info.plist")
        let documentURL = contents.appendingPathComponent("document.wflow")

        // Skip if already installed with identical content.
        if let existing = try? String(contentsOf: documentURL, encoding: .utf8),
           existing == documentWflow,
           FileManager.default.fileExists(atPath: infoURL.path) {
            return
        }

        do {
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try infoPlist.write(to: infoURL, atomically: true, encoding: .utf8)
            try documentWflow.write(to: documentURL, atomically: true, encoding: .utf8)
            refreshServices()
        } catch {
            NSLog("Quick Action install failed: \(error)")
        }
    }

    /// Ask the pasteboard/services server to pick up the new service now
    /// instead of waiting for the next login.
    private static func refreshServices() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-update"]
        try? process.run()
    }

    // MARK: - Workflow bundle contents

    private static let infoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>NSServices</key>
        <array>
            <dict>
                <key>NSBackgroundColorName</key>
                <string>background</string>
                <key>NSIconName</key>
                <string>NSActionTemplate</string>
                <key>NSMenuItem</key>
                <dict>
                    <key>default</key>
                    <string>Convert to PDF</string>
                </dict>
                <key>NSMessage</key>
                <string>runWorkflowAsService</string>
                <key>NSRequiredContext</key>
                <dict>
                    <key>NSApplicationIdentifier</key>
                    <string>com.apple.finder</string>
                </dict>
                <key>NSSendFileTypes</key>
                <array>
                    <string>public.item</string>
                </array>
            </dict>
        </array>
    </dict>
    </plist>
    """

    private static let documentWflow = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>AMApplicationBuild</key>
        <string>528</string>
        <key>AMApplicationVersion</key>
        <string>2.10</string>
        <key>AMDocumentVersion</key>
        <string>2</string>
        <key>actions</key>
        <array>
            <dict>
                <key>action</key>
                <dict>
                    <key>AMAccepts</key>
                    <dict>
                        <key>Container</key>
                        <string>List</string>
                        <key>Optional</key>
                        <true/>
                        <key>Types</key>
                        <array>
                            <string>com.apple.cocoa.string</string>
                        </array>
                    </dict>
                    <key>AMActionVersion</key>
                    <string>2.0.3</string>
                    <key>AMApplication</key>
                    <array>
                        <string>Automator</string>
                    </array>
                    <key>AMParameterProperties</key>
                    <dict>
                        <key>COMMAND_STRING</key>
                        <dict/>
                        <key>CheckedForUserDefaultShell</key>
                        <dict/>
                        <key>inputMethod</key>
                        <dict/>
                        <key>shell</key>
                        <dict/>
                        <key>source</key>
                        <dict/>
                    </dict>
                    <key>AMProvides</key>
                    <dict>
                        <key>Container</key>
                        <string>List</string>
                        <key>Types</key>
                        <array>
                            <string>com.apple.cocoa.string</string>
                        </array>
                    </dict>
                    <key>ActionBundlePath</key>
                    <string>/System/Library/Automator/Run Shell Script.action</string>
                    <key>ActionName</key>
                    <string>Run Shell Script</string>
                    <key>ActionParameters</key>
                    <dict>
                        <key>COMMAND_STRING</key>
                        <string>open -a "Porter" "$@"</string>
                        <key>CheckedForUserDefaultShell</key>
                        <true/>
                        <key>inputMethod</key>
                        <integer>1</integer>
                        <key>shell</key>
                        <string>/bin/zsh</string>
                        <key>source</key>
                        <string></string>
                    </dict>
                    <key>BundleIdentifier</key>
                    <string>com.apple.RunShellScript</string>
                    <key>CFBundleVersion</key>
                    <string>2.0.3</string>
                    <key>CanShowSelectedItemsWhenRun</key>
                    <false/>
                    <key>CanShowWhenRun</key>
                    <true/>
                    <key>Category</key>
                    <array>
                        <string>AMCategoryUtilities</string>
                    </array>
                    <key>Class Name</key>
                    <string>RunShellScriptAction</string>
                    <key>InputUUID</key>
                    <string>5E4C4E82-1E4E-4B7E-9AAF-6BB0378B1A01</string>
                    <key>Keywords</key>
                    <array>
                        <string>Shell</string>
                    </array>
                    <key>OutputUUID</key>
                    <string>5E4C4E82-1E4E-4B7E-9AAF-6BB0378B1A02</string>
                    <key>UUID</key>
                    <string>5E4C4E82-1E4E-4B7E-9AAF-6BB0378B1A03</string>
                    <key>UnlocalizedApplications</key>
                    <array>
                        <string>Automator</string>
                    </array>
                    <key>arguments</key>
                    <dict>
                        <key>0</key>
                        <dict>
                            <key>default value</key>
                            <integer>0</integer>
                            <key>name</key>
                            <string>inputMethod</string>
                            <key>required</key>
                            <string>0</string>
                            <key>type</key>
                            <string>0</string>
                            <key>uuid</key>
                            <string>0</string>
                        </dict>
                        <key>1</key>
                        <dict>
                            <key>default value</key>
                            <false/>
                            <key>name</key>
                            <string>CheckedForUserDefaultShell</string>
                            <key>required</key>
                            <string>0</string>
                            <key>type</key>
                            <string>0</string>
                            <key>uuid</key>
                            <string>1</string>
                        </dict>
                        <key>2</key>
                        <dict>
                            <key>default value</key>
                            <string></string>
                            <key>name</key>
                            <string>source</string>
                            <key>required</key>
                            <string>0</string>
                            <key>type</key>
                            <string>0</string>
                            <key>uuid</key>
                            <string>2</string>
                        </dict>
                        <key>3</key>
                        <dict>
                            <key>default value</key>
                            <string></string>
                            <key>name</key>
                            <string>COMMAND_STRING</string>
                            <key>required</key>
                            <string>0</string>
                            <key>type</key>
                            <string>0</string>
                            <key>uuid</key>
                            <string>3</string>
                        </dict>
                        <key>4</key>
                        <dict>
                            <key>default value</key>
                            <string>/bin/sh</string>
                            <key>name</key>
                            <string>shell</string>
                            <key>required</key>
                            <string>0</string>
                            <key>type</key>
                            <string>0</string>
                            <key>uuid</key>
                            <string>4</string>
                        </dict>
                    </dict>
                    <key>isViewVisible</key>
                    <integer>1</integer>
                    <key>location</key>
                    <string>309.000000:253.000000</string>
                    <key>nibPath</key>
                    <string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
                </dict>
                <key>isViewVisible</key>
                <integer>1</integer>
            </dict>
        </array>
        <key>connectors</key>
        <dict/>
        <key>workflowMetaData</key>
        <dict>
            <key>applicationBundleIDsByPath</key>
            <dict/>
            <key>applicationPaths</key>
            <array/>
            <key>inputTypeIdentifier</key>
            <string>com.apple.Automator.fileSystemObject</string>
            <key>outputTypeIdentifier</key>
            <string>com.apple.Automator.nothing</string>
            <key>presentationMode</key>
            <integer>15</integer>
            <key>processesInput</key>
            <integer>0</integer>
            <key>serviceInputTypeIdentifier</key>
            <string>com.apple.Automator.fileSystemObject</string>
            <key>serviceOutputTypeIdentifier</key>
            <string>com.apple.Automator.nothing</string>
            <key>serviceProcessesInput</key>
            <integer>0</integer>
            <key>systemImageName</key>
            <string>NSActionTemplate</string>
            <key>useAutomaticInputType</key>
            <integer>0</integer>
            <key>workflowTypeIdentifier</key>
            <string>com.apple.Automator.servicesMenu</string>
        </dict>
    </dict>
    </plist>
    """
}
