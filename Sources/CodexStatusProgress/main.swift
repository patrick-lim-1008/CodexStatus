import Foundation

private struct ProgressRequest: Decodable {
    let threadID: String
    let prompt: String
}

private struct ProgressResult: Encodable {
    let ok: Bool
    let code: String
    let summary: String?
    let detail: String?
}

private final class MessageInbox {
    private let condition = NSCondition()
    private var messages: [[String: Any]] = []
    private var didTerminate = false

    func append(_ message: [String: Any]) {
        condition.lock()
        messages.append(message)
        condition.broadcast()
        condition.unlock()
    }

    func markTerminated() {
        condition.lock()
        didTerminate = true
        condition.broadcast()
        condition.unlock()
    }

    func wait(timeout: TimeInterval, matching predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let index = messages.firstIndex(where: predicate) {
                return messages.remove(at: index)
            }
            if didTerminate || Date() >= deadline { return nil }
            condition.wait(until: deadline)
        }
    }
}

private func writeResult(ok: Bool, code: String, summary: String? = nil, detail: String? = nil) {
    guard let data = try? JSONEncoder().encode(ProgressResult(ok: ok, code: code, summary: summary, detail: detail)) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    try? FileHandle.standardOutput.synchronize()
    try? FileHandle.standardOutput.close()
}

private func validThreadID(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 200 else { return false }
    return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
}

private func responseID(_ message: [String: Any]) -> Int? {
    (message["id"] as? NSNumber)?.intValue
}

private func send(_ message: [String: Any], to handle: FileHandle) throws {
    let data = try JSONSerialization.data(withJSONObject: message)
    try handle.write(contentsOf: data)
    try handle.write(contentsOf: Data("\n".utf8))
}

private func agentText(from message: [String: Any], for threadID: String) -> String? {
    guard message["method"] as? String == "item/completed",
          let params = message["params"] as? [String: Any],
          params["threadId"] as? String == threadID,
          let item = params["item"] as? [String: Any],
          item["type"] as? String == "agentMessage"
    else { return nil }
    return item["text"] as? String
}

let requestData = FileHandle.standardInput.readDataToEndOfFile()
guard let request = try? JSONDecoder().decode(ProgressRequest.self, from: requestData) else {
    writeResult(ok: false, code: "invalidRequest")
    exit(1)
}

let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
guard validThreadID(request.threadID), !prompt.isEmpty, prompt.count <= 2_000 else {
    writeResult(ok: false, code: "invalidRequest")
    exit(1)
}

let codexPath = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"]
    ?? "/Applications/ChatGPT.app/Contents/Resources/codex"
guard FileManager.default.isExecutableFile(atPath: codexPath) else {
    writeResult(ok: false, code: "codexUnavailable")
    exit(1)
}

let server = Process()
let serverInput = Pipe()
let serverOutput = Pipe()
private let inbox = MessageInbox()
var outputBuffer = Data()

server.executableURL = URL(fileURLWithPath: codexPath)
server.arguments = ["app-server", "--listen", "stdio://"]
server.standardInput = serverInput
server.standardOutput = serverOutput
server.standardError = FileHandle.nullDevice

serverOutput.fileHandleForReading.readabilityHandler = { handle in
    let chunk = handle.availableData
    guard !chunk.isEmpty else { return }
    outputBuffer.append(chunk)
    while let newline = outputBuffer.firstIndex(of: 0x0A) {
        let line = outputBuffer.prefix(upTo: newline)
        outputBuffer.removeSubrange(...newline)
        if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
            inbox.append(message)
        }
    }
}
server.terminationHandler = { _ in inbox.markTerminated() }

func finish(_ code: Int32) -> Never {
    serverOutput.fileHandleForReading.readabilityHandler = nil
    try? serverInput.fileHandleForWriting.close()
    if server.isRunning { server.terminate() }
    exit(code)
}

do {
    try server.run()
    try send([
        "method": "initialize",
        "id": 0,
        "params": [
            "clientInfo": ["name": "codex_status_progress", "title": "CodexStatus Progress Sidecar", "version": "1.0"]
        ]
    ], to: serverInput.fileHandleForWriting)

    guard let initialize = inbox.wait(timeout: 8, matching: { responseID($0) == 0 }),
          initialize["error"] == nil else {
        writeResult(ok: false, code: "connectionFailed")
        finish(1)
    }

    try send(["method": "initialized", "params": [:]], to: serverInput.fileHandleForWriting)
    try send([
        "method": "thread/fork",
        "id": 1,
        "params": [
            "threadId": request.threadID,
            "ephemeral": true,
            "excludeTurns": true,
            "sandbox": "read-only",
            "approvalPolicy": "never",
            "baseInstructions": "You are a temporary progress sidecar. Answer the progress question without changing, steering, continuing, or interrupting the source task. Report only observable progress; never reveal or invent private chain-of-thought. Do not modify files, start subagents, or ask for approvals."
        ]
    ], to: serverInput.fileHandleForWriting)

    guard let fork = inbox.wait(timeout: 15, matching: { responseID($0) == 1 }) else {
        writeResult(ok: false, code: "forkFailed", detail: "No response from thread/fork")
        finish(1)
    }
    guard fork["error"] == nil,
          let forkResult = fork["result"] as? [String: Any],
          let thread = forkResult["thread"] as? [String: Any],
          let sideThreadID = thread["id"] as? String,
          thread["ephemeral"] as? Bool == true else {
        let detail = ProcessInfo.processInfo.environment["CODEX_STATUS_DEBUG"] == "1"
            ? String(describing: fork["error"] ?? fork["result"] ?? "Malformed fork response")
            : nil
        writeResult(ok: false, code: "forkFailed", detail: detail)
        finish(1)
    }

    try send([
        "method": "turn/start",
        "id": 2,
        "params": [
            "threadId": sideThreadID,
            "input": [["type": "text", "text": prompt]],
            "turnTrigger": "codexstatus-progress-sidecar"
        ]
    ], to: serverInput.fileHandleForWriting)

    guard let start = inbox.wait(timeout: 15, matching: { responseID($0) == 2 }),
          start["error"] == nil else {
        writeResult(ok: false, code: "startFailed")
        finish(1)
    }

    var latestSummary: String?
    let deadline = Date().addingTimeInterval(180)
    while Date() < deadline {
        guard let message = inbox.wait(timeout: min(10, deadline.timeIntervalSinceNow), matching: { candidate in
            guard let params = candidate["params"] as? [String: Any],
                  params["threadId"] as? String == sideThreadID else { return false }
            let method = candidate["method"] as? String
            return method == "item/completed" || method == "turn/completed"
        }) else { continue }

        if let text = agentText(from: message, for: sideThreadID),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            latestSummary = text
        }
        if message["method"] as? String == "turn/completed" { break }
    }

    guard let summary = latestSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty else {
        writeResult(ok: false, code: "emptyResponse")
        finish(1)
    }
    writeResult(ok: true, code: "complete", summary: String(summary.prefix(1_500)))
    finish(0)
} catch {
    writeResult(ok: false, code: "connectionFailed")
    finish(1)
}
