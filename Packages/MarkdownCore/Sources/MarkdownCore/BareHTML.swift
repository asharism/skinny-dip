import Markdown

/// Renders Markdown Source to Bare HTML: structure only, no `class`, `style`,
/// `font` or color attributes. See GLOSSARY.md and docs/adr/0001.
public enum BareHTML {
    public static func render(_ source: String) -> String {
        var renderer = Renderer()
        return renderer.visit(Document(parsing: source))
    }
}

private struct Renderer: MarkupVisitor {
    mutating func defaultVisit(_ markup: any Markup) -> String {
        visitChildren(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined(separator: "\n")
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        "<h\(heading.level)>\(visitChildren(of: heading))</h\(heading.level)>"
    }

    mutating func visitText(_ text: Text) -> String {
        escape(text.string)
    }

    private mutating func visitChildren(of markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
