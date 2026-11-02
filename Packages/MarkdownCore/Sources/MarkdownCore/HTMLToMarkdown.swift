import Foundation
import SwiftSoup

// SwiftSoup (MIT): pasted HTML from Word, Outlook, and webmail is malformed,
// namespaced, and littered with conditional comments and `<o:p>`. A hand-rolled
// scanner would spend most of its code recovering tags; SwiftSoup's tolerant
// parser keeps this module focused on mapping structure to Markdown.

/// Converts clipboard HTML to Markdown Source for Paste as Markdown (⌘V).
///
/// Structure survives (headings, paragraphs, line breaks, emphasis, code,
/// links, lists, tasks, quotes, tables, rules); styling doesn't. Fonts, colors,
/// classes, images and comments are dropped. Text is escaped only where it
/// would otherwise turn into Markdown syntax, so pasted prose stays readable.
public enum HTMLToMarkdown {
    public static func convert(_ html: String) -> String {
        guard let document = parse(html) else { return "" }
        var converter = Converter()
        let root: Element = document.body() ?? document
        return converter.document(root)
    }

    /// True when the HTML is a code editor's styled copy of plain text (VS Code,
    /// JetBrains, a lone `<pre>`): the plain-text flavor is the real content,
    /// and converting would escape the Markdown the user copied.
    public static func isStyledPlainText(_ html: String) -> Bool {
        guard let document = parse(html), let body = document.body() else { return false }
        let roots = body.children().array().filter { !$0.isIgnorable }
        guard roots.count == 1, let root = roots.first else { return false }
        if root.tag == "pre" { return true }
        let style = root.style
        if style.range(of: #"white-space\s*:\s*pre"#, options: .regularExpression) != nil { return true }
        return Converter.isMonospace(style)
    }

    private static func parse(_ html: String) -> Document? {
        guard let document = try? SwiftSoup.parse(stripFragmentHeader(html)) else { return nil }
        _ = try? document.select(
            "head, script, style, template, noscript, img, picture, svg, video, audio, iframe, object, canvas, map"
        ).remove()
        markWordFakeLists(in: document)
        return document
    }

    /// Windows' CF_HTML header (`Version:0.9 StartHTML:…`) sometimes rides along.
    private static func stripFragmentHeader(_ html: String) -> String {
        guard html.hasPrefix("Version:"), let start = html.firstIndex(of: "<") else { return html }
        return String(html[start...])
    }

    /// Word and Outlook write lists as `<p style="mso-list:l0 level2 lfo1">`
    /// with the bullet or number in a `mso-list:Ignore` span. Record the level
    /// and marker on the paragraph, then drop the marker spans everywhere.
    private static func markWordFakeLists(in document: Document) {
        let ignore = "[style*=mso-list:Ignore], [style*=mso-list: Ignore]"
        let paragraphs = (try? document.select("p[style*=mso-list]").array()) ?? []
        for paragraph in paragraphs {
            let style = paragraph.style.lowercased()
            guard !style.contains("mso-list:ignore"), !style.contains("mso-list: ignore"),
                  !style.contains("mso-list:none") else { continue }
            let level = style.firstMatch(of: /level(\d+)/).flatMap { Int($0.1) } ?? 1
            let marker = (try? paragraph.select(ignore).first()?.text()) ?? ""
            _ = try? paragraph.attr("data-sd-list-level", String(level))
            _ = try? paragraph.attr("data-sd-list-marker", marker.collapsingWhitespace().trimmed())
        }
        _ = try? document.select(ignore).remove()
    }
}

// MARK: - Blocks

private struct Block {
    enum Kind { case paragraph, heading, line, gap, other }
    var text: String
    var kind: Kind
}

/// A hard line break while inline content is being collected. Resolved into
/// `"  \n"` (or a paragraph break, for two in a row) when the block finishes.
private let breakMark: Character = "\u{E000}"

private struct Converter {
    var inTableCell = false

    mutating func document(_ root: Element) -> String {
        join(blocks(root.getChildNodes()))
    }

