import Darwin
import Foundation

/// Holds a process-scoped advisory lock so copied builds with the same bundle
/// identifier cannot create duplicate menu-bar items.
final class SingleInstanceGuard {
    private(set) var ownsLock = false
    private var descriptor: Int32 = -1
    let lockURL: URL

    convenience init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.init(lockURL: support
            .appendingPathComponent("CodexStatus", isDirectory: true)
            .appendingPathComponent("instance.lock"))
    }

    init(lockURL: URL) {
        self.lockURL = lockURL
    }

    @discardableResult
    func acquire() -> Bool {
        if ownsLock { return true }
        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return false
        }

        let opened = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { return false }
        guard Darwin.lockf(opened, F_TLOCK, 0) == 0 else {
            Darwin.close(opened)
            return false
        }
        descriptor = opened
        ownsLock = true
        return true
    }

    func release() {
        guard descriptor >= 0 else { return }
        _ = Darwin.lockf(descriptor, F_ULOCK, 0)
        Darwin.close(descriptor)
        descriptor = -1
        ownsLock = false
    }

    deinit {
        release()
    }
}
