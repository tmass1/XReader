import SwiftUI
import WebKit

struct XWebView: NSViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let dataStore = WKWebsiteDataStore.default()
        config.websiteDataStore = dataStore

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        config.preferences.isElementFullscreenEnabled = true
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        context.coordinator.webView = webView

        let request = URLRequest(url: appState.currentURL)
        webView.load(request)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if appState.shouldRefresh {
            webView.reload()
            DispatchQueue.main.async { appState.shouldRefresh = false }
        }
        if appState.shouldGoBack {
            webView.goBack()
            DispatchQueue.main.async { appState.shouldGoBack = false }
        }
        if appState.shouldGoForward {
            webView.goForward()
            DispatchQueue.main.async { appState.shouldGoForward = false }
        }

        if webView.url != appState.currentURL,
           context.coordinator.lastNavigatedURL != appState.currentURL {
            context.coordinator.lastNavigatedURL = appState.currentURL
            let request = URLRequest(url: appState.currentURL)
            webView.load(request)
        }

        webView.pageZoom = appState.zoomLevel

        context.coordinator.injectCSS()
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var appState: AppState
        var webView: WKWebView?
        var lastNavigatedURL: URL?

        init(appState: AppState) {
            self.appState = appState
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.appState.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.appState.isLoading = false
                self.appState.pageTitle = webView.title ?? "X Reader"
                if let url = webView.url {
                    self.appState.currentURL = url
                    self.lastNavigatedURL = url
                }
            }
            // Re-inject CSS after page loads (X is an SPA, needs re-injection)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.injectCSS() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.injectCSS() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.appState.isLoading = false }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let host = url.host ?? ""
                let allowedDomains = [
                    "x.com", "twitter.com", "t.co",
                    "abs.twimg.com", "pbs.twimg.com", "video.twimg.com",
                    "api.x.com", "api.twitter.com",
                    "accounts.google.com", "appleid.apple.com"
                ]
                let isAllowed = allowedDomains.contains { domain in
                    host == domain || host.hasSuffix("." + domain)
                }
                if isAllowed || url.scheme == "about" {
                    decisionHandler(.allow)
                } else {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    // If this was a server redirect (e.g. t.co → external site),
                    // the web view already navigated away from X. Go back to restore it.
                    if navigationAction.navigationType == .other {
                        DispatchQueue.main.async {
                            webView.goBack()
                        }
                    }
                }
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func injectCSS() {
            guard let webView = webView else { return }

            var cssRules: [String] = []

            if appState.minimalMode {
                cssRules.append(contentsOf: [
                    "a[href=\"/compose/post\"], a[data-testid=\"SideNav_NewTweet_Button\"] { display: none !important; }",
                    "aside[aria-label=\"Subscribe to Premium\"], a[href=\"/i/premium_sign_up\"] { display: none !important; }",
                    "a[href=\"/i/verified-orgs-signup\"] { display: none !important; }",
                    "header[role=\"banner\"] { display: none !important; }",
                    "main[role=\"main\"] { margin-left: 0 !important; }",
                    "div[data-testid=\"getVerified\"], div[data-testid=\"inlinePrompt\"] { display: none !important; }",
                ])
            }

            if appState.forceDarkMode {
                cssRules.append("body { background-color: #000 !important; color-scheme: dark !important; }")
            }

            let cssString = cssRules.joined(separator: "\n")
            let escapedCSS = cssString
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")

            let js = """
            (function() {
                var s = document.getElementById('xreader-custom-css');
                if (s) s.remove();
                var style = document.createElement('style');
                style.id = 'xreader-custom-css';
                style.textContent = '\(escapedCSS)';
                document.head.appendChild(style);
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
