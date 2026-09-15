import Foundation

enum RolloutThreadIdentity {
    static func owner(in header: Data) -> String? {
        // Filenames may contain parent/child IDs or segment IDs. The session
        // metadata is the authority for ownership, not any filename substring.
        let firstLine = header.split(separator: 0x0A).first.map(Data.init) ?? header
        guard let root = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
              root["type"] as? String == "session_meta",
              let payload = root["payload"] as? [String: Any]
        else { return nil }
        return payload["id"] as? String
    }
}
