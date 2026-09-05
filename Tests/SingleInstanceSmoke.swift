import Foundation

private struct SingleInstanceTestFailure: Error {
    let message: String
}

@main
struct SingleInstanceSmoke {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe" {
            let probe = SingleInstanceGuard(lockURL: URL(fileURLWithPath: CommandLine.arguments[2]))
            exit(probe.acquire() ? 1 : 0)
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexStatusInstanceTests-\(UUID().uuidString)", isDirectory: true)
        let lockURL = root.appendingPathComponent("instance.lock")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = SingleInstanceGuard(lockURL: lockURL)
        try expect(first.acquire(), "The first instance must own the lock")
        try expect(first.acquire(), "Acquiring the same guard twice must be idempotent")
        let rejectedStatus = try probe(lockURL: lockURL)
        try expect(rejectedStatus == 0, "A second process must be rejected")
        first.release()
        let acquiredStatus = try probe(lockURL: lockURL)
        try expect(acquiredStatus == 1, "The lock must become available after the owner exits")
        print("Single-instance lock smoke tests passed")
    }

    private static func probe(lockURL: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--probe", lockURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SingleInstanceTestFailure(message: message) }
    }
}
