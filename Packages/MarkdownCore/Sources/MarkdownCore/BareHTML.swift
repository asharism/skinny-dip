import Markdown

/// Renders Markdown Source to Bare HTML: structure only, no `class`, `style`,
/// `font` or color attributes. See GLOSSARY.md and docs/adr/0001.
public enum BareHTML {
    public static func render(_ source: String) -> String {
        // P0: not implemented yet. The golden tests are expected to fail.
        _ = Document(parsing: source)
        return ""
    }
}
