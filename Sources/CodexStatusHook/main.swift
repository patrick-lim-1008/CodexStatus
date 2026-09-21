import Foundation

struct Snapshot: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let detail: String
    let status: String
    let updatedAt: Date
}

func shouldIgnoreSubagentHook(
    _ object: [String: Any],
    event: String,
    sessionID: String
) -> Bool {
    if event == "SubagentStart" || event == "SubagentStop" {
        return true
    }

    if let agentType = object["agent_type"] as? String,
       agentType.lowercased().contains("guardian") {
        return true
    }

    // Hooks fired inside a child agent reuse the parent's session_id. The
    // distinct agent_id is therefore required to stop child tool activity from
    // overwriting the status of the conversation the user actually opened.
    guard let agentID = object["agent_id"] as? String,
          !agentID.isEmpty
    else { return false }
    return agentID != sessionID
}

let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard let object = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
      let sessionID = object["session_id"] as? String,
      let event = object["hook_event_name"] as? String
else {
    FileHandle.standardOutput.write(Data("{}\n".utf8))
    exit(0)
}

if shouldIgnoreSubagentHook(object, event: event, sessionID: sessionID) {
    FileHandle.standardOutput.write(Data("{}\n".utf8))
    exit(0)
}

let cwd = object["cwd"] as? String ?? ""
let directoryName = URL(fileURLWithPath: cwd).lastPathComponent
let name = directoryName.isEmpty ? "Codex Task" : directoryName

let mapped: (status: String, detail: String)
switch event {
case "UserPromptSubmit":
    mapped = ("working", "Thinking")
case "PreToolUse":
    let tool = object["tool_name"] as? String ?? "tool"
    if requestsUserInput(tool) {
        mapped = ("needsAttention", "Waiting for your input")
    } else {
        mapped = ("working", "Running \(displayName(for: tool))")
    }
case "PermissionRequest":
    mapped = ("needsAttention", "Waiting for approval")
case "PostToolUse":
    // A failed command/tool is recoverable and does not mean the whole Codex
    // task failed. The next lifecycle state remains authoritative.
    mapped = ("working", containsError(object["tool_response"])
        ? "Continuing after a tool error"
        : "Processing the tool result")
case "Stop":
    // Stop fires when a turn is about to end and can still be continued by a
    // Stop hook. Rollout task_complete is the authoritative Done signal.
    mapped = ("idle", "Turn ended · verifying completion")
case "Interrupt":
    mapped = ("idle", "Interrupted")
case "SessionEnd":
    mapped = ("idle", "Session closed")
default:
    mapped = ("idle", "Session opened")
}

let snapshot = Snapshot(
    schemaVersion: 2,
    id: sessionID,
    name: name,
    detail: mapped.detail,
    status: mapped.status,
    updatedAt: Date()
)
let fileManager = FileManager.default
let sessionsDirectory = ProcessInfo.processInfo.environment["CODEX_STATUS_SESSIONS_DIRECTORY"]
    .map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexStatus/sessions", isDirectory: true)
try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

let safeID = sessionID.map { character -> Character in
    character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
}
let outputURL = sessionsDirectory.appendingPathComponent(String(safeID)).appendingPathExtension("json")
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .millisecondsSince1970
if let data = try? encoder.encode(snapshot) {
    try? data.write(to: outputURL, options: .atomic)
}

FileHandle.standardOutput.write(Data("{}\n".utf8))

func displayName(for tool: String) -> String {
    if tool == "Bash" { return "terminal" }
    if tool == "apply_patch" { return "file edit" }
    if tool.hasPrefix("mcp__") { return "integration" }
    return tool.replacingOccurrences(of: "_", with: " ")
}

func requestsUserInput(_ tool: String) -> Bool {
    let normalized = tool.lowercased()
    return normalized == "request_user_input"
        || normalized.hasSuffix(".request_user_input")
        || normalized.hasSuffix("__request_user_input")
}

func containsError(_ value: Any?) -> Bool {
    guard let value else { return false }
    if let dictionary = value as? [String: Any] {
        if dictionary["isError"] as? Bool == true { return true }
        if let code = dictionary["exit_code"] as? Int, code != 0 { return true }
        if let code = dictionary["exitCode"] as? Int, code != 0 { return true }
        return dictionary.values.contains(where: containsError)
    }
    if let array = value as? [Any] { return array.contains(where: containsError) }
    return false
}
