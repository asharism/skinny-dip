import Foundation

/// Decides whether a stored CodeMirror history JSON still matches the Markdown
/// on disk. The `.md` file is the truth: a hand edit drops the history.
public enum ScratchRestore {
    public static func history(forText text: String, storedHistoryJSON: String?) -> String? {
        guard let storedHistoryJSON,
              let data = storedHistoryJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let document = object["doc"] as? String,
              document == text
        else { return nil }
        return storedHistoryJSON
    }
}