    /// Splits a container's children into blocks. Inline runs between blocks
    /// become their own lines, the way a browser makes anonymous blocks.
    mutating func blocks(_ nodes: [Node]) -> [Block] {
        var result: [Block] = []
        var inlineRun: [Node] = []
        var index = 0

        func flush(_ converter: inout Converter) {
            defer { inlineRun.removeAll() }
            guard !inlineRun.isEmpty else { return }
            let text = converter.finishParagraph(converter.inline(inlineRun))
            if !text.isEmpty {
                result.append(Block(text: text, kind: .line))
            } else if inlineRun.contains(where: { ($0 as? Element)?.tag == "br" }) {
                // Google Docs and Gmail put a bare `<br>` between blocks for a blank line.
                result.append(Block(text: "", kind: .gap))
            }
        }

        while index < nodes.count {
            let node = nodes[index]
            guard let element = node as? Element else {
                if node is TextNode { inlineRun.append(node) }
                index += 1
                continue
            }
            if element.wordListLevel != nil {
                flush(&self)
                var items: [Element] = []
                while index < nodes.count {
                    if let next = nodes[index] as? Element, next.wordListLevel != nil {
                        items.append(next)
                    } else if !nodes[index].isBlankText {
                        break
                    }
                    index += 1
                }
                result.append(Block(text: wordList(items), kind: .other))
                continue
            }
            if element.isBlockLevel || element.hasBlockDescendant {
                flush(&self)
                result.append(contentsOf: block(element))
            } else {
                inlineRun.append(element)
            }
            index += 1
        }
        flush(&self)
        return result
    }

    private mutating func block(_ element: Element) -> [Block] {
        switch element.tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            return heading(element, level: Int(String(element.tag.last!)) ?? 1)
        case "p":
            if element.className.lowercased() == "msotitle" { return heading(element, level: 1) }
            if element.hasBlockDescendant { return blocks(element.getChildNodes()) }
            let text = finishParagraph(inline(element.getChildNodes()))
            return [Block(text: text, kind: text.isEmpty ? .gap : .paragraph)]
        case "ul", "ol":
            let text = list(element)
            return text.isEmpty ? [] : [Block(text: text, kind: .other)]
        case "blockquote":
            let inner = join(blocks(element.getChildNodes()))
            guard !inner.isEmpty else { return [] }
            let quoted = inner.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n")
            return [Block(text: quoted, kind: .other)]
        case "pre":
            return [Block(text: codeBlock(element), kind: .other)]
        case "table":
            let text = table(element)
            return text.isEmpty ? [] : [Block(text: text, kind: .other)]
        case "hr":
            return [Block(text: "---", kind: .other)]
        case "br":
            return [Block(text: "", kind: .gap)]
        default:
            if element.hasBlockDescendant {
                return blocks(element.getChildNodes())
            }
            // Gmail, Apple Mail and Outlook on the web write one `<div>` per line,
            // with `<div><br></div>` for a blank line.
            let text = finishParagraph(inline(element.getChildNodes()))
            if text.isEmpty { return [Block(text: "", kind: .gap)] }
            return [Block(text: text, kind: element.tag == "div" ? .line : .paragraph)]
        }
    }

    private mutating func heading(_ element: Element, level: Int) -> [Block] {
        var text = emit(inlineRuns(element.getChildNodes(), style: Style())).replacingOccurrences(of: String(breakMark), with: " ").collapsingSpaces().trimmed()
        guard !text.isEmpty else { return [] }
        // A trailing ` #` would be read as a closing sequence and vanish.
        if text.hasSuffix(" #") { text = String(text.dropLast()) + "\\#" }
        return [Block(text: String(repeating: "#", count: level) + " " + text, kind: .heading)]
    }

    private func join(_ blocks: [Block]) -> String {
        var output = ""
        var previous: Block?
        var sawGap = false
        for block in blocks {
            if block.kind == .gap {
                sawGap = true
                continue
            }
            if let previous {
                if !sawGap, previous.kind == .line, block.kind == .line {
                    output += "  \n"
                } else if !sawGap, previous.kind == .heading, block.kind == .heading {
                    output += "\n"
                } else {
                    output += "\n\n"
                }
            }
            output += block.text
            previous = block
            sawGap = false
        }
        return output
    }

    // MARK: Lists

