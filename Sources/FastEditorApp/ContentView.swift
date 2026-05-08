import FastEditorModels
import SwiftUI

struct ContentView: View {
    @StateObject var editor = EditorCoreBridge()
    @State var showsMarkdownPreview = false
    @State var showsAgentPanel = true
    @State var showsTaskOutputPanel = true
    @State var showsFindBar = true

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
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.save)) { _ in
            saveFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.find)) { _ in
            showsFindBar = true
        }
        .onChange(of: editor.selectedTaskPlan?.taskID) { _, taskID in
            if taskID != nil {
                showsTaskOutputPanel = true
            }
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

            if showsTaskOutputPanel, let plan = editor.selectedTaskPlan {
                Divider()
                taskOutputPanel(plan)
                    .frame(minHeight: 160, idealHeight: 220, maxHeight: 300)
            }
        }
    }
}
