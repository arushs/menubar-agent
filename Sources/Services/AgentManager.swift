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
            guard let agentType = identifyAgentType(from: info.name) else { continue }

            // Check if we already have this agent (by PID)
            if let existingIndex = agents.firstIndex(where: { $0.pid == info.pid }) {
                var existing = agents[existingIndex]
                existing.cpuUsage = info.cpuUsage
                existing.status = info.cpuUsage > cpuThreshold ? .active : .idle
                newAgents.append(existing)
            } else {
                let agent = Agent(
                    id: UUID(),
                    pid: info.pid,
                    type: agentType,
                    workingDirectory: info.workingDirectory,
                    startTime: info.startTime,
                    status: info.cpuUsage > cpuThreshold ? .active : .idle,
                    cpuUsage: info.cpuUsage
                )
                newAgents.append(agent)
            }
        }

        agents = newAgents.sorted { $0.startTime > $1.startTime }
        hasActiveAgents = !agents.isEmpty
        hasWorkingAgents = agents.contains { $0.status == .active }
    }

    private func identifyAgentType(from processName: String) -> AgentType? {
        let lowercased = processName.lowercased()
        for type in AgentType.allCases {
            for name in type.processNames {
                if lowercased.contains(name) {
                    return type
                }
            }
        }
        return nil
    }

    // MARK: - Actions

    func openInTerminal(_ agent: Agent) {
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(agent.workingDirectory)'"
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
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
