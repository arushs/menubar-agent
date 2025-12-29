import Foundation

struct AgentPattern {
    let displayName: String
    // Patterns to match in command args (checked in order, first match wins)
    let patterns: [String]
    // Patterns that indicate false positives
    let excludePatterns: [String]
    // If true, requires the pattern to be a standalone binary name (not substring)
    let requireExactBinary: Bool
    
    init(_ displayName: String, patterns: [String], exclude: [String] = [], exactBinary: Bool = false) {
        self.displayName = displayName
        self.patterns = patterns
        self.excludePatterns = exclude
        self.requireExactBinary = exactBinary
    }
}

enum AgentType: String, CaseIterable, Identifiable {
    case opencode = "opencode"
    case claudeCode = "claude"
    case codex = "codex"
    case aider = "aider"
    case goose = "goose"
    case cline = "cline"
    case amplecode = "amplecode"
    case mentat = "mentat"
    case gptEngineer = "gpt-engineer"
    case amazonQ = "amazon-q"
    case geminiCli = "gemini-cli"
    case githubCopilot = "github-copilot"

    var id: String { rawValue }

    var displayName: String {
        pattern.displayName
    }

    var pattern: AgentPattern {
        switch self {
        case .opencode:
            return AgentPattern("OpenCode",
                patterns: ["opencode", "opencode-ai"],
                exclude: ["opencode-darwin-arm64"]) // Exclude the internal binary path noise
        case .claudeCode:
            return AgentPattern("Claude Code",
                patterns: ["claude"],
                exclude: ["claudeservice", "claude.ai", "clauded"])
        case .codex:
            return AgentPattern("Codex CLI",
                patterns: ["codex", "@openai/codex"],
                exclude: ["codex-agent-runtime"])
        case .aider:
            return AgentPattern("Aider",
                patterns: ["aider", "aider-chat"],
                exclude: [])
        case .goose:
            return AgentPattern("Goose",
                patterns: ["/goose", "goose-ai", "block/goose"],
                exclude: ["mongoose", "goose.py"],
                exactBinary: true)
        case .cline:
            return AgentPattern("Cline",
                patterns: ["cline", "cline-cli"],
                exclude: ["clineservice"])
        case .amplecode:
            return AgentPattern("Amplecode",
                patterns: ["amplecode"],
                exclude: ["AMPLibrary", "AMPArtwork"])
        case .mentat:
            return AgentPattern("Mentat",
                patterns: ["mentat"],
                exclude: [])
        case .gptEngineer:
            return AgentPattern("GPT Engineer",
                patterns: ["gpt-engineer", "gptengineer", "gpt_engineer"],
                exclude: [])
        case .amazonQ:
            return AgentPattern("Amazon Q",
                patterns: ["amazon-q", "q-cli", "/q "],
                exclude: [])
        case .geminiCli:
            return AgentPattern("Gemini CLI",
                patterns: ["gemini-cli", "@anthropic/gemini"],
                exclude: [])
        case .githubCopilot:
            return AgentPattern("GitHub Copilot CLI",
                patterns: ["github-copilot", "copilot-cli", "@github/copilot"],
                exclude: ["copilot.vim", "copilot.lua"])
        }
    }
    
    // Quick search patterns for initial grep filter (combined for efficiency)
    static var grepPattern: String {
        // Use broader patterns for grep, we'll filter more precisely in Swift
        return "opencode|claude|codex|aider|goose|cline|amplecode|mentat|gpt-engineer|amazon-q|q-cli|gemini-cli|copilot"
    }
}

enum AgentStatus: Equatable {
    case idle
    case active
}

struct SessionStats {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var cost: Double = 0
    var sessionTitle: String?
    
    var totalTokens: Int {
        inputTokens + outputTokens
    }
    
    var formattedTokens: String {
        if totalTokens == 0 { return "" }
        if totalTokens >= 1000 {
            return String(format: "%.1fk tokens", Double(totalTokens) / 1000.0)
        }
        return "\(totalTokens) tokens"
    }
    
    var formattedCost: String {
        if cost == 0 { return "" }
        return String(format: "$%.2f", cost)
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
    var sessionStats: SessionStats?
    var tty: String?

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
