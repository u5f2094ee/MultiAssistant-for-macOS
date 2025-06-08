import Cocoa
import WebKit
import Carbon.HIToolbox.Events // For kVK_ constants

// NEW: Custom view class to allow mouse events to pass through it
class ClickThroughNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // By returning nil, we are telling the system that this view should not handle the mouse event,
        // and the event should be passed to the next view in the hierarchy (i.e., the webview below it).
        return nil
    }
}


class ViewController: NSViewController,
                     WKNavigationDelegate,
                     WKUIDelegate,
                     NSWindowDelegate,
                     WKDownloadDelegate {

    // MARK: - UI Elements & State
    private var webView1: WKWebView!
    private var webView2: WKWebView!
    private var visualEffectView: NSVisualEffectView!
    private var temperatureOverlayView: ClickThroughNSView!

    // Configuration constants
    private let defaultUrlString1 = "https://chat.openai.com/"
    private let defaultUrlString2 = "https://gemini.google.com/app"
    private let cornerRadiusValue: CGFloat = 30.0
    private let zoomStep: CGFloat   = 0.1
    private let minZoom: CGFloat    = 0.5
    private let maxZoom: CGFloat    = 3.0
    private let windowAutosaveName = "MultiAssistantMainWindow_v1"

    // UserDefaults keys
    static let windowAlphaKey = "windowAlphaKey_MultiAssistant_v1"
    static let webViewAlphaKey = "webViewAlphaKey_MultiAssistant_v1"
    static let windowDesktopAssignmentKey = "windowDesktopAssignmentKey_v2"
    static let globalBoldFontKey = "globalBoldFontEnabledKey_MultiAssistant_v1"
    static let webpageTemperatureKey = "webpageTemperatureKey_v1"

    // Runtime state
    private var webView1ZoomScale: CGFloat = 1.0
    private var webView2ZoomScale: CGFloat = 1.0
    private var urlString1: String!
    private var urlString2: String!
    private var currentWindowAlpha: CGFloat = 1.0
    private var currentWebViewAlpha: CGFloat = 0.8
    private var currentDesktopAssignmentRawValue: UInt = NSWindow.CollectionBehavior.canJoinAllSpaces.rawValue
    private var globalBoldFontEnabled: Bool = false
    private var currentWebpageTemperature: Double = 50.0

    private var webViewsReloadingAfterTermination: Set<WKWebView> = []
    private var activeWebView: WKWebView { webView1.isHidden ? webView2 : webView1 }
    private var windowChromeConfigured = false

    // MARK: - View / Window Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("VC: viewDidLoad")
        loadSettings()
        configureContainerLayer()
        setupVisualEffectView()
        setupWebViews()
        setupTemperatureOverlay()
        loadInitialContent()
        setupKeyboardShortcuts()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else {
            NSLog("VC: viewDidAppear - NO WINDOW when viewDidAppear was called.")
            return
        }
        NSLog("VC: viewDidAppear. Window isVisible: \(window.isVisible), isKey: \(window.isKeyWindow), AppIsActive: \(NSApp.isActive)")

        if !windowChromeConfigured {
            setupWindowChrome()
            windowChromeConfigured = true
        }

        if window.isKeyWindow {
             NSLog("VC: viewDidAppear - Window is already key. Calling attemptWebViewFocus.")
             attemptWebViewFocus()
        } else {
             NSLog("VC: viewDidAppear - Window is NOT key. Waiting for windowDidBecomeKey or AppDelegate trigger.")
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSLog("VC: windowDidBecomeKey. AppIsActive: \(NSApp.isActive)")
        attemptWebViewFocus()
    }

    func windowDidResignKey(_ notification: Notification) {
        NSLog("VC: windowDidResignKey. AppIsActive: \(NSApp.isActive)")
    }

    // MARK: - UI Setup Helpers
    private func configureContainerLayer() {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadiusValue
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        NSLog("VC: Container layer background set to clear for blur effect.")
        view.layer?.borderWidth = 1.9
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        NSLog("VC: Container layer configured with custom border.")
    }

    private func setupVisualEffectView() {
        visualEffectView = NSVisualEffectView()
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .hudWindow
        NSLog("VC: VisualEffectView material set to .underWindowBackground.")
        visualEffectView.state = .active
        view.addSubview(visualEffectView, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: view.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        NSLog("VC: VisualEffectView setup complete.")
    }
    
    private func setupTemperatureOverlay() {
        temperatureOverlayView = ClickThroughNSView()
        temperatureOverlayView.translatesAutoresizingMaskIntoConstraints = false
        temperatureOverlayView.wantsLayer = true
        temperatureOverlayView.layer?.backgroundColor = NSColor.clear.cgColor

        view.addSubview(temperatureOverlayView)
        NSLayoutConstraint.activate([
            temperatureOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            temperatureOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            temperatureOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            temperatureOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        NSLog("VC: Temperature overlay view setup.")
        applyTemperatureEffect()
    }

    private func setupWebViews() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let cssString = "html, body { background-color: transparent !important; }"
        let userScript = WKUserScript(source: cssString, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)

        webView1 = WKWebView(frame: .zero, configuration: config)
        webView2 = WKWebView(frame: .zero, configuration: config)

        let webViews: [WKWebView] = [webView1, webView2]
        for wv in webViews {
            wv.setValue(false, forKey: "drawsBackground")
            wv.alphaValue = currentWebViewAlpha
            NSLog("VC: Set WKWebView alphaValue to \(currentWebViewAlpha) for semi-transparent web content.")
            wv.navigationDelegate = self
            wv.uiDelegate = self
            // The download delegate is set on the WKDownload object itself, not here.
            // This line was causing the error and has been removed.
            wv.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(wv)
            NSLayoutConstraint.activate([
                wv.topAnchor.constraint(equalTo: view.topAnchor),
                wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }
        
        webView2.isHidden = true
        NSLog("VC: WebViews setup complete with transparency for blur effect and \(currentWebViewAlpha * 100)% opaque content.")
    }

    private func setupWindowChrome() {
        guard let window = view.window else {
            NSLog("VC: setupWindowChrome - No window found.")
            return
        }
        NSLog("VC: setupWindowChrome - Configuring window...")
        window.delegate = self
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = currentWindowAlpha
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.setFrameAutosaveName(windowAutosaveName)
        window.collectionBehavior = NSWindow.CollectionBehavior(rawValue: currentDesktopAssignmentRawValue)
        NSLog("VC: setupWindowChrome - Set window collectionBehavior to rawValue: \(currentDesktopAssignmentRawValue)")

        if !window.setFrameUsingName(window.frameAutosaveName) || window.frame.width < 100 || window.frame.height < 100 {
            NSLog("VC: setupWindowChrome - Setting default window frame (800x600).")
            window.setFrame(NSRect(x: 200, y: 200, width: 800, height: 600), display: true)
            window.center()
        } else {
             NSLog("VC: setupWindowChrome - Window frame restored from autosave: \(window.frame)")
        }

        NSLog("VC: setupWindowChrome - Activating app and making window key and front.")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.setAppWindow(window)
            NSLog("VC: setupWindowChrome - Passed window reference to AppDelegate.")
        } else {
            NSLog("VC: setupWindowChrome - Could not pass window reference to AppDelegate.")
        }
        NSLog("VC: setupWindowChrome - Configuration complete. Initial window alpha: \(currentWindowAlpha)")
    }

    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers else { return event }
            if self.view.window?.attachedSheet != nil { return event } // Ignore if a sheet (like settings) is open
            switch key.lowercased() {
            case "1": self.togglePage(); return nil
            case "r": self.refreshCurrentPage(); return nil
            case "=","+", "§": self.zoomInPage(); return nil
            case "-": self.zoomOutPage(); return nil
            case "0": self.actualSizePage(); return nil
            case ",": self.openSettings(); return nil
            default: return event
            }
        }
        NSLog("VC: Keyboard shortcuts setup.")
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        urlString1 = d.string(forKey: "customURL1_MultiAssistant_v1") ?? defaultUrlString1
        urlString2 = d.string(forKey: "customURL2_MultiAssistant_v1") ?? defaultUrlString2
        let savedZoom1 = d.float(forKey: "webView1ZoomScale_MultiAssistant_v1")
        webView1ZoomScale = (savedZoom1 > 0.01) ? CGFloat(savedZoom1) : 1.0
        let savedZoom2 = d.float(forKey: "webView2ZoomScale_MultiAssistant_v1")
        webView2ZoomScale = (savedZoom2 > 0.01) ? CGFloat(savedZoom2) : 1.0

        if d.object(forKey: ViewController.windowAlphaKey) != nil {
            currentWindowAlpha = CGFloat(d.double(forKey: ViewController.windowAlphaKey))
        } else {
            currentWindowAlpha = 1.0
            d.set(currentWindowAlpha, forKey: ViewController.windowAlphaKey)
        }
        currentWindowAlpha = clamp(currentWindowAlpha, min: 0.1, max: 1.0)

        if d.object(forKey: ViewController.webViewAlphaKey) != nil {
            currentWebViewAlpha = CGFloat(d.double(forKey: ViewController.webViewAlphaKey))
        } else {
            currentWebViewAlpha = 0.8
            d.set(currentWebViewAlpha, forKey: ViewController.webViewAlphaKey)
        }
        currentWebViewAlpha = clamp(currentWebViewAlpha, min: 0.1, max: 1.0)

        if d.object(forKey: ViewController.windowDesktopAssignmentKey) != nil {
            currentDesktopAssignmentRawValue = UInt(d.integer(forKey: ViewController.windowDesktopAssignmentKey))
        } else {
            currentDesktopAssignmentRawValue = NSWindow.CollectionBehavior.canJoinAllSpaces.rawValue
            d.set(Int(currentDesktopAssignmentRawValue), forKey: ViewController.windowDesktopAssignmentKey)
        }
        
        if d.object(forKey: ViewController.globalBoldFontKey) != nil {
            globalBoldFontEnabled = d.bool(forKey: ViewController.globalBoldFontKey)
        } else {
            globalBoldFontEnabled = false
            d.set(globalBoldFontEnabled, forKey: ViewController.globalBoldFontKey)
        }
        
        if d.object(forKey: ViewController.webpageTemperatureKey) != nil {
            currentWebpageTemperature = d.double(forKey: ViewController.webpageTemperatureKey)
        } else {
            currentWebpageTemperature = 50.0
            d.set(currentWebpageTemperature, forKey: ViewController.webpageTemperatureKey)
        }

        NSLog("VC: Settings loaded. URL1: \(urlString1 ?? "nil"), URL2: \(urlString2 ?? "nil"), Zoom1: \(webView1ZoomScale), Zoom2: \(webView2ZoomScale), WindowAlpha: \(currentWindowAlpha), WebViewAlpha: \(currentWebViewAlpha), DesktopAssignment: \(currentDesktopAssignmentRawValue), GlobalBold: \(globalBoldFontEnabled), Temperature: \(currentWebpageTemperature)")
    }

    private func loadInitialContent() {
        if let u1 = URL(string: urlString1) { webView1.load(URLRequest(url: u1)) } else { NSLog("VC: Invalid URL1: \(urlString1 ?? "nil")")}
        if let u2 = URL(string: urlString2) { webView2.load(URLRequest(url: u2)) } else { NSLog("VC: Invalid URL2: \(urlString2 ?? "nil")")}
    }
    
    // MARK: - Content Styling (Global Bold & Temperature)
    private func applyGlobalBoldStyle(to webView: WKWebView) {
        let js: String
        if globalBoldFontEnabled {
            js = """
            var styleElement = document.getElementById('multiAssistantGlobalBoldStyle');
            if (!styleElement) {
                styleElement = document.createElement('style');
                styleElement.id = 'multiAssistantGlobalBoldStyle';
                document.head.appendChild(styleElement);
            }
            styleElement.innerHTML = '*, *::before, *::after { font-weight: bold !important; }';
            """
        } else {
            js = """
            var styleElement = document.getElementById('multiAssistantGlobalBoldStyle');
            if (styleElement) { styleElement.parentNode.removeChild(styleElement); }
            """
        }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    private func updateGlobalBoldStyleForAllWebViews() {
        applyGlobalBoldStyle(to: webView1)
        applyGlobalBoldStyle(to: webView2)
        NSLog("VC: Updated global bold style for all webviews. Enabled: \(globalBoldFontEnabled)")
    }
    
    private func applyTemperatureEffect() {
        guard temperatureOverlayView != nil else { return }

        let value = currentWebpageTemperature
        let maxAlpha: CGFloat = 0.25

        if value < 49.0 {
            let alpha = (50.0 - value) / 50.0 * maxAlpha
            temperatureOverlayView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(alpha).cgColor
        } else if value > 51.0 {
            let alpha = (value - 50.0) / 50.0 * maxAlpha
            temperatureOverlayView.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(alpha).cgColor
        } else {
            temperatureOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        NSLog("VC: Applied temperature effect. Value: \(value)")
    }


    // MARK: - Focus Handling
    @objc func attemptWebViewFocus() {
        NSLog("VC: attemptWebViewFocus called.")
        guard let window = self.view.window else { NSLog("VC: attemptWebViewFocus - No window."); return }
        let webViewToFocus = self.activeWebView
        let webViewName = webViewToFocus == self.webView1 ? "WebView1" : "WebView2"
        NSLog("VC: attemptWebViewFocus for \(webViewName). AppIsActive: \(NSApp.isActive), WindowIsKey: \(window.isKeyWindow), WindowIsVisible: \(window.isVisible)")
        if !window.isKeyWindow {
            NSLog("VC: attemptWebViewFocus - Window is NOT key. Attempting to make it key.")
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSLog("VC: attemptWebViewFocus (after 0.05s delay) - WindowIsKey: \(window.isKeyWindow)")
                if window.isKeyWindow { self.proceedWithFirstResponder(for: webViewToFocus, window: window) }
                else { NSLog("VC: attemptWebViewFocus (delayed) - Window STILL NOT key."); self.proceedWithFirstResponder(for: webViewToFocus, window: window) }
            }
            return
        }
        proceedWithFirstResponder(for: webViewToFocus, window: window)
    }

    private func proceedWithFirstResponder(for webViewToFocus: WKWebView, window: NSWindow) {
        let webViewName = webViewToFocus == self.webView1 ? "WebView1" : "WebView2"
        NSLog("VC: proceedWithFirstResponder for \(webViewName). Current FR before: \(String(describing: window.firstResponder))")
        if window.makeFirstResponder(webViewToFocus) {
            NSLog("VC: proceedWithFirstResponder - SUCCESS: Made \(webViewName) first responder.")
            executeJavaScriptFocus(reason: "proceedWithFirstResponder_success")
        } else {
            NSLog("VC: proceedWithFirstResponder - FAILED: Could not make \(webViewName) first responder.")
            if window.firstResponder != webViewToFocus && window.canBecomeKey {
                 NSLog("VC: proceedWithFirstResponder - Making window's content view (self.view) first responder as a fallback.")
                 if window.makeFirstResponder(self.view) { NSLog("VC: proceedWithFirstResponder - SUCCESS: Made self.view first responder.") }
                 else { NSLog("VC: proceedWithFirstResponder - FAILED: Could not make self.view first responder either.") }
                 executeJavaScriptFocus(reason: "proceedWithFirstResponder_fallbackFR_self.view")
            }
        }
    }

    private func executeJavaScriptFocus(reason: String) {
        let webViewToFocus = self.activeWebView
        let javascript = """
            (function() {
                let focusableElements = ['#prompt-textarea', 'textarea:not([disabled]):not([readonly])', 'input[type="text"]:not([disabled]):not([readonly])', 'input:not([type="hidden"]):not([disabled]):not([readonly])', 'div[contenteditable="true"]:not([disabled])', '[tabindex]:not([tabindex="-1"]):not([disabled])'];
                for (let selector of focusableElements) {
                    let target = document.querySelector(selector);
                    if (target) {
                        if (typeof target.focus === 'function') { target.focus({ preventScroll: false }); }
                        return;
                    }
                }
                if (document.body && typeof document.body.focus === 'function') { document.body.focus(); }
            })();
        """
        webViewToFocus.evaluateJavaScript(javascript, completionHandler: nil)
    }

    // MARK: - Actions & Web Control
    @objc func togglePage() {
        NSLog("VC: Toggling page.")
        webView1.isHidden.toggle()
        webView2.isHidden.toggle()
        let currentActiveWebView = activeWebView
        view.addSubview(currentActiveWebView)
        view.addSubview(temperatureOverlayView)
        applyZoom(to: activeWebView, scale: currentZoom(for: activeWebView))
        NSLog("VC: Calling attemptWebViewFocus after page toggle.")
        attemptWebViewFocus()
        NSLog("VC: Active webview is now: \(activeWebView == webView1 ? "WebView1" : "WebView2")")
    }

    @objc func refreshCurrentPage() {
        NSLog("VC: Refreshing current page: \(activeWebView == webView1 ? "WebView1" : "WebView2")")
        webViewsReloadingAfterTermination.insert(activeWebView)
        activeWebView.reload()
    }

    @objc func zoomInPage()  { changeZoom(by: +zoomStep) }
    @objc func zoomOutPage() { changeZoom(by: -zoomStep) }
    @objc func actualSizePage() { setZoom(1.0, for: activeWebView) }

    private func changeZoom(by delta: CGFloat) {
        let oldScale = currentZoom(for: activeWebView)
        let newScale = clamp(oldScale + delta, min: minZoom, max: maxZoom)
        setZoom(newScale, for: activeWebView)
    }

    private func currentZoom(for wv: WKWebView) -> CGFloat { (wv == webView1) ? webView1ZoomScale : webView2ZoomScale }

    private func setZoom(_ scale: CGFloat, for wv: WKWebView) {
        let targetScaleKey: String
        if wv == webView1 { webView1ZoomScale = scale; targetScaleKey = "webView1ZoomScale_MultiAssistant_v1" }
        else { webView2ZoomScale = scale; targetScaleKey = "webView2ZoomScale_MultiAssistant_v1" }
        UserDefaults.standard.set(Float(scale), forKey: targetScaleKey)
        applyZoom(to: wv, scale: scale)
        NSLog("VC: Zoom set to \(scale) for \(wv == webView1 ? "WebView1" : "WebView2")")
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat { Swift.max(min, Swift.min(max, value)) }

    private func applyZoom(to wv: WKWebView, scale: CGFloat) {
        let js = "document.documentElement.style.zoom = '\(scale * 100)%';"
        wv.evaluateJavaScript(js) { _, err in if let err = err { NSLog("VC: Zoom JS error: %@", err.localizedDescription) } }
    }

    // MARK: - WKNavigationDelegate
    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
        let webViewName = wv == webView1 ? "WebView1" : "WebView2"
        NSLog("VC: WebView \(webViewName) didFinish navigation. URL: \(wv.url?.absoluteString ?? "N/A").")
        applyZoom(to: wv, scale: currentZoom(for: wv))
        applyGlobalBoldStyle(to: wv)
        
        if view.window?.isKeyWindow == true || webViewsReloadingAfterTermination.contains(wv) {
            NSLog("VC: WebView \(webViewName) finished, attempting focus (window is key or was reloading).")
            attemptWebViewFocus()
        } else { NSLog("VC: WebView \(webViewName) finished, but window not key and not specifically reloading. Focus not attempted automatically.") }
        webViewsReloadingAfterTermination.remove(wv)
    }

    func webViewWebContentProcessDidTerminate(_ wv: WKWebView) {
        let webViewName = wv == webView1 ? "WebView1" : "WebView2"
        NSLog("VC: CRITICAL - WebView \(webViewName) content process did terminate. Reloading.")
        webViewsReloadingAfterTermination.insert(wv)
        wv.reload()
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *), navigationAction.shouldPerformDownload {
            NSLog("VC: Navigation action should perform download. Deciding to download.")
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            if #available(macOS 11.3, *) {
                NSLog("VC: MIME type cannot be shown. Deciding to download. URL: \(navigationResponse.response.url?.absoluteString ?? "N/A")")
                decisionHandler(.download)
            } else {
                if let url = navigationResponse.response.url {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    showClipboardNotification(message: "Download URL has been copied")
                }
                decisionHandler(.cancel)
            }
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let webViewName = (webView == webView1) ? "Page 1" : "Page 2"
        NSLog("VC: \(webViewName) failed provisional navigation: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let webViewName = (webView == webView1) ? "Page 1" : "Page 2"
        NSLog("VC: \(webViewName) failed navigation: \(error.localizedDescription)")
    }
    
    // MARK: - WKUIDelegate & Download Handling
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        NSLog("VC: createWebViewWith triggered for URL: \(url.absoluteString). Intercepting as potential download.")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)

        showClipboardNotification(message: "Download URL has been copied")

        return nil
    }
    
    private func showClipboardNotification(message: String) {
        for subview in view.subviews where subview.tag == 999 {
            subview.removeFromSuperview()
        }

        let notificationLabel = NSTextField(labelWithString: message)
        notificationLabel.tag = 999
        notificationLabel.translatesAutoresizingMaskIntoConstraints = false
        notificationLabel.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.85)
        notificationLabel.textColor = .white
        notificationLabel.alignment = .center
        notificationLabel.font = .systemFont(ofSize: 14, weight: .medium)
        notificationLabel.wantsLayer = true
        notificationLabel.layer?.cornerRadius = 12
        notificationLabel.isBezeled = false
        notificationLabel.drawsBackground = true
        notificationLabel.alphaValue = 0.0

        view.addSubview(notificationLabel)
        notificationLabel.layer?.zPosition = .greatestFiniteMagnitude
        
        NSLayoutConstraint.activate([
            notificationLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            notificationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            notificationLabel.widthAnchor.constraint(equalToConstant: 320),
            notificationLabel.heightAnchor.constraint(equalToConstant: 44)
        ])

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            notificationLabel.animator().alphaValue = 1.0
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.5
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    notificationLabel.animator().alphaValue = 0.0
                }, completionHandler: {
                    notificationLabel.removeFromSuperview()
                })
            }
        })
        NSLog("VC: Displayed notification: '\(message)'")
    }
    
    // MARK: - WKDownloadDelegate
    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        NSLog("VC: Download delegate - navigationAction didBecome download")
        download.delegate = self
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        NSLog("VC: Download delegate - navigationResponse didBecome download")
        download.delegate = self
    }

    @available(macOS 11.3, *)
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: self.view.window!) { (result) in
            if result == .OK, let url = panel.url {
                NSLog("VC: Download destination chosen: \(url.path)")
                completionHandler(url)
            } else {
                NSLog("VC: User cancelled download.")
                download.cancel()
                completionHandler(nil)
            }
        }
    }

    @available(macOS 11.3, *)
    func downloadDidFinish(_ download: WKDownload) {
        NSLog("VC: Download finished successfully.")
        showClipboardNotification(message: "Download Complete!")
    }

    @available(macOS 11.3, *)
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        NSLog("VC: Download failed with error: \(error.localizedDescription)")
        showClipboardNotification(message: "Download Failed")
    }

    // MARK: - Settings Sheet (⌘,)
    @objc func openSettings() {
        NSLog("VC: Open Settings action triggered.")
        guard let window = view.window else {
            NSLog("VC: OpenSettings - No window. Attempting to show via AppDelegate.")
            (NSApp.delegate as? AppDelegate)?.showWindowAction()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.view.window != nil { self.presentSettingsAlert() }
                else { NSLog("VC: OpenSettings - Window still not available after delay and AppDelegate action.") }
            }
            return
        }
        if !window.isVisible || !window.isKeyWindow {
            NSLog("VC: OpenSettings - Window not visible/key. Activating and making key.")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.presentSettingsAlert() }
        } else { presentSettingsAlert() }
    }

    private func createSeparatorBox() -> NSBox {
        let separator = NSBox(); separator.boxType = .separator; separator.translatesAutoresizingMaskIntoConstraints = false; return separator
    }

    private func createSectionHeader(title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title); label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 1); label.isEditable = false; label.isSelectable = false; label.translatesAutoresizingMaskIntoConstraints = false; return label
    }

    private func presentSettingsAlert() {
        guard let window = self.view.window, window.isVisible, window.isKeyWindow else {
            NSLog("VC: PresentSettingsAlert - Window conditions not met (not visible or not key). Retrying if not key.")
            if let w = self.view.window, !w.isKeyWindow { w.makeKeyAndOrderFront(nil); DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.presentSettingsAlert() } }
            return
        }
        NSLog("VC: PresentSettingsAlert - Preparing settings UI.")
        let alert = NSAlert(); alert.messageText = "MultiAssistant Settings"; alert.informativeText = "Customize URLs, window behavior, global shortcuts, and appearance."; alert.addButton(withTitle: "Save Changes"); alert.addButton(withTitle: "Cancel")
        let desiredAccessoryViewWidth: CGFloat = 720; let labelColumnWidth: CGFloat = 160; let hStackSpacing: CGFloat = 12; let vStackRowSpacing: CGFloat = 16; let sectionHeaderSpacing: CGFloat = 8; let sectionBottomSpacing: CGFloat = 24; let outerPadding: CGFloat = 25

        func createSettingRow(labelString: String, control: NSView, alignment: NSLayoutConstraint.Attribute = .firstBaseline) -> NSStackView {
            let label = NSTextField(labelWithString: labelString); label.alignment = .right; label.translatesAutoresizingMaskIntoConstraints = false; label.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true
            control.translatesAutoresizingMaskIntoConstraints = false; control.setContentHuggingPriority(.defaultLow, for: .horizontal); control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let hStack = NSStackView(views: [label, control]); hStack.orientation = .horizontal; hStack.spacing = hStackSpacing; hStack.alignment = alignment
            if let textField = control as? NSTextField { textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true }
            if let segmentedControl = control as? NSSegmentedControl { segmentedControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true}
            return hStack
        }

        let urlSectionHeader = createSectionHeader(title: "Web Page URLs")
        let url1TextField = NSTextField(string: urlString1 ?? defaultUrlString1); url1TextField.placeholderString = "e.g., https://chat.openai.com"; let url1Row = createSettingRow(labelString: "Page 1 URL:", control: url1TextField)
        let url2TextField = NSTextField(string: urlString2 ?? defaultUrlString2); url2TextField.placeholderString = "e.g., https://gemini.google.com"; let url2Row = createSettingRow(labelString: "Page 2 URL:", control: url2TextField)

        let behaviorSectionHeader = createSectionHeader(title: "Window Behavior")
        let autohideCheckbox = NSButton(checkboxWithTitle: "Auto-hide window when application is inactive", target: nil, action: nil); autohideCheckbox.state = UserDefaults.standard.bool(forKey: AppDelegate.autohideWindowKey) ? .on : .off; autohideCheckbox.translatesAutoresizingMaskIntoConstraints = false
        let autohideIndentView = NSView(); autohideIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true; let autohideControlRow = NSStackView(views: [autohideIndentView, autohideCheckbox]); autohideControlRow.orientation = .horizontal; autohideControlRow.spacing = 0; autohideControlRow.alignment = .firstBaseline
        
        let desktopAssignmentControl = NSSegmentedControl(labels: ["All Desktops", "This Desktop", "Standard"], trackingMode: .selectOne, target: nil, action: nil)
        desktopAssignmentControl.segmentStyle = .texturedRounded
        if currentDesktopAssignmentRawValue == NSWindow.CollectionBehavior.canJoinAllSpaces.rawValue { desktopAssignmentControl.selectedSegment = 0
        } else if currentDesktopAssignmentRawValue == NSWindow.CollectionBehavior.moveToActiveSpace.rawValue { desktopAssignmentControl.selectedSegment = 1
        } else { desktopAssignmentControl.selectedSegment = 2 }
        let desktopAssignmentRow = createSettingRow(labelString: "Assign Window To:", control: desktopAssignmentControl, alignment: .centerY)

        let appearanceSectionHeader = createSectionHeader(title: "Window Appearance & Content")
        let windowAlphaSlider = NSSlider(value: Double(currentWindowAlpha), minValue: 0.1, maxValue: 1.0, target: nil, action: nil); windowAlphaSlider.allowsTickMarkValuesOnly = false; windowAlphaSlider.numberOfTickMarks = 10; windowAlphaSlider.translatesAutoresizingMaskIntoConstraints = false
        let currentWindowAlphaDisplayLabel = NSTextField(labelWithString: String(format: "Overall Opacity: %.0f%%", currentWindowAlpha * 100)); currentWindowAlphaDisplayLabel.isEditable = false; currentWindowAlphaDisplayLabel.isSelectable = false; currentWindowAlphaDisplayLabel.translatesAutoresizingMaskIntoConstraints = false; currentWindowAlphaDisplayLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let windowAlphaSliderAndDisplay = NSStackView(views: [windowAlphaSlider, currentWindowAlphaDisplayLabel]); windowAlphaSliderAndDisplay.orientation = .horizontal; windowAlphaSliderAndDisplay.spacing = hStackSpacing; windowAlphaSliderAndDisplay.alignment = .centerY
        let windowAlphaRow = createSettingRow(labelString: "Window Transparency:", control: windowAlphaSliderAndDisplay, alignment: .centerY)

        let webViewAlphaSlider = NSSlider(value: Double(currentWebViewAlpha), minValue: 0.1, maxValue: 1.0, target: nil, action: nil); webViewAlphaSlider.allowsTickMarkValuesOnly = false; webViewAlphaSlider.numberOfTickMarks = 10; webViewAlphaSlider.translatesAutoresizingMaskIntoConstraints = false
        let currentWebViewAlphaDisplayLabel = NSTextField(labelWithString: String(format: "Content Opacity: %.0f%%", currentWebViewAlpha * 100)); currentWebViewAlphaDisplayLabel.isEditable = false; currentWebViewAlphaDisplayLabel.isSelectable = false; currentWebViewAlphaDisplayLabel.translatesAutoresizingMaskIntoConstraints = false; currentWebViewAlphaDisplayLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let webViewAlphaSliderAndDisplay = NSStackView(views: [webViewAlphaSlider, currentWebViewAlphaDisplayLabel]); webViewAlphaSliderAndDisplay.orientation = .horizontal; webViewAlphaSliderAndDisplay.spacing = hStackSpacing; webViewAlphaSliderAndDisplay.alignment = .centerY
        let webViewAlphaRow = createSettingRow(labelString: "Web Page Opacity:", control: webViewAlphaSliderAndDisplay, alignment: .centerY)
        
        let temperatureSlider = NSSlider(value: currentWebpageTemperature, minValue: 0, maxValue: 100, target: nil, action: nil)
        temperatureSlider.allowsTickMarkValuesOnly = false; temperatureSlider.numberOfTickMarks = 11; temperatureSlider.translatesAutoresizingMaskIntoConstraints = false
        let temperatureDisplayLabel = NSTextField(labelWithString: "Cold / Warm"); temperatureDisplayLabel.isEditable = false; temperatureDisplayLabel.isSelectable = false; temperatureDisplayLabel.translatesAutoresizingMaskIntoConstraints = false; temperatureDisplayLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let temperatureSliderAndDisplay = NSStackView(views: [temperatureSlider, temperatureDisplayLabel]); temperatureSliderAndDisplay.orientation = .horizontal; temperatureSliderAndDisplay.spacing = hStackSpacing; temperatureSliderAndDisplay.alignment = .centerY
        let temperatureRow = createSettingRow(labelString: "Page Color Tone:", control: temperatureSliderAndDisplay, alignment: .centerY)

        let globalBoldFontCheckbox = NSButton(checkboxWithTitle: "Force Bold Font Style on Web Pages", target: nil, action: nil)
        globalBoldFontCheckbox.state = globalBoldFontEnabled ? .on : .off
        globalBoldFontCheckbox.translatesAutoresizingMaskIntoConstraints = false
        let boldFontIndentView = NSView(); boldFontIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true
        let boldFontRow = NSStackView(views: [boldFontIndentView, globalBoldFontCheckbox])
        boldFontRow.orientation = .horizontal; boldFontRow.spacing = 0; boldFontRow.alignment = .firstBaseline


        let globalShortcutSectionHeader = createSectionHeader(title: "Global Toggle Shortcut (Show/Hide Window)")
        let currentShortcutDisplayLabel = NSTextField(labelWithString: "Current: \( (NSApp.delegate as? AppDelegate)?.formattedShortcutString() ?? "Not Set" )"); currentShortcutDisplayLabel.isEditable = false; currentShortcutDisplayLabel.isSelectable = false
        let currentShortcutIndentView = NSView(); currentShortcutIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true; let currentShortcutRow = NSStackView(views: [currentShortcutIndentView, currentShortcutDisplayLabel]); currentShortcutRow.orientation = .horizontal; currentShortcutRow.alignment = .firstBaseline
        let keyTextField = NSTextField(string: (NSApp.delegate as? AppDelegate)?.currentShortcutKeyCharacter ?? ""); keyTextField.placeholderString = "e.g., . or A"; keyTextField.widthAnchor.constraint(equalToConstant: 70).isActive = true; let keyRow = createSettingRow(labelString: "Key:", control: keyTextField)
        let optionCheckbox = NSButton(checkboxWithTitle: "Option (⌥)", target: nil, action: nil); let commandCheckbox = NSButton(checkboxWithTitle: "Command (⌘)", target: nil, action: nil); let shiftCheckbox = NSButton(checkboxWithTitle: "Shift (⇧)", target: nil, action: nil); let controlCheckbox = NSButton(checkboxWithTitle: "Control (⌃)", target: nil, action: nil)
        if let appDelegate = NSApp.delegate as? AppDelegate { optionCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.option) ? .on : .off; commandCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.command) ? .on : .off; shiftCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.shift) ? .on : .off; controlCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.control) ? .on : .off }
        let modifiersCheckboxHStack = NSStackView(views: [optionCheckbox, commandCheckbox, shiftCheckbox, controlCheckbox]); modifiersCheckboxHStack.orientation = .horizontal; modifiersCheckboxHStack.spacing = hStackSpacing * 1.2; modifiersCheckboxHStack.alignment = .centerY; let modifiersRow = createSettingRow(labelString: "Modifiers:", control: modifiersCheckboxHStack, alignment: .centerY)

        let otherShortcutsSectionHeader = createSectionHeader(title: "In-App Shortcuts")
        let shortcutTogglePageLabel = NSTextField(labelWithString: "Toggle Page 1/2:  Command (⌘) + 1"); shortcutTogglePageLabel.isEditable = false; shortcutTogglePageLabel.isSelectable = false
        let togglePageIndentView = NSView(); togglePageIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true; let togglePageRow = NSStackView(views: [togglePageIndentView, shortcutTogglePageLabel]); togglePageRow.orientation = .horizontal; togglePageRow.alignment = .firstBaseline

        let mainVerticalStackView = NSStackView(); mainVerticalStackView.orientation = .vertical; mainVerticalStackView.spacing = vStackRowSpacing; mainVerticalStackView.alignment = .leading; mainVerticalStackView.edgeInsets = NSEdgeInsets(top: outerPadding, left: outerPadding, bottom: outerPadding, right: outerPadding)
        mainVerticalStackView.addArrangedSubview(urlSectionHeader); mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: urlSectionHeader); mainVerticalStackView.addArrangedSubview(url1Row); mainVerticalStackView.addArrangedSubview(url2Row); mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: url2Row); mainVerticalStackView.addArrangedSubview(createSeparatorBox()); mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)
        mainVerticalStackView.addArrangedSubview(behaviorSectionHeader); mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: behaviorSectionHeader)
        mainVerticalStackView.addArrangedSubview(autohideControlRow)
        mainVerticalStackView.addArrangedSubview(desktopAssignmentRow)
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: desktopAssignmentRow); mainVerticalStackView.addArrangedSubview(createSeparatorBox()); mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)
        mainVerticalStackView.addArrangedSubview(appearanceSectionHeader); mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: appearanceSectionHeader); mainVerticalStackView.addArrangedSubview(windowAlphaRow); mainVerticalStackView.addArrangedSubview(webViewAlphaRow)
        mainVerticalStackView.addArrangedSubview(temperatureRow)
        mainVerticalStackView.addArrangedSubview(boldFontRow)
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: boldFontRow); mainVerticalStackView.addArrangedSubview(createSeparatorBox()); mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)
        mainVerticalStackView.addArrangedSubview(globalShortcutSectionHeader); mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: globalShortcutSectionHeader); mainVerticalStackView.addArrangedSubview(currentShortcutRow); mainVerticalStackView.addArrangedSubview(keyRow); mainVerticalStackView.addArrangedSubview(modifiersRow); mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: modifiersRow); mainVerticalStackView.addArrangedSubview(createSeparatorBox()); mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)
        mainVerticalStackView.addArrangedSubview(otherShortcutsSectionHeader); mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: otherShortcutsSectionHeader); mainVerticalStackView.addArrangedSubview(togglePageRow)
        mainVerticalStackView.translatesAutoresizingMaskIntoConstraints = false; mainVerticalStackView.frame = NSRect(x: 0, y: 0, width: desiredAccessoryViewWidth, height: 10); mainVerticalStackView.layoutSubtreeIfNeeded()
        let requiredHeight = mainVerticalStackView.fittingSize.height; mainVerticalStackView.frame = NSRect(x: 0, y: 0, width: desiredAccessoryViewWidth, height: requiredHeight)
        alert.accessoryView = mainVerticalStackView
        if let accessory = alert.accessoryView { accessory.widthAnchor.constraint(equalToConstant: desiredAccessoryViewWidth).isActive = true }
        alert.window.layoutIfNeeded()

        alert.beginSheetModal(for: window) { response in
            self.handleSettingsAlertResponse(response, alert: alert, url1TF: url1TextField, url2TF: url2TextField, autohideCB: autohideCheckbox,
                                             desktopAssignmentControl: desktopAssignmentControl,
                                             windowAlphaSlider: windowAlphaSlider, windowAlphaDisplayLabel: currentWindowAlphaDisplayLabel,
                                             webViewAlphaSlider: webViewAlphaSlider, webViewAlphaDisplayLabel: currentWebViewAlphaDisplayLabel,
                                             temperatureSlider: temperatureSlider,
                                             globalBoldFontCB: globalBoldFontCheckbox,
                                             keyTF: keyTextField, optionCB: optionCheckbox, commandCB: commandCheckbox, shiftCB: shiftCheckbox, controlCB: controlCheckbox, currentShortcutDisplayLabel: currentShortcutDisplayLabel)
        }
    }

    private func handleSettingsAlertResponse(
        _ response: NSApplication.ModalResponse, alert: NSAlert,
        url1TF: NSTextField, url2TF: NSTextField, autohideCB: NSButton,
        desktopAssignmentControl: NSSegmentedControl,
        windowAlphaSlider: NSSlider, windowAlphaDisplayLabel: NSTextField,
        webViewAlphaSlider: NSSlider, webViewAlphaDisplayLabel: NSTextField,
        temperatureSlider: NSSlider,
        globalBoldFontCB: NSButton,
        keyTF: NSTextField, optionCB: NSButton, commandCB: NSButton, shiftCB: NSButton, controlCB: NSButton, currentShortcutDisplayLabel: NSTextField
    ) {
        if response == .alertFirstButtonReturn {
            NSLog("VC: Settings Save button clicked.")
            self.saveSettings(urlString: url1TF.stringValue, forKey: "customURL1_MultiAssistant_v1", defaultURL: self.defaultUrlString1, webView: self.webView1) { self.urlString1 = $0 }
            self.saveSettings(urlString: url2TF.stringValue, forKey: "customURL2_MultiAssistant_v1", defaultURL: self.defaultUrlString2, webView: self.webView2) { self.urlString2 = $0 }
            let autohideEnabled = autohideCB.state == .on; UserDefaults.standard.set(autohideEnabled, forKey: AppDelegate.autohideWindowKey); NSLog("VC: Settings - Autohide window set to: \(autohideEnabled)")

            let selectedSegment = desktopAssignmentControl.selectedSegment
            var newDesktopAssignmentRawValue: UInt; var assignmentDescription: String
            switch selectedSegment {
            case 0: newDesktopAssignmentRawValue = NSWindow.CollectionBehavior.canJoinAllSpaces.rawValue; assignmentDescription = "All Desktops"
            case 1: newDesktopAssignmentRawValue = NSWindow.CollectionBehavior.moveToActiveSpace.rawValue; assignmentDescription = "This Desktop Only"
            default: newDesktopAssignmentRawValue = NSWindow.CollectionBehavior().rawValue; assignmentDescription = "Standard Behavior"
            }
            currentDesktopAssignmentRawValue = newDesktopAssignmentRawValue
            UserDefaults.standard.set(Int(newDesktopAssignmentRawValue), forKey: ViewController.windowDesktopAssignmentKey)
            view.window?.collectionBehavior = NSWindow.CollectionBehavior(rawValue: newDesktopAssignmentRawValue)
            NSLog("VC: Settings - Window desktop assignment set to: \(assignmentDescription) (RawValue: \(newDesktopAssignmentRawValue))")

            let newWindowAlphaValue = clamp(CGFloat(windowAlphaSlider.doubleValue), min: 0.1, max: 1.0)
            currentWindowAlpha = newWindowAlphaValue
            UserDefaults.standard.set(newWindowAlphaValue, forKey: ViewController.windowAlphaKey)
            view.window?.alphaValue = newWindowAlphaValue
            windowAlphaDisplayLabel.stringValue = String(format: "Overall Opacity: %.0f%%", newWindowAlphaValue * 100)
            NSLog("VC: Settings - Window alpha set to: \(newWindowAlphaValue)")

            let newWebViewAlphaValue = clamp(CGFloat(webViewAlphaSlider.doubleValue), min: 0.1, max: 1.0)
            currentWebViewAlpha = newWebViewAlphaValue
            UserDefaults.standard.set(newWebViewAlphaValue, forKey: ViewController.webViewAlphaKey)
            
            let webViews: [WKWebView] = [webView1, webView2]
            for wv in webViews {
                wv.alphaValue = newWebViewAlphaValue
            }

            webViewAlphaDisplayLabel.stringValue = String(format: "Content Opacity: %.0f%%", newWebViewAlphaValue * 100)
            NSLog("VC: Settings - Web View alpha set to: \(newWebViewAlphaValue)")
            
            let newTemperatureValue = temperatureSlider.doubleValue
            currentWebpageTemperature = newTemperatureValue
            UserDefaults.standard.set(newTemperatureValue, forKey: ViewController.webpageTemperatureKey)
            applyTemperatureEffect()
            NSLog("VC: Settings - Webpage temperature set to: \(newTemperatureValue)")
            
            let newBoldFontEnabled = globalBoldFontCB.state == .on
            if newBoldFontEnabled != self.globalBoldFontEnabled {
                self.globalBoldFontEnabled = newBoldFontEnabled
                UserDefaults.standard.set(self.globalBoldFontEnabled, forKey: ViewController.globalBoldFontKey)
                NSLog("VC: Settings - Global Bold Font Style set to: \(self.globalBoldFontEnabled)")
                self.updateGlobalBoldStyleForAllWebViews()
            }


            var newModifiers = NSEvent.ModifierFlags(); if optionCB.state == .on { newModifiers.insert(.option) }; if commandCB.state == .on { newModifiers.insert(.command) }; if shiftCB.state == .on { newModifiers.insert(.shift) }; if controlCB.state == .on { newModifiers.insert(.control) }
            let rawKeyString = keyTF.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); var finalKeyCode: UInt16 = UInt16.max; var finalKeyCharacter: String = ""
            if !rawKeyString.isEmpty {
                finalKeyCharacter = String(rawKeyString.prefix(1)).uppercased()
                switch finalKeyCharacter {
                    case "1": finalKeyCode = UInt16(kVK_ANSI_1); case "2": finalKeyCode = UInt16(kVK_ANSI_2); case "3": finalKeyCode = UInt16(kVK_ANSI_3); case "4": finalKeyCode = UInt16(kVK_ANSI_4); case "5": finalKeyCode = UInt16(kVK_ANSI_5); case "6": finalKeyCode = UInt16(kVK_ANSI_6); case "7": finalKeyCode = UInt16(kVK_ANSI_7); case "8": finalKeyCode = UInt16(kVK_ANSI_8); case "9": finalKeyCode = UInt16(kVK_ANSI_9); case "0": finalKeyCode = UInt16(kVK_ANSI_0)
                    case "Q": finalKeyCode = UInt16(kVK_ANSI_Q); case "W": finalKeyCode = UInt16(kVK_ANSI_W); case "E": finalKeyCode = UInt16(kVK_ANSI_E); case "R": finalKeyCode = UInt16(kVK_ANSI_R); case "T": finalKeyCode = UInt16(kVK_ANSI_T); case "Y": finalKeyCode = UInt16(kVK_ANSI_Y); case "U": finalKeyCode = UInt16(kVK_ANSI_U); case "I": finalKeyCode = UInt16(kVK_ANSI_I); case "O": finalKeyCode = UInt16(kVK_ANSI_O); case "P": finalKeyCode = UInt16(kVK_ANSI_P)
                    case "A": finalKeyCode = UInt16(kVK_ANSI_A); case "S": finalKeyCode = UInt16(kVK_ANSI_S); case "D": finalKeyCode = UInt16(kVK_ANSI_D); case "F": finalKeyCode = UInt16(kVK_ANSI_F); case "G": finalKeyCode = UInt16(kVK_ANSI_G); case "H": finalKeyCode = UInt16(kVK_ANSI_H); case "J": finalKeyCode = UInt16(kVK_ANSI_J); case "K": finalKeyCode = UInt16(kVK_ANSI_K); case "L": finalKeyCode = UInt16(kVK_ANSI_L)
                    case "Z": finalKeyCode = UInt16(kVK_ANSI_Z); case "X": finalKeyCode = UInt16(kVK_ANSI_X); case "C": finalKeyCode = UInt16(kVK_ANSI_C); case "V": finalKeyCode = UInt16(kVK_ANSI_V); case "B": finalKeyCode = UInt16(kVK_ANSI_B); case "N": finalKeyCode = UInt16(kVK_ANSI_N); case "M": finalKeyCode = UInt16(kVK_ANSI_M)
                    case ".": finalKeyCode = UInt16(kVK_ANSI_Period); case ",": finalKeyCode = UInt16(kVK_ANSI_Comma); case ";": finalKeyCode = UInt16(kVK_ANSI_Semicolon); case "'": finalKeyCode = UInt16(kVK_ANSI_Quote); case "/": finalKeyCode = UInt16(kVK_ANSI_Slash); case "\\": finalKeyCode = UInt16(kVK_ANSI_Backslash)
                    case "`": finalKeyCode = UInt16(kVK_ANSI_Grave); case "-": finalKeyCode = UInt16(kVK_ANSI_Minus); case "=": finalKeyCode = UInt16(kVK_ANSI_Equal); case "[": finalKeyCode = UInt16(kVK_ANSI_LeftBracket); case "]": finalKeyCode = UInt16(kVK_ANSI_RightBracket)
                    default: NSLog("VC: Warning - Key character '\(finalKeyCharacter)' not in simple map."); if newModifiers.isEmpty { finalKeyCode = UInt16.max; finalKeyCharacter = "" } else { finalKeyCode = UInt16.max; finalKeyCharacter = ""; NSLog("VC: Unknown key character '\(finalKeyCharacter)' with modifiers. Clearing key.") }
                }
            } else {
                finalKeyCode = UInt16.max
                finalKeyCharacter = ""
                newModifiers = []
            }
            let defaults = UserDefaults.standard; defaults.set(NSNumber(value: finalKeyCode), forKey: AppDelegate.shortcutKeyCodeKey); defaults.set(newModifiers.rawValue, forKey: AppDelegate.shortcutModifierFlagsKey); defaults.set(finalKeyCharacter, forKey: AppDelegate.shortcutKeyCharacterKey); NSLog("VC: Saved shortcut - KeyCode: \(finalKeyCode), Modifiers: \(newModifiers.rawValue), Char: '\(finalKeyCharacter)'")
            if let appDelegate = NSApp.delegate as? AppDelegate { appDelegate.currentShortcutKeyCode = finalKeyCode; appDelegate.currentShortcutModifierFlags = newModifiers; appDelegate.currentShortcutKeyCharacter = finalKeyCharacter; currentShortcutDisplayLabel.stringValue = "Current: \(appDelegate.formattedShortcutString())" }
            NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
        } else { NSLog("VC: Settings Cancel button clicked or sheet dismissed.") }
    }

    private func saveSettings(urlString: String, forKey key: String, defaultURL: String, webView: WKWebView, assignToInstanceVar: @escaping (String) -> Void) {
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUrl.isEmpty { UserDefaults.standard.set(defaultURL, forKey: key); assignToInstanceVar(defaultURL); if let url = URL(string: defaultURL) { webView.load(URLRequest(url: url)) }; NSLog("VC: Settings - \(key) reset to default: \(defaultURL)")
        } else if let url = URL(string: trimmedUrl), (url.scheme == "http" || url.scheme == "https") { UserDefaults.standard.set(trimmedUrl, forKey: key); assignToInstanceVar(trimmedUrl); if webView.url?.absoluteString != trimmedUrl { webView.load(URLRequest(url: url)) }; NSLog("VC: Settings - \(key) updated to: \(trimmedUrl)")
        } else { NSLog("VC: Settings - Invalid URL for \(key): '\(trimmedUrl)'. Not saved. Previous URL remains.") }
    }
}

