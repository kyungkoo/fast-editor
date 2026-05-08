import SwiftUI

struct AgentPanel: View {
    @ObservedObject var editor: EditorCoreBridge
    @StateObject private var model = AgentPanelModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            Divider()
            transcript
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.refreshProviders()
        }
    }

    private var header: some View {
        HStack {
            Text("Agent Panel")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                model.refreshProviders()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh providers")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.availableProviders.isEmpty {
                Label("No providers found", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Provider", selection: selectedProviderBinding) {
                    ForEach(model.availableProviders) { provider in
                        Text(provider.displayName).tag(Optional(provider.id))
                    }
                }
                .pickerStyle(.menu)
            }

            TextEditor(text: $model.prompt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 120)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                }

            HStack {
                Button(model.isRunning ? "Stop" : "Send File") {
                    if model.isRunning {
                        model.cancel()
                    } else {
                        model.sendCurrentFile(fileURL: editor.fileURL, text: editor.text)
                    }
                }
                .disabled(!model.isRunning && (!editor.hasOpenBuffer || model.selectedProvider == nil))

                Spacer()

                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
    }

    private var transcript: some View {
        ScrollView {
            Text(model.transcript.isEmpty ? "Idle" : model.transcript)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private var selectedProviderBinding: Binding<AgentProviderID?> {
        Binding(
            get: { model.selectedProvider?.id },
            set: { model.selectedProviderID = $0 }
        )
    }
}
