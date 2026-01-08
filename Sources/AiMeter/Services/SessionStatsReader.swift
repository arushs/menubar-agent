import Foundation
import CommonCrypto

// MARK: - Cache Entry

private struct CacheEntry: Sendable {
    let stats: SessionStats
    let directoryModDate: Date
    let cachedAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(cachedAt) > 60 // 1 minute expiration
    }
}

// MARK: - Thread-Safe Cache

private final class StatsCache: @unchecked Sendable {
    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()

    func get(key: String, currentModDate: Date?) -> SessionStats? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[key] else { return nil }

        // Check if entry is expired
        if entry.isExpired {
            cache.removeValue(forKey: key)
            return nil
        }

        // Check if directory has been modified since we cached
        if let currentModDate = currentModDate, currentModDate > entry.directoryModDate {
            cache.removeValue(forKey: key)
            return nil
        }

        return entry.stats
    }

    func set(key: String, stats: SessionStats, modDate: Date) {
        lock.lock()
        defer { lock.unlock() }

        cache[key] = CacheEntry(
            stats: stats,
            directoryModDate: modDate,
            cachedAt: Date()
        )
    }

    func invalidateExpired() {
        lock.lock()
        defer { lock.unlock() }

        let expiredKeys = cache.filter { $0.value.isExpired }.map { $0.key }
        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

// MARK: - SessionStatsReader

final class SessionStatsReader: Sendable {
    static let shared = SessionStatsReader()

    // Static JSONDecoder instance - thread-safe for decoding
    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private let cache = StatsCache()

    private init() {}

    func getStats(for agent: Agent) -> SessionStats? {
        switch agent.type {
        case .opencode:
            return getOpenCodeStats(workingDirectory: agent.workingDirectory)
        default:
            return nil
        }
    }

    /// Clears all cached stats
    func clearCache() {
        cache.clear()
    }

    /// Removes expired cache entries
    func cleanupExpiredCache() {
        cache.invalidateExpired()
    }

    // MARK: - OpenCode

    private func getOpenCodeStats(workingDirectory: String) -> SessionStats? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let storageDir = "\(homeDir)/.local/share/opencode/storage"

        // Get project hash from working directory
        guard let projectHash = getProjectHash(for: workingDirectory, storageDir: storageDir) else {
            return nil
        }

        // Find the most recent session for this project
        let sessionDir = "\(storageDir)/session/\(projectHash)"
        guard let sessionFile = getMostRecentSession(in: sessionDir) else {
            return nil
        }

        // Read session info
        guard let sessionData = try? Data(contentsOf: URL(fileURLWithPath: sessionFile)),
              let session = try? Self.jsonDecoder.decode(OpenCodeSession.self, from: sessionData) else {
            return nil
        }

        // Get messages for this session to sum up tokens
        let messageDir = "\(storageDir)/message/\(session.id)"

        // Create cache key from working directory and session ID
        let cacheKey = "\(workingDirectory):\(session.id)"

        // Get directory modification date
        let dirModDate = getDirectoryModificationDate(messageDir)

        // Check cache first
        if let cachedStats = cache.get(key: cacheKey, currentModDate: dirModDate) {
            var stats = cachedStats
            stats.sessionTitle = session.title
            return stats
        }

        // Cache miss - read all messages
        let stats = sumMessageStats(in: messageDir, sessionTitle: session.title)

        // Store in cache
        if let modDate = dirModDate {
            cache.set(key: cacheKey, stats: stats, modDate: modDate)
        }

        return stats
    }

    private func getDirectoryModificationDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    private func getProjectHash(for workingDirectory: String, storageDir: String) -> String? {
        let projectDir = "\(storageDir)/project"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: projectDir) else {
            return nil
        }

        // Check each project file to find matching directory
        for file in contents where file.hasSuffix(".json") {
            let filePath = "\(projectDir)/\(file)"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
               let project = try? Self.jsonDecoder.decode(OpenCodeProject.self, from: data),
               project.worktree == workingDirectory {
                return project.id
            }
        }

        // Fallback: hash the directory path (OpenCode uses SHA1)
        return workingDirectory.sha1Hash
    }

    private func getMostRecentSession(in directory: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        let sessionFiles = contents
            .filter { $0.hasPrefix("ses_") && $0.hasSuffix(".json") }
            .map { "\(directory)/\($0)" }
            .sorted { file1, file2 in
                let date1 = (try? FileManager.default.attributesOfItem(atPath: file1)[.modificationDate] as? Date) ?? Date.distantPast
                let date2 = (try? FileManager.default.attributesOfItem(atPath: file2)[.modificationDate] as? Date) ?? Date.distantPast
                return date1 > date2
            }

        return sessionFiles.first
    }

    private func sumMessageStats(in directory: String, sessionTitle: String?) -> SessionStats {
        var stats = SessionStats()
        stats.sessionTitle = sessionTitle

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return stats
        }

        for file in contents where file.hasPrefix("msg_") && file.hasSuffix(".json") {
            let filePath = "\(directory)/\(file)"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
               let message = try? Self.jsonDecoder.decode(OpenCodeMessage.self, from: data) {
                if let tokens = message.tokens {
                    stats.inputTokens += tokens.input
                    stats.outputTokens += tokens.output
                    stats.cacheReadTokens += tokens.cache?.read ?? 0
                    stats.cacheWriteTokens += tokens.cache?.write ?? 0
                }
                stats.cost += message.cost ?? 0
            }
        }

        return stats
    }
}

// MARK: - OpenCode JSON Models

private struct OpenCodeSession: Decodable {
    let id: String
    let title: String?
    let directory: String?
}

private struct OpenCodeProject: Decodable {
    let id: String
    let worktree: String  // OpenCode uses "worktree" not "path"
}

private struct OpenCodeMessage: Decodable {
    let tokens: TokenUsage?
    let cost: Double?

    struct TokenUsage: Decodable {
        let input: Int
        let output: Int
        let cache: CacheUsage?
    }

    struct CacheUsage: Decodable {
        let read: Int
        let write: Int
    }
}

// MARK: - String Extension for SHA1

extension String {
    var sha1Hash: String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count: 20)

        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
