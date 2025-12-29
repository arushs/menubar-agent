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

        var newAgents: [Agent] = []

        for info in processInfos {
            // Check if we already have this agent (by PID)
            if let existingIndex = agents.firstIndex(where: { $0.pid == info.pid }) {
                var existing = agents[existingIndex]
                existing.cpuUsage = info.cpuUsage
                existing.status = info.cpuUsage > cpuThreshold ? .active : .idle
                // Refresh stats
                existing.sessionStats = SessionStatsReader.shared.getStats(for: existing)
                newAgents.append(existing)
            } else {
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
                newAgents.append(agent)
            }
        }

        agents = newAgents.sorted { $0.startTime > $1.startTime }
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
