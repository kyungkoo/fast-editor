import FastEditorModels
import SwiftUI

extension ContentView {
    func taskPreview(_ plan: TaskExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.commandDisplay)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)

            HStack {
                Button(editor.isTaskRunning ? "Stop" : "Run") {
                    if editor.isTaskRunning {
                        editor.stopRunningTask()
                    } else {
                        editor.runSelectedTask()
                    }
                }

                Button("Output") {
                    showsTaskOutputPanel = true
                }

                Spacer()

                Text(editor.taskStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    func taskOutputPanel(_ plan: TaskExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Task Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(plan.commandDisplay)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(editor.taskStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button("Hide") {
                    showsTaskOutputPanel = false
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            HSplitView {
                ScrollView {
                    Text(editor.taskOutput.isEmpty ? "No output yet" : editor.taskOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(editor.taskOutput.isEmpty ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minWidth: 260)
                .background(Color(nsColor: .textBackgroundColor))

                if !editor.taskDiagnostics.isEmpty {
                    ScrollView {
                        diagnosticsList
                            .padding(12)
                    }
                    .frame(minWidth: 220, idealWidth: 280)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
            }
        }
    }

    var diagnosticsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diagnostics")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(editor.taskDiagnostics) { diagnostic in
                Button {
                    editor.navigateToDiagnostic(diagnostic)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(diagnostic.locationDisplay, systemImage: diagnosticIcon(for: diagnostic.severity))
                            .foregroundStyle(diagnosticColor(for: diagnostic.severity))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(diagnostic.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Open \(diagnostic.locationDisplay)")
            }
        }
    }

    func taskIcon(for kind: TaskKind) -> String {
        switch kind {
        case .build:
            "hammer"
        case .run:
            "play"
        case .test:
            "checklist"
        case .script:
            "terminal"
        case .other:
            "gearshape"
        }
    }

    func diagnosticIcon(for severity: TaskDiagnosticSeverity) -> String {
        switch severity {
        case .error:
            "xmark.octagon"
        case .warning:
            "exclamationmark.triangle"
        case .note:
            "info.circle"
        }
    }

    func diagnosticColor(for severity: TaskDiagnosticSeverity) -> Color {
        switch severity {
        case .error:
            .red
        case .warning:
            .orange
        case .note:
            .secondary
        }
    }
}
