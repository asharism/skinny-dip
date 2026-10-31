import SwiftUI
import WebKit

/// CodeMirror 6 running in a WKWebView. `editor.html` and the prebuilt
/// `editor.bundle.js` are loaded from the app bundle; nothing touches the network.
struct Editor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.writingToolsBehavior = .complete
        configuration.userContentController.add(context.coordinator, name: "spike")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
        webView.navigationDelegate = context.coordinator

        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("Resources"),
              case let page = resources.appendingPathComponent("editor.html"),
              FileManager.default.fileExists(atPath: page.path)
        else {
            Coordinator.log("editor.html missing from the app bundle")
            return webView
        }
        webView.loadFileURL(page, allowingReadAccessTo: resources)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static func log(_ message: String) {
            print("[CodeMirrorSpike] \(message)")
            fflush(stdout)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.window?.makeFirstResponder(webView)
            Task {
                do {
                    // Passing the text as an argument lets WebKit serialize it; no string escaping.
                    _ = try await webView.callAsyncJavaScript(
                        "return setDocument(text)",
                        arguments: ["text": SampleDocument.text],
                        contentWorld: .page
                    )
                } catch {
                    Self.log("setDocument failed: \(error)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            Self.log("navigation failed: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            Self.log("provisional navigation failed: \(error)")
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            Self.log("js: \(message.body)")
        }
    }
}
