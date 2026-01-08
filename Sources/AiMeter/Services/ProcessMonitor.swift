import Foundation

struct ProcessInfo {
    let pid: Int32
    let ppid: Int32
    let name: String
    let command: String
    let workingDirectory: String
    let startTime: Date
    let cpuUsage: Double
    let agentType: AgentType
    let tty: String?
}

final class ProcessMonitor: Sendable {
    static let shared = ProcessMonitor()

    // Static DateFormatter to avoid expensive recreation on each call
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private init() {}

    func findAgentProcesses() -> [ProcessInfo] {
        // Single ps call with grep for broad initial filter - include ppid for deduplication
        let psOutput = shell("ps -eo pid,ppid,lstart,pcpu,args | grep -iE '\(AgentType.grepPattern)' | grep -v grep | grep -v aimeter")

        let lines = psOutput.split(separator: "\n")
        guard !lines.isEmpty else { return [] }

        // Parse and identify processes
        var pidToProcess: [Int32: (line: String, type: AgentType, ppid: Int32)] = [:]

        for line in lines {
            let lineStr = String(line).trimmingCharacters(in: .whitespaces)
            let components = lineStr.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 9,
                  let pid = Int32(components[0]),
                  let ppid = Int32(components[1]) else { continue }

            // Extract full command args (index 8 onwards, since we added ppid)
            let args = components[8...].joined(separator: " ")

            // Try to identify which agent this is
            if let agentType = identifyAgent(args: args) {
                pidToProcess[pid] = (lineStr, agentType, ppid)
            }
        }

        guard !pidToProcess.isEmpty else { return [] }

        // Get all detected PIDs for parent filtering
        let detectedPids = Set(pidToProcess.keys)

        // Filter out processes whose parent is also a detected agent (keep only top-level)
        let topLevelPids = pidToProcess.filter { !detectedPids.contains($0.value.ppid) }

        guard !topLevelPids.isEmpty else { return [] }

        // Batch lsof call for all PIDs at once
        let pidList = topLevelPids.keys.map(String.init).joined(separator: ",")
        let cwdMap = batchGetWorkingDirectories(pids: pidList)
        let ttyMap = batchGetTTYs(pids: pidList)

        // Parse all processes using static dateFormatter
        var processes: [ProcessInfo] = []
        for (pid, data) in topLevelPids {
            let cwd = cwdMap[pid] ?? "~"
            if let info = parseProcessLine(data.line, pid: pid, ppid: data.ppid, agentType: data.type, cwd: cwd, tty: ttyMap[pid]) {
                processes.append(info)
            }
        }

        return processes
    }

    private func identifyAgent(args: String) -> AgentType? {
        let lowerArgs = args.lowercased()

        // Check each agent type's patterns
        for agentType in AgentType.allCases {
            let pattern = agentType.pattern

            // First check exclusions
            var excluded = false
            for excludePattern in pattern.excludePatterns {
                if lowerArgs.contains(excludePattern.lowercased()) {
                    excluded = true
                    break
                }
            }
            if excluded { continue }

            // Check for matches
            for matchPattern in pattern.patterns {
                if pattern.requireExactBinary {
                    // Check if it's an exact binary name match
                    if isBinaryMatch(args: args, binary: matchPattern) {
                        return agentType
                    }
                } else {
                    if lowerArgs.contains(matchPattern.lowercased()) {
                        return agentType
                    }
                }
            }
        }

        return nil
    }

    private func isBinaryMatch(args: String, binary: String) -> Bool {
        // Extract the binary name from the command
        // Handle cases like "/usr/local/bin/goose" or "python -m goose"
        let components = args.split(separator: " ")
        for component in components {
            let path = String(component)
            let binaryName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            if binaryName == binary.lowercased() {
                return true
            }
        }
        return false
    }

    private func parseProcessLine(_ line: String, pid: Int32, ppid: Int32, agentType: AgentType, cwd: String, tty: String?) -> ProcessInfo? {
        let components = line.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count >= 9 else { return nil }

        // Parse lstart (indices 2-6, since ppid is at index 1)
        let dateComponents = components[2...6]
        let dateString = dateComponents.joined(separator: " ")
        let startTime = Self.dateFormatter.date(from: dateString) ?? Date()

        // CPU usage at index 7
        let cpuUsage = Double(components[7]) ?? 0.0

        // Args start at index 8
        let args = components[8...].joined(separator: " ")
        let processName = URL(fileURLWithPath: String(components[8])).lastPathComponent

        return ProcessInfo(
            pid: pid,
            ppid: ppid,
            name: processName,
            command: args,
            workingDirectory: cwd,
            startTime: startTime,
            cpuUsage: cpuUsage,
            agentType: agentType,
            tty: tty
        )
    }

    private func batchGetWorkingDirectories(pids: String) -> [Int32: String] {
        let output = shell("lsof -a -d cwd -Fpn -p \(pids) 2>/dev/null")

        var result: [Int32: String] = [:]
        var currentPid: Int32?

        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            if lineStr.hasPrefix("p") {
                currentPid = Int32(lineStr.dropFirst())
            } else if lineStr.hasPrefix("n"), let pid = currentPid {
                result[pid] = String(lineStr.dropFirst())
            }
        }

        return result
    }

    private func batchGetTTYs(pids: String) -> [Int32: String] {
        // Get TTY for each process
        let output = shell("ps -o pid=,tty= -p \(pids) 2>/dev/null")

        var result: [Int32: String] = [:]
        for line in output.split(separator: "\n") {
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            if components.count >= 2,
               let pid = Int32(components[0]) {
                let tty = String(components[1])
                if tty != "??" && !tty.isEmpty {
                    result[pid] = "/dev/\(tty)"
                }
            }
        }

        return result
    }

    func getCPUUsage(pid: Int32) -> Double {
        let output = shell("ps -p \(pid) -o %cpu= 2>/dev/null")
        return Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
    }

    private func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.standardInput = nil

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
