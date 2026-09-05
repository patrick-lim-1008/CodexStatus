import Foundation

enum MenuBarLayoutPolicy {
    static func reservesCountSlot(
        showCounts: Bool,
        displayedStatusCounts: [Int]
    ) -> Bool {
        showCounts && displayedStatusCounts.contains { $0 > 1 }
    }
}
