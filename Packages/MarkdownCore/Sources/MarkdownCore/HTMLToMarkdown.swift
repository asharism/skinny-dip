import SwiftSoup

// SwiftSoup (MIT): pasted HTML from Word, Outlook, and webmail is malformed,
// namespaced, and littered with conditional comments and `<o:p>`. A hand-rolled
// scanner would spend most of its code recovering tags; SwiftSoup's tolerant
// parser keeps this module focused on mapping structure to Markdown.

/// Converts clipboard or fragment HTML to Markdown Source for Paste as Markdown.
public enum HTMLToMarkdown {
    public static func convert(_ html: String) -> String {
        guard let document = try? SwiftSoup.parse(html) else { return "" }
        _ = try? document.select("script, style").remove()
        let root = document.body() ?? document
        var converter = Converter()
        return converter.convertBlocks(root.getChildNodes())
    }
}

private struct Converter {
    private static let safeLinkSchemes: Set<String> = ["http", "https", "mailto"]

    mutating func convertBlocks(_ nodes: [Node]) -> String {
        var blocks: [String] = []
        for node in nodes {
            guard let block = convertBlock(node) else { continue }
            blocks.append(block)
        }
        guard let first = blocks.first else { return "" }
        return blocks.dropFirst().reduce(first) { result, block in
            let separator = result.hasPrefix("#") && block.hasPrefix("#") ? "\n" : "\n\n"
            return result + separator + block
        }
    }

