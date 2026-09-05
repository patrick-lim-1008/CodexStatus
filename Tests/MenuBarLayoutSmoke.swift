import Foundation

private struct MenuBarLayoutTestFailure: Error {
    let message: String
}

@main
struct MenuBarLayoutSmoke {
    static func main() throws {
        try expect(
            !MenuBarLayoutPolicy.reservesCountSlot(showCounts: true, displayedStatusCounts: [1]),
            "A single unnumbered status must use the narrow width"
        )
        try expect(
            MenuBarLayoutPolicy.reservesCountSlot(showCounts: true, displayedStatusCounts: [1, 3, 1]),
            "Any numbered state in the full cycle must reserve the wide width"
        )
        try expect(
            !MenuBarLayoutPolicy.reservesCountSlot(showCounts: false, displayedStatusCounts: [4]),
            "Disabling counts must always return to the narrow width"
        )
        try expect(
            !MenuBarLayoutPolicy.reservesCountSlot(showCounts: true, displayedStatusCounts: []),
            "An idle cycle must use the narrow width"
        )
        print("Menu-bar adaptive width smoke tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw MenuBarLayoutTestFailure(message: message) }
    }
}
