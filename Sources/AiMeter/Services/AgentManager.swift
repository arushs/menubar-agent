import Foundation
import Combine
import AppKit

@MainActor
class AgentManager: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var hasActiveAgents: Bool = false
    @Published var hasWorkingAgents: Bool = false

    private var timer: Timer?
    private let cpuThreshold: Double = 5.0 // CPU usage above this = "active/working"

    static let shared = AgentManager()

    private init() {
        startMonitoring()
    }

    func startMonitoring() {
        // Initial scan
        Task {
            await refreshAgents()
        }

        // Poll every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAgents()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refreshAgents() async {
        let processInfos = await Task.detached {
            ProcessMonitor.shared.findAgentProcesses()
        }.value

        // Build a set of current PIDs for quick lookup
        let currentPIDs = Set(processInfos.map { $0.pid })

        // Remove agents that are no longer running (in reverse to avoid index shifting)
        for index in agents.indices.reversed() {
            if !currentPIDs.contains(agents[index].pid) {
                agents.remove(at: index)
            }
        }

        // Build a dictionary of existing agents by PID for O(1) lookup
        var existingAgentIndices: [Int32: Int] = [:]
        for (index, agent) in agents.enumerated() {
            existingAgentIndices[agent.pid] = index
        }

        // Track if we need to re-sort (only when new agents are added)
        var needsSort = false

        for info in processInfos {
            if let existingIndex = existingAgentIndices[info.pid] {
                // Update existing agent in-place
                agents[existingIndex].cpuUsage = info.cpuUsage
                agents[existingIndex].status = info.cpuUsage > cpuThreshold ? .active : .idle
                agents[existingIndex].sessionStats = SessionStatsReader.shared.getStats(for: agents[existingIndex])
            } else {
                // Create new agent only for genuinely new processes
                var agent = Agent(
                    id: UUID(),
                    pid: info.pid,
                    type: info.agentType,
                    workingDirectory: info.workingDirectory,
                    startTime: info.startTime,
                    status: info.cpuUsage > cpuThreshold ? .active : .idle,
                    cpuUsage: info.cpuUsage,
                    sessionStats: nil,
                    tty: info.tty
                )
                agent.sessionStats = SessionStatsReader.shared.getStats(for: agent)
                agents.append(agent)
                needsSort = true
            }
        }

        // Only sort when new agents were added
        if needsSort {
            agents.sort { $0.startTime > $1.startTime }
        }

        hasActiveAgents = !agents.isEmpty
        hasWorkingAgents = agents.contains { $0.status == .active }
    }

    // MARK: - Actions

    func openInTerminal(_ agent: Agent) {
        // Detect which terminal app owns this TTY and focus it
        if let tty = agent.tty {
            // Try iTerm2 first
            if tryFocusiTerm(tty: tty) { return }
            // Try Terminal.app
            if tryFocusTerminalApp(tty: tty) { return }
            // Try Ghostty
            if tryFocusGhostty(tty: tty) { return }
        }
        
        // Fallback: open in default/available terminal
        openNewTerminal(at: agent.workingDirectory)
    }
    
    private func tryFocusiTerm(tty: String) -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "iTerm2") then return false
        end tell
        tell application "iTerm"
            activate
            set targetTTY to "\(tty)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is targetTTY then
                            select s
                            select t
                            set index of w to 1
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            if error == nil && result.booleanValue {
                return true
            }
        }
        return false
    }
    
    private func tryFocusTerminalApp(tty: String) -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "Terminal") then return false
        end tell
        tell application "Terminal"
            activate
            set targetTTY to "\(tty)"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is targetTTY then
                        set selected of t to true
                        set index of w to 1
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            if error == nil && result.booleanValue {
                return true
            }
        }
        return false
    }
    
    private func tryFocusGhostty(tty: String) -> Bool {
        // Ghostty doesn't have AppleScript support yet, but we can activate it
        // and it will show the most recent window
        let script = """
        tell application "System Events"
            if not (exists process "Ghostty") then return false
        end tell
        tell application "Ghostty" to activate
        return true
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            if error == nil && result.booleanValue {
                return true
            }
        }
        return false
    }
    
    private func openNewTerminal(at directory: String) {
        // Try iTerm2 first, then Terminal, then Ghostty
        let itermScript = """
        tell application "System Events"
            if exists process "iTerm2" then
                tell application "iTerm"
                    activate
                    create window with default profile
                    tell current session of current window
                        write text "cd '\(directory)'"
                    end tell
                end tell
                return true
            end if
        end tell
        return false
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: itermScript) {
            let result = scriptObject.executeAndReturnError(&error)
            if error == nil && result.booleanValue {
                return
            }
        }
        
        // Try Ghostty
        let ghosttyScript = """
        tell application "System Events"
            if exists process "Ghostty" then
                tell application "Ghostty" to activate
                -- Ghostty doesn't have full AppleScript, open via shell
                do shell script "open -a Ghostty"
                return true
            end if
        end tell
        return false
        """
        
        if let scriptObject = NSAppleScript(source: ghosttyScript) {
            let result = scriptObject.executeAndReturnError(&error)
            if error == nil && result.booleanValue {
                return
            }
        }
        
        // Fallback to Terminal.app
        let terminalScript = """
        tell application "Terminal"
            activate
            do script "cd '\(directory)'"
        end tell
        """
        
        if let scriptObject = NSAppleScript(source: terminalScript) {
            scriptObject.executeAndReturnError(&error)
        }
    }

    func copyPath(_ agent: Agent) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(agent.workingDirectory, forType: .string)
    }

    func killAgent(_ agent: Agent) {
        let task = Process()
        task.launchPath = "/bin/kill"
        task.arguments = ["-15", String(agent.pid)] // SIGTERM for graceful shutdown

        do {
            try task.run()
            task.waitUntilExit()

            // Refresh after killing
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                await refreshAgents()
            }
        } catch {
            print("Failed to kill process: \(error)")
        }
    }
}
