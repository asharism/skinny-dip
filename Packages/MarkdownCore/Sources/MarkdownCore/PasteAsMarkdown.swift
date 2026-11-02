import Foundation

/// The pasteboard flavors Paste as Markdown reads, already pulled off the
/// platform pasteboard, so the choice between them is testable without AppKit.
public struct PasteboardContents: Sendable, Equatable {
    /// Our private flavor: the Markdown Source of a Skinny Dip copy.
    public var skinnyDipMarkdown: String?
    /// `public.html`, or the main resource of a web archive (Safari, Mail).
    public var html: String?
    /// `public.utf8-plain-text`, or the text of an RTF-only copy.
    public var plainText: String?

    public init(skinnyDipMarkdown: String? = nil, html: String? = nil, plainText: String? = nil) {
        self.skinnyDipMarkdown = skinnyDipMarkdown
        self.html = html
        self.plainText = plainText
    }
}

public enum PasteAsMarkdown {
    /// Paste as Markdown (⌘V). Our own copies paste their exact Markdown Source;
    /// rich text from other apps is converted; anything else pastes as plain text.
    public static func text(for contents: PasteboardContents) -> String? {
        if let markdown = nonEmpty(contents.skinnyDipMarkdown) {
            return normalizingNewlines(markdown)
        }
        let plain = nonEmpty(contents.plainText)
        if let html = nonEmpty(contents.html) {
            // A code editor's copy is styled plain text: converting it would
            // escape the Markdown the user copied from VS Code.
            if let plain, HTMLToMarkdown.isStyledPlainText(html) {
                return normalizingNewlines(plain)
            }
            if let markdown = nonEmpty(HTMLToMarkdown.convert(html)) {
                return markdown
            }
        }
        return plain.map(normalizingNewlines)
    }

    /// Paste and Match Style (⌥⇧⌘V): the plain-text flavor, never converted.
    public static func plainText(for contents: PasteboardContents) -> String? {
        nonEmpty(contents.plainText).map(normalizingNewlines)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func normalizingNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

/// Decodes the HTML that apps put on the pasteboard.
public enum PasteboardHTML {
    /// `public.html` bytes. Mostly UTF-8, but Word and older apps may write
    /// UTF-16 with a byte-order mark or a legacy charset named in a `<meta>`.
    public static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        let charset = head.firstMatch(of: /charset\s*=\s*["']?([a-z0-9_\-]+)/).map { String($0.1) } ?? "windows-1252"
        return String(data: data, encoding: encoding(named: charset)) ?? String(data: data, encoding: .windowsCP1252)
    }

    /// The main resource of a `com.apple.webarchive`, which Safari and Mail put
    /// on the pasteboard, sometimes without a `public.html` flavor.
    public static func fromWebArchive(_ data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let main = plist["WebMainResource"] as? [String: Any],
              let body = main["WebResourceData"] as? Data
        else { return nil }
        if let mime = main["WebResourceMIMEType"] as? String, !mime.lowercased().contains("html") {
            return nil
        }
        if let name = main["WebResourceTextEncodingName"] as? String,
           let text = String(data: body, encoding: encoding(named: name.lowercased())) {
            return text
        }
        return decode(body)
    }

    private static func encoding(named name: String) -> String.Encoding {
        switch name {
        case "utf-8", "utf8": .utf8
        case "utf-16", "utf-16le", "utf-16be": .utf16
        case "iso-8859-1", "latin1", "latin-1": .isoLatin1
        case "macintosh", "x-mac-roman": .macOSRoman
        case "shift_jis", "shift-jis": .shiftJIS
        default: .windowsCP1252
        }
    }
}
