import Markdown

/// Renders Markdown Source to Bare HTML: structure only, no `class`, `style`,
/// `font` or color attributes. See GLOSSARY.md and docs/adr/0001.
public enum BareHTML {
    public static func render(_ source: String, options: RenderOptions = .default) -> String {
        // Smart punctuation would turn typed quotes and dashes into curly ones (ADR-0002).
        let document = Document(parsing: source, options: .disableSmartOpts)
        var renderer = Renderer(options: options)
        return renderer.visit(document)
    }
}

private struct Renderer: MarkupVisitor {
    let options: RenderOptions
    private var isInsideLink = false
    private var tableAlignments: [Table.ColumnAlignment?] = []

    init(options: RenderOptions) {
        self.options = options
    }

    mutating func defaultVisit(_ markup: any Markup) -> String {
        visitChildren(of: markup)
    }

    // MARK: Blocks

    mutating func visitDocument(_ document: Document) -> String {
        visitBlocks(of: document)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = options.demotesHeadings ? min(heading.level + 1, 6) : heading.level
        return "<h\(level)>\(visitChildren(of: heading))</h\(level)>"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(visitChildren(of: paragraph))</p>"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(visitBlocks(of: blockQuote))\n</blockquote>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        // No language class: Bare HTML carries no `class` attributes.
        "<pre><code>\(escape(codeBlock.code))</code></pre>"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        "<p>\(escape(html.rawHTML.trimmingTrailingNewlines()))</p>"
    }

    // MARK: Lists

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        "<ul>\n\(visitItems(of: list))\n</ul>"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
        return "<ol\(start)>\n\(visitItems(of: list))\n</ol>"
    }

    private mutating func visitItems(of list: any ListItemContainer) -> String {
        let isTight = !list.isLoose
        var items: [String] = []
        for item in list.listItems {
            items.append(renderItem(item, isTight: isTight))
        }
        return items.joined(separator: "\n")
    }

    /// Follows cmark's layout: a tight item's paragraphs are inlined, and every
    /// other block sits on its own line inside the `<li>`.
    private mutating func renderItem(_ item: ListItem, isTight: Bool) -> String {
        // Checkboxes get stripped by mail clients, so task items use characters.
        var marker = switch item.checkbox {
        case .checked: "☑ "
        case .unchecked: "☐ "
        case nil: ""
        }

        var html = "<li>"
        for child in item.children {
            if isTight, let paragraph = child as? Paragraph {
                html += marker + visitChildren(of: paragraph)
            } else {
                if !html.hasSuffix("\n") { html += "\n" }
                if let paragraph = child as? Paragraph, !marker.isEmpty {
                    html += "<p>\(marker)\(visitChildren(of: paragraph))</p>\n"
                } else {
                    html += visit(child) + "\n"
                }
            }
            marker = ""
        }
        return html + "</li>"
    }

    // MARK: Tables

    mutating func visitTable(_ table: Table) -> String {
        tableAlignments = table.columnAlignments
        let border = options.bordersTables ? " border=\"1\"" : ""
        return "<table\(border)>\n\(visitBlocks(of: table))\n</table>"
    }

    mutating func visitTableHead(_ head: Table.Head) -> String {
        "<thead>\n<tr>\n\(renderCells(of: head, tag: "th"))\n</tr>\n</thead>"
    }

    mutating func visitTableBody(_ body: Table.Body) -> String {
        "<tbody>\n\(visitBlocks(of: body))\n</tbody>"
    }

    mutating func visitTableRow(_ row: Table.Row) -> String {
        "<tr>\n\(renderCells(of: row, tag: "td"))\n</tr>"
    }

    private mutating func renderCells(of row: any Markup, tag: String) -> String {
        row.children.enumerated().map { column, cell in
            // `align` is a structural attribute, not CSS, so Word and Outlook honor it.
            let align = switch column < tableAlignments.count ? tableAlignments[column] : nil {
            case .left: " align=\"left\""
            case .center: " align=\"center\""
            case .right: " align=\"right\""
            case nil: ""
            }
            return "<\(tag)\(align)>\(visitChildren(of: cell))</\(tag)>"
        }.joined(separator: "\n")
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) -> String {
        isInsideLink ? escape(text.string) : autolinked(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(visitChildren(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(visitChildren(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(visitChildren(of: strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escape(inlineCode.code))</code>"
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> String {
        escape(html.rawHTML)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        options.newlinesAsBreaks ? "<br>\n" : "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitLink(_ link: Link) -> String {
        let wasInsideLink = isInsideLink
        isInsideLink = true
        defer { isInsideLink = wasInsideLink }

        let content = visitChildren(of: link)
        // Only links that work in someone else's inbox; anything else is just its text.
        guard let destination = link.destination, Self.isPasteSafe(destination, schemes: ["http", "https", "mailto"]) else {
            return content
        }
        return "<a href=\"\(escape(destination))\">\(content)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let alt = escape(image.plainText)
        // A local path means nothing in someone else's inbox, so it renders as its alt text.
        guard let source = image.source, Self.isPasteSafe(source, schemes: ["http", "https"]) else {
            return alt
        }
        return "<img src=\"\(escape(source))\" alt=\"\(alt)\">"
    }

    // MARK: Helpers

    private mutating func visitChildren(of markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    private mutating func visitBlocks(of markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined(separator: "\n")
    }

    private static func isPasteSafe(_ url: String, schemes: Set<String>) -> Bool {
        guard let colon = url.firstIndex(of: ":") else { return false }
        return schemes.contains(url[..<colon].lowercased())
    }

    /// swift-markdown doesn't enable GFM's autolink extension, so bare web
    /// addresses in text are linked here.
    private func autolinked(_ string: String) -> String {
        var html = ""
        var rest = string[...]
        while let match = rest.firstMatch(of: /https?:\/\/[^\s<>]+/) {
            var url = match.output[...]
            while let last = url.last, ".,:;!?\"')".contains(last) { url.removeLast() }
            html += escape(String(rest[..<match.range.lowerBound]))
            html += "<a href=\"\(escape(String(url)))\">\(escape(String(url)))</a>"
            rest = rest[url.endIndex...]
        }
        return html + escape(String(rest))
    }

    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension ListItemContainer {
    /// CommonMark: a list is loose if a blank line separates two of its items,
    /// or two blocks directly inside one item. swift-markdown doesn't expose it.
    var isLoose: Bool {
        let items = Array(listItems)
        let itemGap = zip(items, items.dropFirst()).contains { hasBlankLine(between: $0, and: $1) }
        let childGap = items.contains { item in
            let children = Array(item.children)
            return zip(children, children.dropFirst()).contains { hasBlankLine(between: $0, and: $1) }
        }
        return itemGap || childGap
    }

    private func hasBlankLine(between first: any Markup, and second: any Markup) -> Bool {
        guard let end = contentEndLine(of: first), let start = second.range?.lowerBound.line else { return false }
        return start > end + 1
    }

    /// A list item's own range runs on over the blank line after it, so measure
    /// where its last piece of content ends instead.
    private func contentEndLine(of markup: any Markup) -> Int? {
        if let last = markup.children.reversed().first(where: { $0.range != nil }) {
            return contentEndLine(of: last)
        }
        return markup.range?.upperBound.line
    }
}

extension String {
    func trimmingTrailingNewlines() -> String {
        var result = self
        while result.hasSuffix("\n") { result.removeLast() }
        return result
    }
}
