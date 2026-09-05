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
    let activity: String
    let activityUpdatedAt: Double
    let turnStartedAt: Double
}

struct UsageWindow: Codable {
    let name: String
    let remainingPercent: Double
    let resetsAt: Double
}

struct ScanResult: Codable {
    let connected: Bool
    let threads: [ThreadSummary]
    let usageWindows: [UsageWindow]?
}

private struct RolloutState: Codable {
    let lifecycle: String
    let updatedAt: Double
    let activity: String
    let activityUpdatedAt: Double
    let turnStartedAt: Double
}

private let fractionalTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let standardTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

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
              let state = latestRolloutState(in: url)
        else { continue }
        result[threadID] = state
    }
    return result
}

private func latestRolloutState(in url: URL) -> RolloutState? {
    guard let handle = try? FileHandle(forReadingFrom: url),
          let fileSize = try? handle.seekToEnd()
    else { return nil }
    defer { try? handle.close() }

    var windowSize: UInt64 = min(fileSize, 256 * 1024)
    while windowSize > 0 {
        let start = fileSize - windowSize
        try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        if start > 0, let firstNewline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(...firstNewline)
        }

        if let state = rolloutState(in: data), state.lifecycle != "unknown" { return state }

        if windowSize == fileSize { break }
        windowSize = min(fileSize, windowSize * 2)
    }
    return nil
}

private func rolloutState(in data: Data) -> RolloutState? {
    var lifecycle = "unknown"
    var lifecycleUpdatedAt = 0.0
    var activity = "Activity unavailable"
    var activityUpdatedAt = 0.0
    var turnStartedAt = 0.0
    var foundRecord = false

    for line in data.split(separator: 0x0A) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let recordType = object["type"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { continue }

        foundRecord = true
        let timestamp = parsedTimestamp(object["timestamp"] as? String)

        if recordType == "event_msg", let event = payload["type"] as? String {
            switch event {
            case "task_started":
                lifecycle = "running"
                lifecycleUpdatedAt = timestamp
                turnStartedAt = timestamp
            case "task_complete":
                lifecycle = "completed"
                lifecycleUpdatedAt = timestamp
            case "turn_aborted":
                lifecycle = "aborted"
                lifecycleUpdatedAt = timestamp
            default:
                break
            }
        }

        if let mappedActivity = sanitizedActivity(recordType: recordType, payload: payload) {
            activity = mappedActivity
            activityUpdatedAt = timestamp
        }
    }

    guard foundRecord else { return nil }
    return RolloutState(
        lifecycle: lifecycle,
        updatedAt: lifecycleUpdatedAt,
        activity: activity,
        activityUpdatedAt: activityUpdatedAt,
        turnStartedAt: turnStartedAt
    )
}

private func parsedTimestamp(_ value: String?) -> Double {
    guard let value else { return 0 }
    if let date = fractionalTimestampFormatter.date(from: value) {
        return date.timeIntervalSince1970
    }
    return standardTimestampFormatter.date(from: value)?.timeIntervalSince1970 ?? 0
}

/// Maps private rollout records to a small, non-sensitive activity vocabulary.
/// Commands, prompts, paths, arguments, tool results, and model reasoning are
/// intentionally never copied into CodexStatus output.
private func sanitizedActivity(recordType: String, payload: [String: Any]) -> String? {
    let payloadType = payload["type"] as? String ?? ""

    if recordType == "event_msg" {
        switch payloadType {
        case "task_started", "agent_reasoning": return "Thinking"
        case "agent_message": return "Writing a response"
        case "patch_apply_end": return "Editing files"
        case "web_search_end": return "Searching the web"
        case "mcp_tool_call_end": return "Using an integration"
        case "sub_agent_activity": return "Coordinating subtasks"
        case "image_generation_end": return "Generating an image"
        case "task_complete": return "Completed"
        case "turn_aborted": return "Stopped"
        default: return nil
        }
    }

    guard recordType == "response_item" else { return nil }
    switch payloadType {
    case "reasoning":
        return "Thinking"
    case "message":
        return payload["role"] as? String == "assistant" ? "Writing a response" : nil
    case "custom_tool_call", "function_call":
        return sanitizedToolActivity(payload["name"] as? String ?? "")
    default:
        return nil
    }
}

private func sanitizedToolActivity(_ name: String) -> String {
    let normalized = name.lowercased()
    if normalized == "exec" || normalized.contains("terminal") || normalized.contains("command") {
        return "Using the terminal"
    }
    if normalized.contains("patch") || normalized.contains("file") {
        return "Editing files"
    }
    if normalized.contains("web") || normalized.contains("browser") || normalized.contains("search") {
        return "Searching the web"
    }
    if normalized.contains("image") {
        return "Generating an image"
    }
    if normalized.contains("agent") || normalized.contains("thread") || normalized.contains("message") {
        return "Coordinating subtasks"
    }
    if normalized.contains("wait") {
        return "Waiting for a tool"
    }
    return "Using a tool"
}

if CommandLine.arguments.contains("--parse-rollout") {
    let inputData = FileHandle.standardInput.readDataToEndOfFile()
    if let state = rolloutState(in: inputData),
       let data = try? JSONEncoder().encode(state) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }
    FileHandle.standardOutput.write(Data("{}\n".utf8))
    exit(1)
}

let environment = ProcessInfo.processInfo.environment
let codexCandidates: [String]
if let override = environment["CODEX_CLI_PATH"] {
    codexCandidates = [override]
} else {
    codexCandidates = [
        "/Applications/Codex.app/Contents/Resources/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex"
    ]
}
guard let codexPath = codexCandidates.first(where: {
    FileManager.default.isExecutableFile(atPath: $0)
}) else {
    let result = ScanResult(connected: false, threads: [], usageWindows: nil)
    if let data = try? JSONEncoder().encode(result) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
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

func parseUsageWindows(_ result: [String: Any]) -> [UsageWindow] {
    let legacyLimit = result["rateLimits"] as? [String: Any]
    let canonicalLimitID = legacyLimit?["limitId"] as? String ?? "codex"
    let limitsByID = result["rateLimitsByLimitId"] as? [String: Any]
    let canonicalLimit = limitsByID?[canonicalLimitID] as? [String: Any]
        ?? legacyLimit
    guard let canonicalLimit else { return [] }

    // The map can also contain model-specific buckets such as a 5-hour window
    // for one Codex model. Those are not the account's general 5-hour limit and
    // must not switch the compact meter into dual-window mode.
    return [
        parseUsageWindow(canonicalLimit["primary"], fallback: "Primary limit"),
        parseUsageWindow(canonicalLimit["secondary"], fallback: "Secondary limit")
    ].compactMap { $0 }
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
                    lifecycleUpdatedAt: lifecycle?.updatedAt ?? 0,
                    activity: lifecycle?.activity ?? "Activity unavailable",
                    activityUpdatedAt: lifecycle?.activityUpdatedAt ?? 0,
                    turnStartedAt: lifecycle?.turnStartedAt ?? 0
                )
            }
            receivedThreads = true
        } else if messageID == 2 {
            if let result = message["result"] as? [String: Any] {
                usageWindows = parseUsageWindows(result)
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
            "clientInfo": ["name": "codex_status", "title": "CodexStatus", "version": "0.3.1"]
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
let result = ScanResult(
    connected: receivedThreads,
    threads: receivedThreads ? summaries : [],
    usageWindows: usageWindows
)
if let data = try? encoder.encode(result) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
