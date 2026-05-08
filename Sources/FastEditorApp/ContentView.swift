import FastEditorModels
import SwiftUI

struct ContentView: View {
    @StateObject var editor = EditorCoreBridge()
    @State var showsMarkdownPreview = false
    @State var showsAgentPanel = true
    @State var showsTaskOutputPanel = true
    @State var showsFindBar = true
    @State var showsQuickOpenPanel = false
    @State var showsGoToLinePanel = false
    @State var sidebarMode: ProjectSidebarMode = .files
    @State var goToLineInput = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            workspaceSurface
        }
        .alert("Editor Core Error", isPresented: editor.errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newFile)) { _ in
            editor.newFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openFile)) { _ in
            openFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openFolder)) { _ in
            openFolder()
            sidebarMode = .files
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.save)) { _ in
            saveFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.undo)) { _ in
            editor.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.redo)) { _ in
            editor.redo()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.find)) { _ in
            showsFindBar = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.workspaceSearch)) { _ in
            sidebarMode = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.quickOpen)) { _ in
            editor.updateQuickOpenQuery("")
            showsQuickOpenPanel = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.goToLine)) { _ in
            goToLineInput = ""
            showsGoToLinePanel = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.findReferences)) { _ in
            sidebarMode = .references
            editor.findReferencesForCurrentQuery()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.navigateBack)) { _ in
            editor.goBackInNavigationHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.navigateForward)) { _ in
            editor.goForwardInNavigationHistory()
        }
        .onChange(of: editor.selectedTaskPlan?.taskID) { _, taskID in
            if taskID != nil {
                showsTaskOutputPanel = true
            }
        }
        .sheet(isPresented: $showsQuickOpenPanel) {
            QuickOpenPanel(editor: editor, isPresented: $showsQuickOpenPanel)
                .frame(width: 560, height: 420)
        }
        .sheet(isPresented: $showsGoToLinePanel) {
            GoToLinePanel(
                editor: editor,
                input: $goToLineInput,
                isPresented: $showsGoToLinePanel
            )
            .frame(width: 320, height: 120)
        }
    }

    var workspaceSurface: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)

            centerSurface
                .frame(minWidth: 420)

            if showsAgentPanel {
                AgentPanel(editor: editor)
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
            }
        }
    }

    var centerSurface: some View {
        VStack(spacing: 0) {
            editorSurface
            Divider()
            statusBar

            if showsTaskOutputPanel, let plan = editor.selectedTaskPlan {
                Divider()
                taskOutputPanel(plan)
                    .frame(minHeight: 160, idealHeight: 220, maxHeight: 300)
            }
        }
    }
}
