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

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    AppCommand.post(AppCommand.undo)
                }
                .keyboardShortcut("z")

                Button("Redo") {
                    AppCommand.post(AppCommand.redo)
                }
                .keyboardShortcut("Z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .textEditing) {
                Button("Find in File") {
                    AppCommand.post(AppCommand.find)
                }
                .keyboardShortcut("f")

                Button("Workspace Search") {
                    AppCommand.post(AppCommand.workspaceSearch)
                }
                .keyboardShortcut("F", modifiers: [.command, .shift])

                Button("Quick Open") {
                    AppCommand.post(AppCommand.quickOpen)
                }
                .keyboardShortcut("p")

                Button("Go to Line") {
                    AppCommand.post(AppCommand.goToLine)
                }
                .keyboardShortcut("l")

                Button("Find References") {
                    AppCommand.post(AppCommand.findReferences)
                }
                .keyboardShortcut("r")
            }

            CommandMenu("Navigate") {
                Button("Back") {
                    AppCommand.post(AppCommand.navigateBack)
                }
                .keyboardShortcut("[")

                Button("Forward") {
                    AppCommand.post(AppCommand.navigateForward)
                }
                .keyboardShortcut("]")
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
