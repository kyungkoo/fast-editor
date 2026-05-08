import Foundation

@MainActor
final class AgentPanelModel: ObservableObject {
    @Published private(set) var providers: [AgentProvider] = []
    @Published var selectedProviderID: AgentProviderID?
    @Published var prompt = ""
    @Published private(set) var transcript = ""
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Detecting providers"

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    var availableProviders: [AgentProvider] {
        providers.filter(\.available)
    }

    var selectedProvider: AgentProvider? {
        guard let selectedProviderID else {
            return availableProviders.first
        }

        return availableProviders.first { $0.id == selectedProviderID } ?? availableProviders.first
    }

    func refreshProviders() {
        let value = feDetectAgentProviders()
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            providers = []
            selectedProviderID = nil
            statusText = "Provider detection failed"
            return
        }

        let data = Data(bytes: pointer, count: value.len)
        do {
            providers = try JSONDecoder().decode([AgentProvider].self, from: data)
            if let selectedProviderID,
               !availableProviders.contains(where: { $0.id == selectedProviderID }) {
                self.selectedProviderID = availableProviders.first?.id
            } else if selectedProviderID == nil {
                selectedProviderID = availableProviders.first?.id
            }
            statusText = availableProviders.isEmpty ? "No providers found" : "Ready"
        } catch {
            providers = []
            selectedProviderID = nil
            statusText = "Provider decode failed: \(error.localizedDescription)"
        }
    }

    func sendCurrentFile(fileURL: URL?, text: String) {
        guard !isRunning, let provider = selectedProvider, let executablePath = provider.executablePath else {
            return
        }

        let request = buildRequest(fileURL: fileURL, text: text)
        let invocation = invocationForProvider(provider, request: request)
        transcript = ""
        appendTranscript("→ \(provider.displayName)\n\n")
        isRunning = true
        statusText = "Running \(provider.displayName)"

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()

        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = invocation.arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            Task { @MainActor in
                self?.appendTranscript(String(decoding: data, as: UTF8.self))
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            Task { @MainActor in
                self?.appendTranscript(String(decoding: data, as: UTF8.self))
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.finishProcess(exitCode: process.terminationStatus)
            }
        }

        do {
            try process.run()
            if let stdin = invocation.stdin {
                inputPipe.fileHandleForWriting.write(Data(stdin.utf8))
            }
            try? inputPipe.fileHandleForWriting.close()
        } catch {
            finishProcess(exitCode: nil)
            appendTranscript("Failed to launch \(provider.displayName): \(error.localizedDescription)\n")
        }
    }

    func cancel() {
        process?.terminate()
    }

    private func buildRequest(fileURL: URL?, text: String) -> String {
        let path = fileURL?.path ?? "Untitled"
        let userPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = userPrompt.isEmpty
            ? "Review this file and summarize useful observations. Do not edit files or run commands."
            : userPrompt

        return """
        \(instruction)

        Current file: \(path)

        ```text
        \(text)
        ```
        """
    }

    private func invocationForProvider(
        _ provider: AgentProvider,
        request: String
    ) -> (arguments: [String], stdin: String?) {
        switch provider.id {
        case .codex:
            return (
                ["exec", "--sandbox", "read-only", "--color", "never", "-"],
                request
            )
        case .claude:
            return (
                ["--print", "--permission-mode", "plan"],
                request
            )
        case .gemini:
            return (
                ["--prompt", "Use the context from stdin to answer the request.", "--approval-mode", "plan"],
                request
            )
        }
    }

    private func appendTranscript(_ text: String) {
        transcript += text
    }

    private func finishProcess(exitCode: Int32?) {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        errorPipe = nil
        isRunning = false

        if let exitCode {
            statusText = exitCode == 0 ? "Completed" : "Exited with status \(exitCode)"
        } else {
            statusText = "Launch failed"
        }
    }
}
