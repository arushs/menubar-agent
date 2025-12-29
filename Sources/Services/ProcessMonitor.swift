import Foundation

struct ProcessInfo {
    let pid: Int32
    let name: String
    let command: String
    let workingDirectory: String
    let startTime: Date
    let cpuUsage: Double
}

class ProcessMonitor {
    static let shared = ProcessMonitor()

    private init() {}

    func findAgentProcesses() -> [ProcessInfo] {
        var processes: [ProcessInfo] = []

        let allProcessNames = AgentType.allCases.flatMap { $0.processNames }

        for processName in allProcessNames {
            let found = findProcesses(matching: processName)
            processes.append(contentsOf: found)
        }

        return processes
    }

    private func findProcesses(matching name: String) -> [ProcessInfo] {
        var results: [ProcessInfo] = []

        // Use ps to find processes
        let psOutput = shell("ps -eo pid,comm,lstart,pcpu")
        let lines = psOutput.split(separator: "\n").dropFirst() // Skip header

        for line in lines {
            let lineStr = String(line)
            if lineStr.lowercased().contains(name.lowercased()) {
                if let info = parseProcessLine(lineStr, searchName: name) {
                    results.append(info)
                }
            }
        }

        return results
    }

    private func parseProcessLine(_ line: String, searchName: String) -> ProcessInfo? {
        let components = line.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count >= 8 else { return nil }

        guard let pid = Int32(components[0]) else { return nil }
        let processName = String(components[1])

        // Parse lstart (e.g., "Sun Dec 29 10:30:00 2024")
        // lstart has format: Day Mon DD HH:MM:SS YYYY
        let dateComponents = components[2...6]
        let dateString = dateComponents.joined(separator: " ")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let startTime = dateFormatter.date(from: dateString) ?? Date()

        // CPU usage is the last component
        let cpuUsage = Double(components.last ?? "0") ?? 0.0

        // Get working directory using lsof
        let cwd = getWorkingDirectory(pid: pid)

        return ProcessInfo(
            pid: pid,
            name: processName,
            command: processName,
            workingDirectory: cwd,
            startTime: startTime,
            cpuUsage: cpuUsage
        )
    }

    private func getWorkingDirectory(pid: Int32) -> String {
        // Use lsof to get the current working directory
        let output = shell("lsof -p \(pid) -Fn 2>/dev/null | grep '^n/' | grep 'cwd' || lsof -p \(pid) -Fn 2>/dev/null | head -5")

        // Try to find cwd from lsof output
        let lines = output.split(separator: "\n")
        for line in lines {
            let lineStr = String(line)
            if lineStr.hasPrefix("n/") {
                return String(lineStr.dropFirst()) // Remove 'n' prefix
            }
        }

        // Fallback: try pwdx equivalent on macOS
        let pwdOutput = shell("lsof -a -p \(pid) -d cwd -Fn 2>/dev/null")
        let pwdLines = pwdOutput.split(separator: "\n")
        for line in pwdLines {
            let lineStr = String(line)
            if lineStr.hasPrefix("n") {
                return String(lineStr.dropFirst())
            }
        }

        return "~"
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
