// MouseVisualizerView.swift
// SwiftUI view that renders the SVG inline in a transparent WKWebView and toggles
// the real SVG elements (CSS classes) in response to MouseInputMonitor.
//
// Usage:  MouseVisualizerView().aspectRatio(520.0 / 1000.0, contentMode: .fit)

import SwiftUI
import WebKit

struct MouseVisualizerView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground") // let the app's dark background show through
        web.navigationDelegate = context.coordinator
        context.coordinator.attach(to: web)
        web.loadHTMLString(Self.page, baseURL: nil)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
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

    private static let page = #"""
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      html,body{margin:0;height:100%;background:transparent;overflow:hidden}
      svg#mouse{width:100%;height:100%;display:block}
      /* Press / release: short fade so it feels instant but not harsh. */
      [data-btn]{transition:fill 60ms ease-out}
      [data-btn].on{fill:#FF922E}
      #wheel-ridges{transition:stroke 80ms ease-out}
      svg.scrolling #wheel-ridges{stroke:#FF922E}
      /* Distinct up/down feedback: orange glow on the leading half of the wheel. */
      svg.scroll-up   #wheel-body:not(.on){fill:url(#scroll-up-fill)}
      svg.scroll-down #wheel-body:not(.on){fill:url(#scroll-down-fill)}
    </style></head><body>
    \#(MouseSVG.markup)
    <script>
      const svg = document.getElementById('mouse');
      const ridges = document.getElementById('wheel-ridges');
      const KEYS = ['left','right','middle','back','forward'];
      function setState(s){
        for (const k of KEYS)
          document.querySelectorAll('[data-btn="'+k+'"]').forEach(e => e.classList.toggle('on', !!s[k]));
      }
      let scrollTimer;
      function scrollStep(dir){            // dir: -1 = wheel rolled up, 1 = down
        svg.classList.add('scrolling');
        svg.classList.toggle('scroll-up', dir < 0);
        svg.classList.toggle('scroll-down', dir > 0);
        ridges.animate(
          [{transform:'translateY(0px)'},{transform:'translateY('+(dir*4)+'px)'},{transform:'translateY(0px)'}],
          {duration:90, easing:'ease-out'});
        clearTimeout(scrollTimer);
        scrollTimer = setTimeout(() => svg.classList.remove('scrolling','scroll-up','scroll-down'), 160);
      }
    </script></body></html>
    """#
}
