import AppKit
import SwiftUI

@main
struct FastEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    AppCommand.post(AppCommand.newFile)
                }
                .keyboardShortcut("n")

                Button("Open File...") {
                    AppCommand.post(AppCommand.openFile)
                }
                .keyboardShortcut("o")

                Button("Open Folder...") {
                    AppCommand.post(AppCommand.openFolder)
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    AppCommand.post(AppCommand.save)
                }
                .keyboardShortcut("s")
            }

            CommandGroup(replacing: .textEditing) {
                Button("Find") {
                    AppCommand.post(AppCommand.find)
                }
                .keyboardShortcut("f")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
