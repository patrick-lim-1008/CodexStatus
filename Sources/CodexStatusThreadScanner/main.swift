import Foundation

struct ThreadSummary: Codable {
    let id: String
    let name: String
    let cwd: String
    let updatedAt: Double
    let statusType: String
    let activeFlags: [String]
    let lifecycle: String
    let lifecycleUpdatedAt: Double
}

struct UsageWindow: Codable {
    let name: String
    let remainingPercent: Double
    let resetsAt: Double
}

struct ScanResult: Codable {
    let threads: [ThreadSummary]
    let usageWindows: [UsageWindow]?
}

private struct RolloutState {
    let lifecycle: String
    let updatedAt: Double
}

private func rolloutStates(for threadIDs: Set<String>) -> [String: RolloutState] {
    guard !threadIDs.isEmpty else { return [:] }
    let sessionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)
    guard let enumerator = FileManager.default.enumerator(
        at: sessionsURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else { return [:] }

    var result: [String: RolloutState] = [:]
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
        guard let threadID = threadIDs.first(where: { url.lastPathComponent.contains($0) }),
              let state = latestLifecycle(in: url)
        else { continue }
        result[threadID] = state
    }
    return result
}

private func latestLifecycle(in url: URL) -> RolloutState? {
    guard let handle = try? FileHandle(forReadingFrom: url),
          let fileSize = try? handle.seekToEnd()
    else { return nil }
    defer { try? handle.close() }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var windowSize: UInt64 = min(fileSize, 256 * 1024)
    while windowSize > 0 {
        let start = fileSize - windowSize
        try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        if start > 0, let firstNewline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(...firstNewline)
        }

        for line in data.split(separator: 0x0A).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let event = payload["type"] as? String,
                  ["task_started", "task_complete", "turn_aborted"].contains(event)
            else { continue }

            let lifecycle: String
            switch event {
            case "task_started": lifecycle = "running"
            case "task_complete": lifecycle = "completed"
            default: lifecycle = "aborted"
            }
            let timestamp = (object["timestamp"] as? String)
                .flatMap { formatter.date(from: $0) }?
                .timeIntervalSince1970 ?? 0
            return RolloutState(lifecycle: lifecycle, updatedAt: timestamp)
        }

        if windowSize == fileSize { break }
        windowSize = min(fileSize, windowSize * 2)
    }
    return nil
}

let environment = ProcessInfo.processInfo.environment
let codexPath = environment["CODEX_CLI_PATH"]
    ?? "/Applications/ChatGPT.app/Contents/Resources/codex"

guard FileManager.default.isExecutableFile(atPath: codexPath) else {
    FileHandle.standardOutput.write(Data("[]\n".utf8))
    exit(0)
}

let server = Process()
let input = Pipe()
let output = Pipe()
server.executableURL = URL(fileURLWithPath: codexPath)
server.arguments = ["app-server", "--listen", "stdio://"]
server.standardInput = input
server.standardOutput = output
server.standardError = FileHandle.nullDevice

let semaphore = DispatchSemaphore(value: 0)
let lock = NSLock()
var buffer = Data()
var summaries: [ThreadSummary] = []
var usageWindows: [UsageWindow]? = nil
var receivedThreads = false
var receivedUsage = false
var didSignal = false
let includeUsage = environment["CODEX_STATUS_INCLUDE_USAGE"] == "1"

func windowName(minutes: Double, fallback: String) -> String {
    if minutes == 300 { return "5-hour limit" }
    if minutes == 10_080 { return "Weekly limit" }
    if minutes >= 1_440 { return "\(Int(minutes / 1_440))-day limit" }
    if minutes >= 60 { return "\(Int(minutes / 60))-hour limit" }
    if minutes > 0 { return "\(Int(minutes))-minute limit" }
    return fallback
}

func parseUsageWindow(_ value: Any?, fallback: String) -> UsageWindow? {
    guard let object = value as? [String: Any],
          let used = (object["usedPercent"] as? NSNumber)?.doubleValue
    else { return nil }
    let minutes = (object["windowDurationMins"] as? NSNumber)?.doubleValue ?? 0
    return UsageWindow(
        name: windowName(minutes: minutes, fallback: fallback),
        remainingPercent: max(0, min(100, 100 - used)),
        resetsAt: (object["resetsAt"] as? NSNumber)?.doubleValue ?? 0
    )
}

func signalIfFinished() {
    if !didSignal && receivedThreads && (!includeUsage || receivedUsage) {
        didSignal = true
        semaphore.signal()
    }
}

output.fileHandleForReading.readabilityHandler = { handle in
    let chunk = handle.availableData
    guard !chunk.isEmpty else { return }

    lock.lock()
    buffer.append(chunk)
    while let newline = buffer.firstIndex(of: 0x0A) {
        let line = buffer.prefix(upTo: newline)
        buffer.removeSubrange(...newline)
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let messageID = message["id"] as? Int
        else { continue }

        if messageID == 1,
           let result = message["result"] as? [String: Any],
           let rows = result["data"] as? [[String: Any]] {
            let recentRows = Array(rows.prefix(12))
            let states = rolloutStates(for: Set(recentRows.compactMap { $0["id"] as? String }))
            summaries = recentRows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                let status = row["status"] as? [String: Any] ?? [:]
                let lifecycle = states[id]
                return ThreadSummary(
                    id: id,
                    name: (row["name"] as? String) ?? "",
                    cwd: (row["cwd"] as? String) ?? "",
                    updatedAt: (row["updatedAt"] as? NSNumber)?.doubleValue ?? 0,
                    statusType: (status["type"] as? String) ?? "notLoaded",
                    activeFlags: status["activeFlags"] as? [String] ?? [],
                    lifecycle: lifecycle?.lifecycle ?? "unknown",
                    lifecycleUpdatedAt: lifecycle?.updatedAt ?? 0
                )
            }
            receivedThreads = true
        } else if messageID == 2 {
            if let result = message["result"] as? [String: Any],
               let limits = result["rateLimits"] as? [String: Any] {
                usageWindows = [
                    parseUsageWindow(limits["primary"], fallback: "Primary limit"),
                    parseUsageWindow(limits["secondary"], fallback: "Secondary limit")
                ].compactMap { $0 }
            } else {
                usageWindows = []
            }
            receivedUsage = true
        }
        signalIfFinished()
    }
    lock.unlock()
}

do {
    try server.run()
    var messages = [
        ["method": "initialize", "id": 0, "params": [
            "clientInfo": ["name": "codex_status", "title": "CodexStatus", "version": "0.2.0"]
        ]],
        ["method": "initialized", "params": [:]],
        ["method": "thread/list", "id": 1, "params": ["limit": 20, "sortKey": "updated_at"]]
    ] as [[String: Any]]
    if includeUsage {
        messages.append(["method": "account/rateLimits/read", "id": 2])
    }

    for message in messages {
        let data = try JSONSerialization.data(withJSONObject: message)
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.write(Data("\n".utf8))
    }

    _ = semaphore.wait(timeout: .now() + 6)
} catch {
    summaries = []
}

output.fileHandleForReading.readabilityHandler = nil
if server.isRunning { server.terminate() }

let encoder = JSONEncoder()
let result = ScanResult(threads: receivedThreads ? summaries : [], usageWindows: usageWindows)
if let data = try? encoder.encode(result) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
