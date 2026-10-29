// MouseVisualizerView.swift
// SwiftUI view that renders the dark and light SVGs inline in a transparent WKWebView,
// cross-fades between them when the app theme changes, and toggles the real SVG elements
// (CSS classes) in response to MouseInputMonitor.
//
// Usage:  MouseVisualizerView(isDark: isDarkMode).aspectRatio(520.0 / 1000.0, contentMode: .fit)

import SwiftUI
import WebKit

/// WKWebView without the built-in right-click menu (Reload, Back, Inspect Element…).
private final class VisualizerWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
    }
}

struct MouseVisualizerView: NSViewRepresentable {
    var isDark: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = VisualizerWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground") // let the app's panel show through
        web.navigationDelegate = context.coordinator
        context.coordinator.theme = isDark
        context.coordinator.attach(to: web)
        web.loadHTMLString(Self.page(dark: isDark), baseURL: nil)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.setTheme(dark: isDark)
    }

    /// Runs when the view leaves the hierarchy: removes the event monitors.
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let monitor = MouseInputMonitor()
        private weak var web: WKWebView?
        private var pageLoaded = false
        private var pendingPressed: Set<MouseControl> = []
        var theme = true

        func attach(to web: WKWebView) {
            self.web = web
            monitor.onPressedChange = { [weak self] in self?.push(pressed: $0) }
            monitor.onScrollStep = { [weak self] dir in
                guard self?.pageLoaded == true else { return }
                self?.web?.evaluateJavaScript("scrollStep(\(dir.rawValue))")
            }
            monitor.start()
        }

        func detach() {
            monitor.stop()
            monitor.onPressedChange = nil
            monitor.onScrollStep = nil
        }

        func setTheme(dark: Bool) {
            guard dark != theme else { return }
            theme = dark
            guard pageLoaded else { return } // initial page already uses the latest `theme`
            web?.evaluateJavaScript("setTheme(\(dark))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            webView.evaluateJavaScript("setTheme(\(theme))") // covers a toggle during page load
            push(pressed: pendingPressed)
        }

        private func push(pressed: Set<MouseControl>) {
            guard pageLoaded else { pendingPressed = pressed; return }
            let fields = MouseControl.allCases
                .map { "\($0.svgName):\(pressed.contains($0))" }
                .joined(separator: ",")
            web?.evaluateJavaScript("setState({\(fields)})")
        }
    }

    // MARK: - Page

    private static func page(dark: Bool) -> String {
        let theme = dark ? "dark" : "light"
        let darkSVG = MouseSVG.markup
        let lightSVG = MouseSVG.markupLight
        return #"""
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html,body{margin:0;height:100%;background:transparent;overflow:hidden;
            -webkit-user-select:none;user-select:none}
          #stage{position:relative;width:100%;height:100%}
          .layer{position:absolute;inset:0;pointer-events:none;
            transition:opacity 450ms ease-in-out}
          svg.mouse{width:100%;height:100%;display:block}
          /* Theme cross-fade: both SVGs stay in the DOM, only opacity changes. */
          body.dark  .layer.light{opacity:0}
          body.light .layer.dark{opacity:0}
          /* Press / release: short fade so it feels instant but not harsh. */
          [data-btn]{transition:fill 60ms ease-out}
          [data-btn].on{fill:#FF922E}
          .ridges{transition:stroke 80ms ease-out}
          svg.scrolling .ridges{stroke:#FF922E}
          /* Distinct up/down feedback: orange glow on the leading half of the wheel. */
          svg.scroll-up   .wheel-body:not(.on){fill:url(#scroll-up-fill)}
          svg.scroll-down .wheel-body:not(.on){fill:url(#scroll-down-fill)}
        </style></head>
        <body class="\#(theme)">
        <div id="stage">
          <div class="layer dark">\#(darkSVG)</div>
          <div class="layer light">\#(lightSVG)</div>
        </div>
        <script>
          document.addEventListener('contextmenu', e => e.preventDefault());
          const svgs = Array.from(document.querySelectorAll('svg.mouse'));
          const ridges = Array.from(document.querySelectorAll('.ridges'));
          const KEYS = ['left','right','middle','back','forward'];
          function setTheme(dark){
            document.body.classList.toggle('dark', dark);
            document.body.classList.toggle('light', !dark);
          }
          function setState(s){
            for (const k of KEYS)
              document.querySelectorAll('[data-btn="'+k+'"]').forEach(e => e.classList.toggle('on', !!s[k]));
          }
          let scrollTimer;
          function scrollStep(dir){            // dir: -1 = wheel rolled up, 1 = down
            svgs.forEach(v => {
              v.classList.add('scrolling');
              v.classList.toggle('scroll-up', dir < 0);
              v.classList.toggle('scroll-down', dir > 0);
            });
            ridges.forEach(r => r.animate(
              [{transform:'translateY(0px)'},{transform:'translateY('+(dir*4)+'px)'},{transform:'translateY(0px)'}],
              {duration:90, easing:'ease-out'}));
            clearTimeout(scrollTimer);
            scrollTimer = setTimeout(() => svgs.forEach(v => v.classList.remove('scrolling','scroll-up','scroll-down')), 160);
          }
        </script></body></html>
        """#
    }
}
