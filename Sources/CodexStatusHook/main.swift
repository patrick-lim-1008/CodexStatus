import Foundation

struct Snapshot: Codable {
    let id: String
    let name: String
    let detail: String
    let status: String
    let updatedAt: Date
}

let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard let object = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
      let sessionID = object["session_id"] as? String,
      let event = object["hook_event_name"] as? String
else {
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
    mapped = ("working", "Running \(displayName(for: tool))")
case "PermissionRequest":
    mapped = ("needsAttention", "Waiting for approval")
case "PostToolUse":
    mapped = containsError(object["tool_response"])
        ? ("error", "A tool reported an error")
        : ("working", "Continuing")
case "Stop":
    mapped = ("done", "Finished just now")
case "SessionEnd":
    mapped = ("idle", "Session closed")
case "SubagentStart":
    let agent = object["agent_type"] as? String ?? "subagent"
    mapped = ("working", "Running \(agent) subagent")
case "SubagentStop":
    mapped = ("working", "Subagent finished")
default:
    mapped = ("idle", "Session opened")
}

let snapshot = Snapshot(id: sessionID, name: name, detail: mapped.detail, status: mapped.status, updatedAt: Date())
let fileManager = FileManager.default
let sessionsDirectory = fileManager.homeDirectoryForCurrentUser
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
