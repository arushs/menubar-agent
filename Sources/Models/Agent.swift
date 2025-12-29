import Foundation

enum AgentType: String, CaseIterable, Identifiable {
    case claudeCode = "claude"
    case codex = "codex"
    case aider = "aider"
    case cursorAgent = "cursor-agent"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .aider: return "Aider"
        case .cursorAgent: return "Cursor Agent"
        }
    }

    var processNames: [String] {
        switch self {
        case .claudeCode: return ["claude"]
        case .codex: return ["codex"]
        case .aider: return ["aider"]
        case .cursorAgent: return ["cursor-agent", "cursor"]
        }
    }
}

enum AgentStatus: Equatable {
    case idle
    case active

    var color: String {
        switch self {
        case .idle: return "green"
        case .active: return "yellow"
        }
    }
}

struct Agent: Identifiable, Equatable {
    let id: UUID
    let pid: Int32
    let type: AgentType
    let workingDirectory: String
    let startTime: Date
    var status: AgentStatus
    var cpuUsage: Double

    var projectName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    var runningTime: String {
        let interval = Date().timeIntervalSince(startTime)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)

        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.pid == rhs.pid && lhs.type == rhs.type
    }
}
