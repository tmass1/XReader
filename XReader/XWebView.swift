import SwiftUI
import WebKit

struct XWebView: NSViewRepresentable {
    @EnvironmentObject var appState: AppState
    var cornerRadius: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        webView.wantsLayer = true
        webView.layer?.cornerRadius = cornerRadius
        webView.layer?.cornerCurve = .continuous
        webView.layer?.masksToBounds = true

        context.coordinator.attach(to: webView)
        context.coordinator.applyStyles(XWebView.css(for: appState))

        webView.pageZoom = appState.zoomLevel
        webView.load(URLRequest(url: appState.currentURL))
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
            context.coordinator.navigate(to: appState.currentURL)
        }

        if webView.pageZoom != appState.zoomLevel {
            webView.pageZoom = appState.zoomLevel
        }

        context.coordinator.applyStyles(XWebView.css(for: appState))
    }

    static func css(for state: AppState) -> String {
        var rules: [String] = []

        if state.minimalMode {
            rules += [
                // Upsells and compose entry points
                "a[href=\"/compose/post\"], a[data-testid=\"SideNav_NewTweet_Button\"] { display: none !important; }",
                "aside[aria-label=\"Subscribe to Premium\"], a[href=\"/i/premium_sign_up\"], a[href=\"/i/verified-orgs-signup\"] { display: none !important; }",
                "div[data-testid=\"getVerified\"], div[data-testid=\"inlinePrompt\"] { display: none !important; }",
                // X's own nav and trends column; XReader's rail replaces them
                "header[role=\"banner\"] { display: none !important; }",
                "[data-testid=\"sidebarColumn\"] { display: none !important; }",
                // One centered reading column without side rules
                "main[role=\"main\"] { margin-left: 0 !important; align-items: center !important; }",
                "[data-testid=\"primaryColumn\"] { margin-left: auto !important; margin-right: auto !important; border-left-color: transparent !important; border-right-color: transparent !important; }",
            ]
        }

        if state.forceDarkMode {
            rules.append("body { background-color: #000 !important; color-scheme: dark !important; }")
        }

        return rules.joined(separator: "\n")
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var appState: AppState
        var lastNavigatedURL: URL?
        private weak var webView: WKWebView?
        private var observations: [NSKeyValueObservation] = []
        private var appliedCSS: String?

        init(appState: AppState) {
            self.appState = appState
        }

        // KVO keeps state in sync with X's client-side (pushState) navigation,
        // which never fires didFinish.
        func attach(to webView: WKWebView) {
            self.webView = webView
            observations = [
                webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                    guard let self, let url = wv.url else { return }
                    DispatchQueue.main.async {
                        self.lastNavigatedURL = url
                        if self.appState.currentURL != url { self.appState.currentURL = url }
                    }
                },
                webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.appState.pageTitle = wv.title ?? "X Reader" }
                },
                webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.appState.isLoading = wv.isLoading }
                },
                webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.appState.canGoBack = wv.canGoBack }
                },
                webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.appState.canGoForward = wv.canGoForward }
                },
            ]
        }

        // Once X is running, route through its own client-side router so switching
        // sections is instant instead of a full reload behind X's splash screen.
        func navigate(to url: URL) {
            guard let webView else { return }
            guard isXHost(url), isXHost(webView.url), !webView.isLoading else {
                webView.load(URLRequest(url: url))
                return
            }
            var path = url.path.isEmpty ? "/" : url.path
            if let query = url.query { path += "?" + query }

            webView.callAsyncJavaScript(Self.routerNavigation, arguments: ["path": path], in: nil, in: .page) { result in
                if case .success(let handled) = result, handled as? Bool == true { return }
                webView.load(URLRequest(url: url))
            }
        }

        private func isXHost(_ url: URL?) -> Bool {
            guard let host = url?.host else { return false }
            return host == "x.com" || host.hasSuffix(".x.com")
        }

        private static let routerNavigation = """
        if (!document.querySelector('main[role="main"]')) return false;
        let target = path;
        // /profile and /lists aren't X routes; resolve them through the signed-in user's handle.
        if (target === '/profile' || target === '/lists') {
            const profile = document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
            if (!profile) return false;
            target = profile.getAttribute('href') + (target === '/lists' ? '/lists' : '');
        }
        const link = [...document.querySelectorAll('header[role="banner"] a[href]')].find(a => a.getAttribute('href') === target);
        if (link) {
            link.click();
        } else {
            history.pushState(null, '', target);
            dispatchEvent(new PopStateEvent('popstate', { state: null }));
        }
        return true;
        """

        // Installs the stylesheet at document start (no flash of X's own chrome on load)
        // and updates the live page; skips work when nothing changed.
        func applyStyles(_ css: String) {
            guard css != appliedCSS, let webView else { return }
            appliedCSS = css

            guard let data = try? JSONEncoder().encode(css),
                  let literal = String(data: data, encoding: .utf8) else { return }
            let js = """
            (function() {
                var s = document.getElementById('xreader-style');
                if (!s) {
                    s = document.createElement('style');
                    s.id = 'xreader-style';
                    (document.head || document.documentElement).appendChild(s);
                }
                s.textContent = \(literal);
            })();
            """

            let controller = webView.configuration.userContentController
            controller.removeAllUserScripts()
            controller.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let host = url.host ?? ""
            let allowedDomains = [
                "x.com", "twitter.com", "t.co",
                "abs.twimg.com", "pbs.twimg.com", "video.twimg.com",
                "api.x.com", "api.twitter.com",
                "accounts.google.com", "appleid.apple.com"
            ]
            let isAllowed = allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
            if isAllowed || url.scheme == "about" {
                decisionHandler(.allow)
            } else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                // A server redirect (e.g. t.co → external) already left X; go back to restore it.
                if navigationAction.navigationType == .other {
                    DispatchQueue.main.async { webView.goBack() }
                }
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
