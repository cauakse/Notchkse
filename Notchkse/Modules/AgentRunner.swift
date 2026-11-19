import AppKit
import Observation

/// Agentes de IA de linha de comando que o Notchkse sabe chamar.
struct AgentDefinition: Identifiable, Hashable {
    let id: String        // nome do executável
    let name: String
    let symbol: String

    static let known: [AgentDefinition] = [
        .init(id: "claude", name: "Claude Code", symbol: "sparkle"),
        .init(id: "codex", name: "Codex", symbol: "chevron.left.forwardslash.chevron.right"),
        .init(id: "gemini", name: "Gemini CLI", symbol: "diamond"),
        .init(id: "opencode", name: "OpenCode", symbol: "terminal"),
        .init(id: "cursor-agent", name: "Cursor Agent", symbol: "cursorarrow.rays"),
        .init(id: "ollama", name: "Ollama", symbol: "cpu"),
    ]

    func arguments(prompt: String, continuing: Bool, settings: AppSettings) -> [String] {
        switch id {
        case "claude": (continuing ? ["--continue"] : []) + ["-p", prompt]
        case "codex": ["exec", "--skip-git-repo-check", prompt]
        case "gemini": ["-p", prompt]
        case "opencode": ["run", prompt]
        case "cursor-agent": ["-p", prompt]
        case "ollama": ["run", settings.ollamaModel, prompt]
        default: [prompt]
        }
    }

    var supportsContinue: Bool { id == "claude" }
}

@Observable
final class AgentRunner {
    private(set) var available: [AgentDefinition] = []
    private(set) var detected = false
    private(set) var output = ""
    private(set) var isRunning = false
    private(set) var lastPrompt = ""
    private(set) var runningAgent: AgentDefinition?

    @ObservationIgnored var onFinish: ((AgentDefinition) -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var hasConversation = false

    /// Descobre quais CLIs estão instaladas (uma vez; dá para forçar de novo).
    func detect(force: Bool = false) {
        guard force || !detected else { return }
        let names = AgentDefinition.known.map(\.id)
        DispatchQueue.global(qos: .utility).async {
            let script = names.map { "command -v \($0) >/dev/null 2>&1 && echo \($0)" }.joined(separator: "; ")
            let out = Shell.run("/bin/zsh", ["-lc", script + "; true"]) ?? ""
            let found = Set(out.split(separator: "\n").map(String.init))
            DispatchQueue.main.async { [weak self] in
                self?.available = AgentDefinition.known.filter { found.contains($0.id) }
                self?.detected = true
            }
        }
    }

    func run(prompt: String, agent: AgentDefinition, settings: AppSettings, continuing: Bool) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        let resume = continuing && hasConversation && agent.supportsContinue
        output = ""
        lastPrompt = trimmed
        isRunning = true
        runningAgent = agent

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // `exec "$@"` evita qualquer problema de escape: o prompt vai como argumento puro.
        process.arguments = ["-lc", "exec \"$@\"", "notchkse", agent.id]
            + agent.arguments(prompt: trimmed, continuing: resume, settings: settings)
        process.environment = Shell.environment
        let dir = URL(fileURLWithPath: (settings.agentWorkingDirectory as NSString).expandingTildeInPath)
        process.currentDirectoryURL = FileManager.default.fileExists(atPath: dir.path)
            ? dir : URL(fileURLWithPath: NSHomeDirectory())
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in self?.append(chunk.strippingANSI) }
        }
        process.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRunning = false
                self.hasConversation = true
                self.process = nil
                if self.output.isEmpty { self.output = "(sem resposta)" }
                self.onFinish?(agent)
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            isRunning = false
            output = "Não foi possível iniciar \(agent.name): \(error.localizedDescription)"
        }
    }

    func stop() {
        process?.terminate()
    }

    func newConversation() {
        stop()
        hasConversation = false
        output = ""
        lastPrompt = ""
    }

    private func append(_ chunk: String) {
        output += chunk
        if output.count > 200_000 { output = String(output.suffix(150_000)) }
    }
}