    private mutating func list(_ list: Element) -> String {
        let ordered = list.tag == "ol"
        var number = Int(list.attribute("start")) ?? 1
        let children = list.children().array()
        // Google Docs puts a `<p role="presentation">` in every item of a tight list.
        let loose = children.contains { item in
            item.tag == "li" && item.children().array().contains { $0.tag == "p" && $0.attribute("role") != "presentation" }
        }

        var items: [String] = []
        var lastWidth = 2
        for child in children {
            switch child.tag {
            case "li":
                let marker = ordered ? "\(number). " : "- "
                number += 1
                lastWidth = marker.count
                items.append(listItem(child, marker: marker, loose: loose))
            case "ul", "ol":
                // Google Docs nests lists as siblings of the `<li>`, not inside it.
                let nested = indent(self.list(child), by: lastWidth)
                guard !nested.isEmpty else { continue }
                if items.isEmpty { items.append(nested) } else { items[items.count - 1] += "\n" + nested }
            default:
                continue
            }
        }
        return items.joined(separator: loose ? "\n\n" : "\n")
    }

    private mutating func listItem(_ item: Element, marker: String, loose: Bool) -> String {
        let parts = blocks(item.getChildNodes())
        var body = loose ? join(parts) : parts.filter { $0.kind != .gap }.map(\.text).joined(separator: "\n")
        body = body.replacing(/^[•·◦▪●∙]\s*/, with: "")

        var box = ""
        if body.hasPrefix("☐") || body.hasPrefix("☑") {
            box = body.hasPrefix("☑") ? "[x] " : "[ ] "
            body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard !body.isEmpty else { return (marker + box).trimmed() }
        // Continuation lines line up with the text after the marker, or CommonMark
        // ends the item (and `1. ` needs three spaces, not two).
        return marker + box + indent(body, by: marker.count, skippingFirstLine: true)
    }

    private func indent(_ text: String, by width: Int, skippingFirstLine: Bool = false) -> String {
        let pad = String(repeating: " ", count: width)
        return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { offset, line in
            line.isEmpty || (skippingFirstLine && offset == 0) ? String(line) : pad + line
        }.joined(separator: "\n")
    }

    private mutating func wordList(_ paragraphs: [Element]) -> String {
        var widths: [Int] = []
        var counters: [Int] = []
        var lines: [String] = []
        for paragraph in paragraphs {
            let depth = min(max((paragraph.wordListLevel ?? 1) - 1, 0), widths.count)
            let rawMarker = paragraph.attribute("data-sd-list-marker")
            let ordered = rawMarker.wholeMatch(of: /\(?([0-9]+|[a-zA-Z]|[ivxlcdmIVXLCDM]+)[.)]/) != nil
            if counters.count > depth + 1 { counters.removeLast(counters.count - depth - 1) }
            if counters.count == depth + 1 {
                counters[depth] += 1
            } else {
                counters.append(Int(rawMarker.filter(\.isNumber)) ?? 1)
            }
            let marker = ordered ? "\(counters[depth]). " : "- "
            widths = Array(widths.prefix(depth)) + [marker.count]
            let pad = String(repeating: " ", count: widths.dropLast().reduce(0, +))
            let text = finishParagraph(inline(paragraph.getChildNodes()))
            lines.append(pad + marker + indent(text, by: pad.count + marker.count, skippingFirstLine: true))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Code

    private func codeBlock(_ pre: Element) -> String {
        var body = Self.preformattedText(pre.getChildNodes())
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
        if body.hasPrefix("\n") { body.removeFirst() }
        while body.hasSuffix("\n") { body.removeLast() }

        var fence = "```"
        while body.contains(fence) { fence += "`" }
        return "\(fence)\(Self.language(of: pre))\n\(body)\n\(fence)"
    }

    private static func preformattedText(_ nodes: [Node]) -> String {
        var text = ""
        for node in nodes {
            if let textNode = node as? TextNode {
                text += textNode.getWholeText()
            } else if let element = node as? Element {
                switch element.tag {
                case "br":
                    text += "\n"
                case "div", "p":
                    if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
                    text += preformattedText(element.getChildNodes())
                    if !text.hasSuffix("\n") { text += "\n" }
                default:
                    text += preformattedText(element.getChildNodes())
                }
            }
        }
        return text
    }

    private static func language(of pre: Element) -> String {
        var candidates = [pre]
        if let code = try? pre.select("code").first() { candidates.append(code) }
        if let parent = pre.parent() { candidates.append(parent) }
        for element in candidates {
            for name in element.className.split(separator: " ") {
                for prefix in ["language-", "lang-", "highlight-source-"] where name.hasPrefix(prefix) {
                    let language = name.dropFirst(prefix.count)
                    if !language.isEmpty, language.allSatisfy({ $0.isLetter || $0.isNumber || "+-#_.".contains($0) }) {
                        return String(language)
                    }
                }
            }
        }
        return ""
    }

    // MARK: Tables

    private mutating func table(_ table: Element) -> String {
        var rows: [Element] = []
        for section in table.children().array() {
            switch section.tag {
            case "thead", "tbody", "tfoot":
                rows += section.children().array().filter { $0.tag == "tr" }
            case "tr":
                rows.append(section)
            default:
                continue
            }
        }
        if let head = rows.firstIndex(where: { $0.parent()?.tag == "thead" }), head > 0 {
            rows.insert(rows.remove(at: head), at: 0)
        }
        guard !rows.isEmpty else { return "" }

        let wasInCell = inTableCell
        inTableCell = true
        defer { inTableCell = wasInCell }

        var cells: [[String]] = []
        var alignments: [String] = []
        for (offset, row) in rows.enumerated() {
            let rowCells = row.children().array().filter { $0.tag == "td" || $0.tag == "th" }
            cells.append(rowCells.map { cell in
                blocks(cell.getChildNodes()).filter { $0.kind != .gap }.map(\.text).joined(separator: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .collapsingSpaces()
                    .trimmed()
            })
            if offset == 0 {
                alignments = rowCells.map(Self.alignment)
                // Word and Outlook bold their header rows; Markdown headers are bold already.
                cells[0] = cells[0].map(Self.unbolded)
            }
        }
        let columns = cells.map(\.count).max() ?? 0
        guard columns > 0 else { return "" }
        alignments += Array(repeating: "----", count: max(0, columns - alignments.count))

        func line(_ row: [String]) -> String {
            let padded = row + Array(repeating: "", count: columns - row.count)
            return "| " + padded.joined(separator: " | ") + " |"
        }
        return ([line(cells[0]), line(alignments)] + cells.dropFirst().map(line)).joined(separator: "\n")
    }

    private static func unbolded(_ cell: String) -> String {
        guard cell.count > 4, cell.hasPrefix("**"), cell.hasSuffix("**") else { return cell }
        let inner = cell.dropFirst(2).dropLast(2)
        return inner.contains("**") ? cell : String(inner)
    }

    private static func alignment(_ cell: Element) -> String {
        var align = cell.attribute("align").lowercased()
        if align.isEmpty, let match = cell.style.lowercased().firstMatch(of: /text-align\s*:\s*(left|center|right)/) {
            align = String(match.1)
        }
        switch align {
        case "left": return ":---"
        case "center": return ":----:"
        case "right": return "----:"
        default: return "----"
        }
    }

    // MARK: Inline

    struct Style: Equatable {
        var bold = false
        var italic = false
        var strike = false
    }

    struct Run {
        var text: String
        var style: Style
        /// Already Markdown (a code span or link): never escaped.
        var isMarkup = false
    }

    mutating func inline(_ nodes: [Node]) -> String {
        emit(inlineRuns(nodes, style: Style()))
    }

    private mutating func inlineRuns(_ nodes: [Node], style: Style) -> [Run] {
        var runs: [Run] = []
        for node in nodes {
            if let text = node as? TextNode {
                let collapsed = text.getWholeText().collapsingWhitespace()
                if !collapsed.isEmpty { runs.append(Run(text: collapsed, style: style)) }
            } else if let element = node as? Element {
                runs += inlineRuns(element, style: style)
            }
        }
        return runs
    }

    private mutating func inlineRuns(_ element: Element, style: Style) -> [Run] {
        let css = element.style.lowercased()
        var inner = style
        switch element.tag {
        case "br":
            return [Run(text: String(breakMark), style: style)]
        case "o:p":
            return []
        case "code", "kbd", "samp", "tt":
            return [Run(text: codeSpan(element.rawText), style: style, isMarkup: true)]
        case "a":
            return [Run(text: link(element), style: style, isMarkup: true)]
        case "strong", "b":
            inner.bold = true
        case "em", "i", "cite", "dfn", "var":
            inner.italic = true
        case "del", "s", "strike":
            inner.strike = true
        default:
            if Self.isMonospace(css), !element.hasBlockDescendant {
                return [Run(text: codeSpan(element.rawText), style: style, isMarkup: true)]
            }
        }
        // Google Docs wraps the whole copy in `<b style="font-weight:normal">` and
        // marks real bold on spans; Outlook and Teams do the same with styles.
        if css.range(of: #"font-weight\s*:\s*(bold|bolder|[6-9]00)"#, options: .regularExpression) != nil {
            inner.bold = true
        } else if css.range(of: #"font-weight\s*:\s*(normal|lighter|[1-4]00)"#, options: .regularExpression) != nil {
            inner.bold = false
        }
        if css.range(of: #"font-style\s*:\s*italic"#, options: .regularExpression) != nil {
            inner.italic = true
        } else if css.range(of: #"font-style\s*:\s*normal"#, options: .regularExpression) != nil {
            inner.italic = false
        }
        if css.contains("line-through") { inner.strike = true }

        var runs = inlineRuns(element.getChildNodes(), style: inner)
        if element.isBlockLevel {
            runs.insert(Run(text: String(breakMark), style: style), at: 0)
            runs.append(Run(text: String(breakMark), style: style))
        }
        return runs
    }

    static func isMonospace(_ css: String) -> Bool {
        guard let family = css.lowercased().firstMatch(of: /font-family\s*:\s*([^;]+)/)?.1 else { return false }
        // Only the first family counts: "Calibri, monospace" is a fallback chain.
        let first = family.split(separator: ",").first?
            .trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) ?? ""
        return [
            "monospace", "menlo", "monaco", "consolas", "courier", "courier new", "sf mono", "ui-monospace",
            "source code pro", "fira code", "jetbrains mono", "cascadia code", "cascadia mono", "lucida console",
        ].contains(first)
    }

    private func codeSpan(_ raw: String) -> String {
        var code = raw.collapsingWhitespace()
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return code }
        // GFM splits table cells before inline parsing, so even code needs `\|`.
        if inTableCell { code = code.replacingOccurrences(of: "|", with: "\\|") }
        // Backslash escapes don't work inside code spans; a longer fence does.
        let longest = code.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
        let fence = String(repeating: "`", count: longest + 1)
        let pad = code.hasPrefix("`") || code.hasSuffix("`") ? " " : ""
        return fence + pad + code + pad + fence
    }

    private mutating func link(_ element: Element) -> String {
        let label = emit(inlineRuns(element.getChildNodes(), style: Style()))
            .replacingOccurrences(of: String(breakMark), with: " ")
            .collapsingSpaces()
            .trimmed()
        let href = element.attribute("href").trimmed()
        let scheme = href.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
        guard ["http", "https", "mailto"].contains(scheme), href.contains(":") else { return label }

        let address = scheme == "mailto" ? String(href.dropFirst("mailto:".count)) : href
        if label.isEmpty || Self.unescape(label) == address || Self.unescape(label) == href {
            return "<\(address)>"
        }
        let destination = href.contains(" ") || href.contains("(") || href.contains(")")
            ? "<\(href.replacingOccurrences(of: ">", with: "%3E"))>"
            : href
        return "[\(label)](\(destination))"
    }

    private static func unescape(_ text: String) -> String {
        text.replacing(/\\(.)/) { String($0.1) }
    }

    /// Writes runs as Markdown, opening and closing emphasis only where the style
    /// changes so adjacent runs (Word splits words into many) merge, and keeping
    /// spaces outside the delimiters, where CommonMark needs them.
    private func emit(_ runs: [Run]) -> String {
        var output = ""
        var open: [String] = []

        func close(keeping style: Style) {
            while open.contains(where: { !Self.style(style, has: $0) }), let top = open.popLast() {
                let trailing = output.trailingSpace
                output.removeLast(trailing.count)
                output += top + trailing
            }
        }

        for run in runs {
            let text = run.isMarkup ? run.text : escape(run.text)
            if text.allSatisfy({ $0 == " " || $0 == breakMark }) {
                output += text
                continue
            }
            close(keeping: run.style)
            let leading = text.leadingSpace
            output += leading
            for delimiter in ["~~", "**", "*"] where Self.style(run.style, has: delimiter) && !open.contains(delimiter) {
                output += delimiter
                open.append(delimiter)
            }
            output += text.dropFirst(leading.count)
        }
        close(keeping: Style())
        return output
    }

    private static func style(_ style: Style, has delimiter: String) -> Bool {
        switch delimiter {
        case "~~": style.strike
        case "**": style.bold
        case "*": style.italic
        default: false
        }
    }

    private func escape(_ text: String) -> String {
        let characters = Array(text)
        let tildes = characters.filter { $0 == "~" }.count
        var result = ""
        for (index, char) in characters.enumerated() {
            let before = index > 0 ? characters[index - 1] : " "
            let after = index + 1 < characters.count ? characters[index + 1] : " "
            switch char {
            case "\\", "`", "*", "[", "]":
                result += "\\\(char)"
            case "_":
                // An underscore inside a word (snake_case) can't start emphasis.
                let inWord = (before.isLetter || before.isNumber) && (after.isLetter || after.isNumber)
                result += inWord ? "_" : "\\_"
            case "|" where inTableCell:
                result += "\\|"
            case "~" where tildes > 1:
                result += "\\~"
            case "&":
                let rest = String(characters[(index + 1)...].prefix(12))
                result += rest.firstMatch(of: /^#?[A-Za-z0-9]+;/) == nil ? "&" : "\\&"
            default:
                result.append(char)
            }
        }
        return result
    }

    /// Resolves break marks into hard breaks (two in a row: a paragraph break)
    /// and escapes what would read as block syntax at the start of a line.
    mutating func finishParagraph(_ text: String) -> String {
        let lines = text.split(separator: breakMark, omittingEmptySubsequences: false)
            .map { String($0).collapsingSpaces().trimmed() }
        var output = ""
        var pendingBreak: String?
        for line in lines {
            if line.isEmpty {
                if pendingBreak != nil { pendingBreak = "\n\n" }
                continue
            }
            if let pendingBreak { output += pendingBreak }
            output += Self.escapeLineStart(line)
            pendingBreak = "  \n"
        }
        return output
    }

    private static func escapeLineStart(_ line: String) -> String {
        if line.firstMatch(of: /^#{1,6}(\s|$)/) != nil { return "\\" + line }
        if line.hasPrefix(">") || line.hasPrefix("~~~") { return "\\" + line }
        if line.firstMatch(of: /^[-+](\s|$)/) != nil { return "\\" + line }
        if line.wholeMatch(of: /[=\-]+/) != nil { return "\\" + line }
        if let match = line.firstMatch(of: /^(\d{1,9})([.)])(\s|$)/) {
            return String(match.1) + "\\" + line.dropFirst(match.1.count)
        }
        return line
    }
}

// MARK: - Helpers

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HTML whitespace rules: runs of spaces, tabs and newlines are one space.
    /// Non-breaking spaces become plain spaces; zero-width characters go.
    func collapsingWhitespace() -> String {
        var result = ""
        var lastWasSpace = false
        for char in self {
            if char == "\u{200B}" || char == "\u{FEFF}" { continue }
            if char == " " || char == "\t" || char == "\n" || char == "\r\n" || char == "\r"
                || char == "\u{000C}" || char == "\u{00A0}" {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(char)
                lastWasSpace = false
            }
        }
        return result
    }

    func collapsingSpaces() -> String {
        replacing(/\ {2,}/, with: " ")
    }

    var leadingSpace: String {
        String(prefix { $0 == " " || $0 == breakMark })
    }

    var trailingSpace: String {
        String(reversed().prefix { $0 == " " || $0 == breakMark }.reversed())
    }
}

private extension Node {
    var isBlankText: Bool {
        if let text = self as? TextNode { return text.getWholeText().collapsingWhitespace().trimmed().isEmpty }
        return !(self is Element)
    }
}

private extension Element {
    var tag: String { tagName().lowercased() }
    var style: String { attribute("style") }
    var className: String { (try? self.className()) ?? "" }

    /// Text with whitespace as written; callers collapse it.
    var rawText: String {
        getChildNodes().map { node in
            if let text = node as? TextNode { return text.getWholeText() }
            if let element = node as? Element { return element.tag == "br" ? " " : element.rawText }
            return ""
        }.joined()
    }

    func attribute(_ name: String) -> String {
        (try? attr(name)) ?? ""
    }

    var wordListLevel: Int? {
        tag == "p" ? Int(attribute("data-sd-list-level")) : nil
    }

    var isIgnorable: Bool {
        ["meta", "link", "title", "o:p", "br"].contains(tag)
    }

    var isBlockLevel: Bool {
        Self.blockTags.contains(tag)
    }

    /// Descendants only: SwiftSoup's `select` would match the element itself.
    var hasBlockDescendant: Bool {
        children().array().contains { $0.isBlockLevel || $0.hasBlockDescendant }
    }

    static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "center", "dd", "details", "div", "dl", "dt",
        "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
        "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section", "summary", "table", "ul",
    ]
}