    mutating func convertBlock(_ node: Node) -> String? {
        guard let element = node as? Element else {
            if let text = node as? TextNode {
                let trimmed = text.text().trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : escapeText(trimmed)
            }
            return nil
        }

        switch element.safeTag() {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(element.safeTag().last!)) ?? 1
            return String(repeating: "#", count: level) + " " + convertInlines(element).trimmed()
        case "p":
            let content = convertInlines(element).trimmed()
            return content.isEmpty ? nil : content
        case "div", "section", "article", "main", "header", "footer", "span":
            if !element.hasMatchingDescendants("p, h1, h2, h3, h4, h5, h6, ul, ol, blockquote, pre, table, hr") {
                let content = convertInlines(element).trimmed()
                return content.isEmpty ? nil : content
            }
            return convertBlocks(element.getChildNodes()).nilIfEmpty
        case "ul":
            return renderList(element, ordered: false, depth: 0).nilIfEmpty
        case "ol":
            let start = Int(element.safeAttr("start")) ?? 1
            return renderList(element, ordered: true, depth: 0, start: start).nilIfEmpty
        case "blockquote":
            return renderBlockquote(element).nilIfEmpty
        case "pre":
            return renderCodeBlock(element).nilIfEmpty
        case "table":
            return renderTable(element).nilIfEmpty
        case "hr":
            return "---"
        case "br":
            return ""
        case "img":
            return renderImage(element).nilIfEmpty
        case "o:p":
            return nil
        default:
            if element.isBlock() {
                return convertBlocks(element.getChildNodes()).nilIfEmpty
            }
            let content = convertInlines(element).trimmed()
            return content.isEmpty ? nil : content
        }
    }

    private mutating func renderBlockquote(_ element: Element) -> String {
        let inner = convertBlocks(element.getChildNodes())
        let lines = inner.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.map { line in
            line.isEmpty ? ">" : "> \(line)"
        }.joined(separator: "\n")
    }

    private mutating func renderCodeBlock(_ element: Element) -> String {
        let body = (try? element.select("code").first()?.text()) ?? element.safeText()
        let fence = fenceString(for: body)
        return "\(fence)\n\(body)\n\(fence)"
    }

    private func fenceString(for code: String) -> String {
        var fence = "```"
        while code.contains(fence) { fence += "`" }
        return fence
    }

    private mutating func renderTable(_ table: Element) -> String {
        guard let rows = try? table.select("tr").array(), !rows.isEmpty else { return "" }

        var headerCells: [String] = []
        var alignments: [String?] = []
        var bodyRows: [[String]] = []

        if let thead = try? table.select("thead tr").first() {
            headerCells = cellTexts(in: thead)
            alignments = cellAlignments(in: thead)
            bodyRows = (try? table.select("tbody tr").array())?.map { cellTexts(in: $0) } ?? []
        } else {
            headerCells = cellTexts(in: rows[0])
            alignments = cellAlignments(in: rows[0])
            bodyRows = rows.dropFirst().map { cellTexts(in: $0) }
        }

        guard !headerCells.isEmpty else { return "" }

        let separator = alignments.map { alignment in
            switch alignment {
            case "left": ":---"
            case "center": ":----:"
            case "right": "----:"
            default: "----"
            }
        }

        var lines = [
            "| " + headerCells.joined(separator: " | ") + " |",
            "| " + separator.joined(separator: " | ") + " |",
        ]
        for row in bodyRows {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    private mutating func cellTexts(in row: Element) -> [String] {
        (try? row.select("th, td").array())?.map { convertInlines($0).trimmed() } ?? []
    }

    private func cellAlignments(in row: Element) -> [String?] {
        (try? row.select("th, td").array())?.map { cell in
            switch cell.safeAttr("align").lowercased() {
            case "left": "left"
            case "center": "center"
            case "right": "right"
            default: nil
            }
        } ?? []
    }

    private mutating func renderList(_ list: Element, ordered: Bool, depth: Int, start: Int = 1) -> String {
        guard let items = try? list.select("> li").array() else { return "" }
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []
        var index = start

        for (itemOffset, item) in items.enumerated() {
            let task = taskMarker(in: item)
            let marker: String
            if ordered {
                marker = "\(index). "
                index += 1
            } else if let task {
                marker = task.checked ? "- [x] " : "- [ ] "
            } else {
                marker = "- "
            }
            let prefix = indent + marker

            var childLists: [Element] = []
            var inlineParts: [String] = []
            var blockParts: [String] = []

            for child in item.getChildNodes() {
                if let text = child as? TextNode {
                    inlineParts.append(text.text())
                    continue
                }
                guard let el = child as? Element else { continue }
                switch el.safeTag() {
                case "ul", "ol":
                    childLists.append(el)
                case "p":
                    let text = convertInlines(el).trimmed()
                    if !text.isEmpty { blockParts.append(text) }
                default:
                    if el.isBlock() {
                        if let block = convertBlock(el) { blockParts.append(block) }
                    } else {
                        inlineParts.append(convertInlines(el))
                    }
                }
            }

            if itemOffset > 0 && isLooseListItem(item) {
                lines.append("")
            }

            let primary = blockParts.first ?? inlineParts.joined().trimmed()
            let stripped = stripListMarker(stripTaskMarker(primary, task: task))
            lines.append(prefix + stripped)

            if blockParts.count > 1 {
                for extra in blockParts.dropFirst() {
                    lines.append(indent + "  " + extra)
                }
            }

            for nested in childLists {
                let nestedOrdered = nested.safeTag() == "ol"
                let nestedStart = Int(nested.safeAttr("start")) ?? 1
                lines.append(renderList(nested, ordered: nestedOrdered, depth: depth + 1, start: nestedStart))
            }
        }

        return lines.joined(separator: "\n")
    }

    private func isLooseListItem(_ item: Element) -> Bool {
        (try? item.select("> p").first()) != nil
    }

    private func taskMarker(in item: Element) -> (checked: Bool, raw: String)? {
        let text = item.safeText()
        if text.hasPrefix("☐") { return (false, "☐") }
        if text.hasPrefix("☑") { return (true, "☑") }
        return nil
    }

    private func stripTaskMarker(_ text: String, task: (checked: Bool, raw: String)?) -> String {
        guard let task else { return text }
        var result = text
        if result.hasPrefix(task.raw) {
            result = String(result.dropFirst(task.raw.count))
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func stripListMarker(_ text: String) -> String {
        text.replacing(/^[\s·•●◦∙-]+/, with: "")
    }

    mutating func convertInlines(_ element: Element) -> String {
        convertInlineNodes(element.getChildNodes())
    }

    private mutating func convertInlineNodes(_ nodes: [Node]) -> String {
        nodes.map { convertInline($0) }.joined()
    }

    private mutating func convertInline(_ node: Node) -> String {
        if let text = node as? TextNode {
            var raw = text.getWholeText()
            while raw.first == "\n" { raw.removeFirst() }
            return escapeText(raw)
        }
        guard let element = node as? Element else { return "" }

        switch element.safeTag() {
        case "strong", "b":
            return "**" + convertInlines(element) + "**"
        case "em", "i":
            return "*" + convertInlines(element) + "*"
        case "code":
            let code = element.safeText()
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "|", with: "\\|")
            return "`" + code + "`"
        case "del", "s", "strike":
            return "~~" + convertInlines(element) + "~~"
        case "br":
            return "  \n"
        case "a":
            return renderLink(element)
        case "img":
            return renderImage(element)
        case "span", "font":
            return convertInlines(element)
        case "o:p":
            return ""
        default:
            return convertInlines(element)
        }
    }

    private mutating func renderLink(_ element: Element) -> String {
        let label = convertInlines(element)
        let href = element.safeAttr("href")
        guard let scheme = href.split(separator: ":", maxSplits: 1).first,
              Self.safeLinkSchemes.contains(scheme.lowercased()) else {
            return label
        }
        if scheme.lowercased() == "mailto", label == String(href.dropFirst("mailto:".count)) {
            return "<\(label)>"
        }
        return "[\(label)](\(href))"
    }

    private mutating func renderImage(_ element: Element) -> String {
        let alt = element.safeAttr("alt")
        let src = element.safeAttr("src")
        guard let scheme = src.split(separator: ":", maxSplits: 1).first,
              scheme.lowercased() == "http" || scheme.lowercased() == "https" else {
            return escapeText(alt)
        }
        let escapedAlt = alt.replacingOccurrences(of: "]", with: "\\]")
        return "![\(escapedAlt)](\(src))"
    }

    private func escapeText(_ string: String) -> String {
        var result = ""
        for char in string {
            switch char {
            case "\\": result += "\\\\"
            case "`": result += "\\`"
            case "*": result += "\\*"
            case "_": result += "\\_"
            case "[": result += "\\["
            case "]": result += "\\]"
            case "#": result += "\\#"
            case "|": result += "\\|"
            default: result.append(char)
            }
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Element {
    func safeTag() -> String {
        (try? tagName())?.lowercased() ?? ""
    }

    func safeAttr(_ name: String) -> String {
        (try? attr(name)) ?? ""
    }

    func safeText() -> String {
        (try? text()) ?? ""
    }

    func hasMatchingDescendants(_ selector: String) -> Bool {
        (try? !select(selector).isEmpty()) ?? false
    }

    func isBlock() -> Bool {
        switch safeTag() {
        case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li",
             "blockquote", "pre", "table", "thead", "tbody", "tr", "td", "th", "hr":
            true
        default:
            false
        }
    }
}
