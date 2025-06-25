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
    private var webViews: [WKWebView?] = [] // MODIFIED: Array is now optional to allow deallocation
    private var visualEffectView: NSVisualEffectView!
    private var temperatureOverlayView: ClickThroughNSView!
    private var brightnessOverlayView: ClickThroughNSView!

    // Configuration constants
    private let webViewCount = 10
    private let defaultUrlStrings = Array(repeating: "", count: 10)
    private let cornerRadiusValue: CGFloat = 25.0
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
    static let webpageBrightnessKey = "webpageBrightnessKey_v1"
    static let webTabEnabledKey = "webTabEnabledKey_v1"
    static let webTabLabelsKey = "webTabLabelsKey_v1"
    static let webTabPersistKey = "webTabPersistKey_v1"
    static let unloadTimerDurationKey = "unloadTimerDurationKey_v1" // NEW: Key for timer duration
    static let cycleWithPersistOnlyKey = "cycleWithPersistOnlyKey_v1" // NEW: Key for cycle behavior

    // Runtime state
    private var webViewZoomScales: [CGFloat] = []
    private var urlStrings: [String] = []
    private var webTabEnabledStates: [Bool] = []
    private var webTabLabels: [String] = []
    private var webTabPersistStates: [Bool] = []
    private var unloadTimers: [Int: DispatchWorkItem] = [:]
    private var activeWebViewIndex: Int = 0
    private var currentWindowAlpha: CGFloat = 1.0
    private var currentWebViewAlpha: CGFloat = 0.8
    private var currentDesktopAssignmentRawValue: UInt = NSWindow.CollectionBehavior.canJoinAllSpaces.rawValue
    private var globalBoldFontEnabled: Bool = false
    private var currentWebpageTemperature: Double = 50.0
    private var currentWebpageBrightness: Double = 50.0
    private var currentUnloadDelay: TimeInterval = 300.0 // NEW: User-configurable unload delay
    private var cycleWithPersistOnly: Bool = false // NEW: State for cycle behavior

    private var webViewsReloadingAfterTermination: Set<WKWebView> = []
    // MODIFIED: This now force-unwraps, relying on logic to ensure the active view is never nil
    private var activeWebView: WKWebView { webViews[activeWebViewIndex]! }
    private var windowChromeConfigured = false
    private var hudWorkItem: DispatchWorkItem?

    // MARK: - View / Window Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("VC: viewDidLoad")
        loadSettings()
        configureContainerLayer()
        setupVisualEffectView()
        setupWebViews()
        setupTemperatureOverlay()
        setupBrightnessOverlay()
        loadInitialContent()
        setupKeyboardShortcuts()
        
        if !webTabEnabledStates[activeWebViewIndex] {
            activeWebViewIndex = webTabEnabledStates.firstIndex(of: true) ?? 0
            switchToPage(index: activeWebViewIndex, showHUD: false) // Don't show HUD on initial load
        }
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
        view.layer?.borderWidth = 0.7
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
    
    private func setupBrightnessOverlay() {
        brightnessOverlayView = ClickThroughNSView()
        brightnessOverlayView.translatesAutoresizingMaskIntoConstraints = false
        brightnessOverlayView.wantsLayer = true
        brightnessOverlayView.layer?.backgroundColor = NSColor.clear.cgColor

        view.addSubview(brightnessOverlayView)
        NSLayoutConstraint.activate([
            brightnessOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            brightnessOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            brightnessOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            brightnessOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        NSLog("VC: Brightness overlay view setup.")
        applyBrightnessEffect()
    }

    // NEW: Helper to create a configured webview instance
    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let cssString = "html, body { background-color: transparent !important; }"
        let userScript = WKUserScript(source: cssString, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = currentWebViewAlpha
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }

    private func setupWebViews() {
        // Initialize the array with nil placeholders
        webViews = Array(repeating: nil, count: webViewCount)
        // Create webviews only for enabled tabs initially
        for i in 0..<webViewCount {
            if webTabEnabledStates[i] {
                let newWebView = createWebView()
                webViews[i] = newWebView
                view.addSubview(newWebView)
                NSLayoutConstraint.activate([
                    newWebView.topAnchor.constraint(equalTo: view.topAnchor),
                    newWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    newWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    newWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
                ])
                newWebView.isHidden = (i != activeWebViewIndex)
            }
        }
        NSLog("VC: WebViews setup complete. Initialized \(webTabEnabledStates.filter { $0 }.count) views.")
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
            guard let self = self, event.modifierFlags.contains(.command) else { return event }
            if self.view.window?.attachedSheet != nil { return event }

            switch Int(event.keyCode) {
            case kVK_ANSI_Grave:
                self.cycleToNextPage()
                return nil
            case kVK_Delete:
                self.actualSizePage()
                return nil
            default:
                break
            }
            
            guard let key = event.charactersIgnoringModifiers else { return event }

            if let keyInt = Int(key) {
                let pageIndex = (keyInt == 0) ? 9 : keyInt - 1
                if pageIndex >= 0 && pageIndex < self.webViewCount {
                    if self.webTabEnabledStates[pageIndex] {
                        self.switchToPage(index: pageIndex)
                    }
                    return nil
                }
            }

            switch key.lowercased() {
            case "r": self.refreshCurrentPage(); return nil
            case "=","+", "§": self.zoomInPage(); return nil
            case "-": self.zoomOutPage(); return nil
            case ",": self.openSettings(); return nil
            default: return event
            }
        }
        NSLog("VC: Keyboard shortcuts setup.")
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        
        urlStrings.removeAll()
        webViewZoomScales.removeAll()
        webTabEnabledStates.removeAll()
        webTabLabels.removeAll()
        webTabPersistStates.removeAll()
        
        for i in 0..<webViewCount {
            let urlKey = "customURL\(i+1)_MultiAssistant_v2"
            let zoomKey = "webView\(i+1)ZoomScale_MultiAssistant_v2"
            
            let url = d.string(forKey: urlKey) ?? defaultUrlStrings[i]
            urlStrings.append(url)
            
            let savedZoom = d.float(forKey: zoomKey)
            let zoom = (savedZoom > 0.01) ? CGFloat(savedZoom) : 1.0
            webViewZoomScales.append(zoom)
        }
        
        if let savedEnabledStates = d.array(forKey: ViewController.webTabEnabledKey) as? [Bool], savedEnabledStates.count == webViewCount {
            webTabEnabledStates = savedEnabledStates
        } else {
            webTabEnabledStates = [true, true] + Array(repeating: false, count: webViewCount - 2)
        }
        
        if let savedLabels = d.stringArray(forKey: ViewController.webTabLabelsKey), savedLabels.count == webViewCount {
            webTabLabels = savedLabels
        } else {
            webTabLabels = Array(repeating: "", count: webViewCount)
        }
        
        if let savedPersistStates = d.array(forKey: ViewController.webTabPersistKey) as? [Bool], savedPersistStates.count == webViewCount {
            webTabPersistStates = savedPersistStates
        } else {
            webTabPersistStates = Array(repeating: false, count: webViewCount)
        }

        // NEW: Load unload delay setting
        if d.object(forKey: ViewController.unloadTimerDurationKey) != nil {
            currentUnloadDelay = d.double(forKey: ViewController.unloadTimerDurationKey)
        } else {
            currentUnloadDelay = 300.0 // Default to 5 minutes
        }

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
        
        if d.object(forKey: ViewController.webpageBrightnessKey) != nil {
            currentWebpageBrightness = d.double(forKey: ViewController.webpageBrightnessKey)
        } else {
            currentWebpageBrightness = 50.0
            d.set(currentWebpageBrightness, forKey: ViewController.webpageBrightnessKey)
        }
        
        // NEW: Load cycle behavior setting
        if d.object(forKey: ViewController.cycleWithPersistOnlyKey) != nil {
            cycleWithPersistOnly = d.bool(forKey: ViewController.cycleWithPersistOnlyKey)
        } else {
            cycleWithPersistOnly = false // Default to cycling through all enabled tabs
            d.set(cycleWithPersistOnly, forKey: ViewController.cycleWithPersistOnlyKey)
        }

        NSLog("VC: Settings loaded for \(webViewCount) pages.")
    }

    private func loadInitialContent() {
        for (index, _) in urlStrings.enumerated() {
            if webTabEnabledStates[index] {
                loadPage(at: index)
            }
        }
    }
    
    // MARK: - Page Loading/Unloading
    
    private func loadPage(at index: Int) {
        guard index >= 0, index < webViewCount, webTabEnabledStates[index] else { return }
        
        // If the webview for this index doesn't exist, create it.
        if webViews[index] == nil {
            let newWebView = createWebView()
            webViews[index] = newWebView
            view.addSubview(newWebView, positioned: .below, relativeTo: temperatureOverlayView)
            NSLayoutConstraint.activate([
                newWebView.topAnchor.constraint(equalTo: view.topAnchor),
                newWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                newWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                newWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            newWebView.isHidden = (index != activeWebViewIndex)
            NSLog("VC: Re-created webview for index \(index).")
        }

        guard let webView = webViews[index] else { return }
        let urlString = urlStrings[index]

        // Only load if it's currently blank and has a valid URL
        if webView.url == nil || webView.url?.absoluteString == "about:blank" {
             if let url = URL(string: urlString) {
                NSLog("VC: Loading page at index \(index). URL: \(url.absoluteString)")
                webView.load(URLRequest(url: url))
             } else if !urlString.isEmpty {
                 NSLog("VC: Cannot load page at index \(index), invalid URL: \(urlString)")
                 webView.loadHTMLString("<html><body>Invalid URL</body></html>", baseURL: nil)
             } else {
                 webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
             }
        } else {
             NSLog("VC: Page at index \(index) is already loaded. Skipping reload.")
        }
    }
    
    // MODIFIED: This now deallocates the webview entirely
    private func unloadPage(at index: Int) {
        guard index >= 0, index < webViewCount, webViews[index] != nil else { return }
        
        if index == activeWebViewIndex || webTabPersistStates[index] {
            NSLog("VC: Unload for page \(index) aborted (is active or persisted).")
            unloadTimers.removeValue(forKey: index)
            return
        }
        
        NSLog("VC: Deallocating webview and process for index \(index).")
        let webViewToUnload = webViews[index]
        webViewToUnload?.removeFromSuperview()
        webViews[index] = nil // This deinitializes the WKWebView and its process
        
        unloadTimers.removeValue(forKey: index)
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
        // Use compactMap to safely unwrap optionals
        webViews.compactMap { $0 }.forEach { applyGlobalBoldStyle(to: $0) }
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
    
    private func applyBrightnessEffect() {
        guard brightnessOverlayView != nil else { return }

        let value = currentWebpageBrightness
        let maxAlpha: CGFloat = 0.4 // Max darkness/brightness effect

        if value < 49.0 {
            // Darken
            let alpha = (50.0 - value) / 50.0 * maxAlpha
            brightnessOverlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(alpha).cgColor
        } else if value > 51.0 {
            // Brighten
            let alpha = (value - 50.0) / 50.0 * maxAlpha
            brightnessOverlayView.layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
        } else {
            // Neutral
            brightnessOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        NSLog("VC: Applied brightness effect. Value: \(value)")
    }


    // MARK: - Focus Handling
    @objc func attemptWebViewFocus() {
        guard webTabEnabledStates.contains(true) else {
            NSLog("VC: attemptWebViewFocus - Aborted, no tabs enabled.")
            return
        }
        
        // Ensure the active webview exists before trying to focus it
        guard let _ = webViews[activeWebViewIndex] else {
            NSLog("VC: attemptWebViewFocus - Aborted, active webview at index \(activeWebViewIndex) is nil.")
            return
        }
        
        NSLog("VC: attemptWebViewFocus called.")
        guard let window = self.view.window else { NSLog("VC: attemptWebViewFocus - No window."); return }
        let webViewToFocus = self.activeWebView
        NSLog("VC: attemptWebViewFocus for WebView at index \(activeWebViewIndex). AppIsActive: \(NSApp.isActive), WindowIsKey: \(window.isKeyWindow), WindowIsVisible: \(window.isVisible)")
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
        NSLog("VC: proceedWithFirstResponder for WebView at index \(activeWebViewIndex). Current FR before: \(String(describing: window.firstResponder))")
        if window.makeFirstResponder(webViewToFocus) {
            NSLog("VC: proceedWithFirstResponder - SUCCESS: Made WebView at index \(activeWebViewIndex) first responder.")
            executeJavaScriptFocus(reason: "proceedWithFirstResponder_success")
        } else {
            NSLog("VC: proceedWithFirstResponder - FAILED: Could not make WebView at index \(activeWebViewIndex) first responder.")
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
    @objc func cycleToNextPage() {
        // NEW: Create a filtered list of tab indices to cycle through based on the setting
        let tabsToCycle = webTabEnabledStates.indices.filter {
            webTabEnabledStates[$0] && (!cycleWithPersistOnly || webTabPersistStates[$0])
        }

        // Must have at least two tabs in the filtered list to be able to cycle
        guard tabsToCycle.count > 1 else {
            NSLog("VC: Cycle Page - Not enough tabs (\(tabsToCycle.count)) to cycle through with current filter (Persist Only: \(cycleWithPersistOnly)).")
            return
        }

        // Find the position of the currently active tab within our filtered list
        guard let currentIndexInCycle = tabsToCycle.firstIndex(of: activeWebViewIndex) else {
            // This can happen if the active tab is not in the cycle list (e.g., it's not persisted when the setting requires it).
            // In this case, just switch to the very first available tab in the filtered list.
            if let firstValidTab = tabsToCycle.first {
                switchToPage(index: firstValidTab)
            }
            return
        }

        // Get the next index in the filtered list, wrapping around if necessary
        let nextIndexInCycle = (currentIndexInCycle + 1) % tabsToCycle.count
        let nextWebViewIndex = tabsToCycle[nextIndexInCycle]

        switchToPage(index: nextWebViewIndex)
    }
    
    @objc func switchToPage(index: Int, showHUD: Bool = true) {
        guard webTabEnabledStates[index], index != activeWebViewIndex else { return }
        NSLog("VC: Switching page from index \(activeWebViewIndex) to \(index).")
        
        let oldIndex = activeWebViewIndex
        
        // --- Logic for the page we are LEAVING ---
        // Schedule unload only if the feature is not disabled ("Never" option)
        if currentUnloadDelay > 0 && oldIndex >= 0 && oldIndex < webViewCount && !webTabPersistStates[oldIndex] {
            unloadTimers[oldIndex]?.cancel()
            NSLog("VC: Scheduling unload for non-persisted page \(oldIndex) in \(currentUnloadDelay) seconds.")
            let workItem = DispatchWorkItem { [weak self] in
                self?.unloadPage(at: oldIndex)
            }
            unloadTimers[oldIndex] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + currentUnloadDelay, execute: workItem)
        }
        
        // --- Logic for the page we are SWITCHING TO ---
        if let timer = unloadTimers[index] {
            timer.cancel()
            unloadTimers.removeValue(forKey: index)
            NSLog("VC: Cancelled pending unload for page \(index) as it is now active.")
        }
        
        // This will create and/or load the page if needed
        loadPage(at: index)

        // --- Original logic to update UI ---
        activeWebViewIndex = index
        
        for (i, webView) in webViews.enumerated() {
            webView?.isHidden = (i != activeWebViewIndex)
        }
        
        // This relies on `loadPage` having already created the webview if it was nil
        let currentActiveWebView = activeWebView
        view.addSubview(currentActiveWebView, positioned: .below, relativeTo: temperatureOverlayView)
        if let brightnessView = brightnessOverlayView {
            view.addSubview(brightnessView, positioned: .above, relativeTo: temperatureOverlayView)
        }
        
        if showHUD {
            showTabSwitchHUD(for: index)
        }
        
        applyZoom(to: currentActiveWebView, scale: currentZoom())
        NSLog("VC: Calling attemptWebViewFocus after page switch.")
        attemptWebViewFocus()
        NSLog("VC: Active webview is now at index: \(activeWebViewIndex)")
    }

    @objc func refreshCurrentPage() {
        NSLog("VC: Refreshing current page at index: \(activeWebViewIndex)")
        guard let webView = webViews[activeWebViewIndex] else {
            NSLog("VC: Cannot refresh, webview at index \(activeWebViewIndex) is nil.")
            return
        }
        webViewsReloadingAfterTermination.insert(webView)
        webView.reload()
    }

    @objc func zoomInPage()  { changeZoom(by: +zoomStep) }
    @objc func zoomOutPage() { changeZoom(by: -zoomStep) }
    @objc func actualSizePage() { setZoom(1.0) }

    private func changeZoom(by delta: CGFloat) {
        let oldScale = currentZoom()
        let newScale = clamp(oldScale + delta, min: minZoom, max: maxZoom)
        setZoom(newScale)
    }

    private func currentZoom() -> CGFloat { webViewZoomScales[activeWebViewIndex] }
    
    private func zoomScale(for wv: WKWebView) -> CGFloat {
        if let index = webViews.firstIndex(of: wv) {
            return webViewZoomScales[index]
        }
        return 1.0
    }

    private func setZoom(_ scale: CGFloat) {
        guard webViews[activeWebViewIndex] != nil else { return }
        webViewZoomScales[activeWebViewIndex] = scale
        let targetScaleKey = "webView\(activeWebViewIndex + 1)ZoomScale_MultiAssistant_v2"
        UserDefaults.standard.set(Float(scale), forKey: targetScaleKey)
        applyZoom(to: activeWebView, scale: scale)
        NSLog("VC: Zoom set to \(scale) for WebView at index \(activeWebViewIndex)")
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat { Swift.max(min, Swift.min(max, value)) }

    private func applyZoom(to wv: WKWebView, scale: CGFloat) {
        let js = "document.documentElement.style.zoom = '\(scale * 100)%';"
        wv.evaluateJavaScript(js) { _, err in if let err = err { NSLog("VC: Zoom JS error: %@", err.localizedDescription) } }
    }

    // MARK: - WKNavigationDelegate
    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
        guard let index = webViews.firstIndex(of: wv) else { return }
        NSLog("VC: WebView at index \(index) didFinish navigation. URL: \(wv.url?.absoluteString ?? "N/A").")
        applyZoom(to: wv, scale: zoomScale(for: wv))
        applyGlobalBoldStyle(to: wv)
        
        if view.window?.isKeyWindow == true || webViewsReloadingAfterTermination.contains(wv) {
            NSLog("VC: WebView \(index) finished, attempting focus (window is key or was reloading).")
            if index == activeWebViewIndex {
                 attemptWebViewFocus()
            }
        } else { NSLog("VC: WebView \(index) finished, but window not key and not specifically reloading. Focus not attempted automatically.") }
        webViewsReloadingAfterTermination.remove(wv)
    }

    func webViewWebContentProcessDidTerminate(_ wv: WKWebView) {
        guard let index = webViews.firstIndex(of: wv) else { return }
        NSLog("VC: CRITICAL - WebView at index \(index) content process did terminate. Reloading.")
        
        // Since the process is gone, we must fully recreate the webview
        unloadPage(at: index) // This will set webViews[index] to nil
        // If the terminated page was the active one, reload it immediately.
        if index == activeWebViewIndex {
            loadPage(at: index)
        }
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
        let webViewName = (webViews.firstIndex(of: webView).map { "Page \($0 + 1)" }) ?? "Unknown Page"
        NSLog("VC: \(webViewName) failed provisional navigation: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let webViewName = (webViews.firstIndex(of: webView).map { "Page \($0 + 1)" }) ?? "Unknown Page"
        NSLog("VC: \(webViewName) failed navigation: \(error.localizedDescription)")
    }
    
    // MARK: - WKUIDelegate & Download Handling
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSLog("VC: Intercepted request to create a new web view for URL: \(url.absoluteString). Opening in default browser.")
            NSWorkspace.shared.open(url)
        }
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
        
        // MODIFIED: Increased width for better layout
        let desiredAccessoryViewWidth: CGFloat = 800; let labelColumnWidth: CGFloat = 180; let hStackSpacing: CGFloat = 12; let vStackRowSpacing: CGFloat = 10; let sectionHeaderSpacing: CGFloat = 8; let sectionBottomSpacing: CGFloat = 24; let outerPadding: CGFloat = 25

        func createSettingRow(labelString: String, control: NSView) -> NSStackView {
            let label = NSTextField(labelWithString: labelString); label.alignment = .right; label.translatesAutoresizingMaskIntoConstraints = false; label.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true
            control.translatesAutoresizingMaskIntoConstraints = false
            let hStack = NSStackView(views: [label, control]); hStack.orientation = .horizontal; hStack.spacing = hStackSpacing; hStack.alignment = .firstBaseline
            return hStack
        }
        
        let mainVerticalStackView = NSStackView(); mainVerticalStackView.orientation = .vertical; mainVerticalStackView.spacing = vStackRowSpacing; mainVerticalStackView.alignment = .leading; mainVerticalStackView.edgeInsets = NSEdgeInsets(top: outerPadding, left: outerPadding, bottom: outerPadding, right: outerPadding)

        // --- URL Section ---
        let urlSectionHeader = createSectionHeader(title: "Web Page URLs")
        mainVerticalStackView.addArrangedSubview(urlSectionHeader)
        mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: urlSectionHeader)
        
        let urlNoteLabel = NSTextField(labelWithString: "Please enter full URLs (e.g., https://...)")
        urlNoteLabel.textColor = .secondaryLabelColor
        urlNoteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let noteIndentView = NSView(); noteIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true
        let noteRow = NSStackView(views: [noteIndentView, urlNoteLabel]); noteRow.orientation = .horizontal; noteRow.spacing = 0
        mainVerticalStackView.addArrangedSubview(noteRow)
        
        var urlTextFields: [NSTextField] = []
        var labelTextFields: [NSTextField] = []
        var enabledCheckboxes: [NSButton] = []
        var persistCheckboxes: [NSButton] = []
        
        for i in 0..<webViewCount {
            let urlTextField = NSTextField(string: urlStrings[i])
            urlTextField.placeholderString = "e.g., https://openai.com"
            urlTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            
            let labelTextField = NSTextField(string: webTabLabels[i])
            labelTextField.placeholderString = "Label"
            labelTextField.widthAnchor.constraint(equalToConstant: 120).isActive = true
            
            let enabledCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
            enabledCheckbox.state = webTabEnabledStates[i] ? .on : .off
            
            let persistCheckbox = NSButton(checkboxWithTitle: "Persist", target: nil, action: nil)
            persistCheckbox.state = webTabPersistStates[i] ? .on : .off
            
            let controlStack = NSStackView(views: [urlTextField, labelTextField, enabledCheckbox, persistCheckbox])
            controlStack.orientation = .horizontal
            controlStack.spacing = hStackSpacing
            
            let urlRow = createSettingRow(labelString: "Page \(i+1):", control: controlStack)
            urlTextFields.append(urlTextField)
            labelTextFields.append(labelTextField)
            enabledCheckboxes.append(enabledCheckbox)
            persistCheckboxes.append(persistCheckbox)
            mainVerticalStackView.addArrangedSubview(urlRow)
        }
        
        if let lastUrlRow = mainVerticalStackView.arrangedSubviews.last {
            mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: lastUrlRow)
        }
        
        mainVerticalStackView.addArrangedSubview(createSeparatorBox())
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)

        // --- Behavior Section ---
        let behaviorSectionHeader = createSectionHeader(title: "Window Behavior")
        mainVerticalStackView.addArrangedSubview(behaviorSectionHeader)
        mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: behaviorSectionHeader)

        // NEW: Unload Timer Duration Setting
        let unloadPopup = NSPopUpButton(frame: .zero)
        unloadPopup.addItems(withTitles: ["1 Minute", "5 Minutes", "15 Minutes", "30 Minutes", "Never"])
        unloadPopup.item(withTitle: "1 Minute")?.representedObject = 60.0
        unloadPopup.item(withTitle: "5 Minutes")?.representedObject = 300.0
        unloadPopup.item(withTitle: "15 Minutes")?.representedObject = 900.0
        unloadPopup.item(withTitle: "30 Minutes")?.representedObject = 1800.0
        unloadPopup.item(withTitle: "Never")?.representedObject = -1.0
        
        if let selectedItem = unloadPopup.itemArray.first(where: { ($0.representedObject as? Double) == currentUnloadDelay }) {
            unloadPopup.select(selectedItem)
        } else {
            unloadPopup.selectItem(withTitle: "5 Minutes")
        }
        let unloadRow = createSettingRow(labelString: "Unload Inactive Tabs After:", control: unloadPopup); unloadRow.alignment = .centerY
        mainVerticalStackView.addArrangedSubview(unloadRow)
        
        // NEW: Cycle Behavior Setting
        let cycleBehaviorControl = NSSegmentedControl(labels: ["All Enabled Tabs", "Persisted Tabs Only"], trackingMode: .selectOne, target: nil, action: nil)
        cycleBehaviorControl.segmentStyle = .texturedRounded
        cycleBehaviorControl.selectedSegment = cycleWithPersistOnly ? 1 : 0
        let cycleBehaviorRow = createSettingRow(labelString: "Cycle (⌘+`) Through:", control: cycleBehaviorControl)
        cycleBehaviorRow.alignment = .centerY
        mainVerticalStackView.addArrangedSubview(cycleBehaviorRow)

        let autohideCheckbox = NSButton(checkboxWithTitle: "Auto-hide window when application is inactive", target: nil, action: nil); autohideCheckbox.state = UserDefaults.standard.bool(forKey: AppDelegate.autohideWindowKey) ? .on : .off; autohideCheckbox.translatesAutoresizingMaskIntoConstraints = false
        let autohideIndentView = NSView(); autohideIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true; let autohideControlRow = NSStackView(views: [autohideIndentView, autohideCheckbox]); autohideControlRow.orientation = .horizontal; autohideControlRow.spacing = 0; autohideControlRow.alignment = .firstBaseline
        mainVerticalStackView.addArrangedSubview(autohideControlRow)
        
        let desktopAssignmentControl = NSSegmentedControl(labels: ["All Desktops", "This Desktop", "Standard"], trackingMode: .selectOne, target: nil, action: nil)
        desktopAssignmentControl.segmentStyle = .texturedRounded
        if currentDesktopAssignmentRawValue == NSWindow.CollectionBehavior.canJoinAllSpaces.rawValue { desktopAssignmentControl.selectedSegment = 0
        } else if currentDesktopAssignmentRawValue == NSWindow.CollectionBehavior.moveToActiveSpace.rawValue { desktopAssignmentControl.selectedSegment = 1
        } else { desktopAssignmentControl.selectedSegment = 2 }
        let desktopAssignmentRow = createSettingRow(labelString: "Assign Window To:", control: desktopAssignmentControl); desktopAssignmentRow.alignment = .centerY
        mainVerticalStackView.addArrangedSubview(desktopAssignmentRow)
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: desktopAssignmentRow)
        mainVerticalStackView.addArrangedSubview(createSeparatorBox())
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)

        // --- Appearance Section ---
        let appearanceSectionHeader = createSectionHeader(title: "Window Appearance & Content")
        mainVerticalStackView.addArrangedSubview(appearanceSectionHeader)
        mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: appearanceSectionHeader)
        let windowAlphaSlider = NSSlider(value: Double(currentWindowAlpha), minValue: 0.1, maxValue: 1.0, target: nil, action: nil); windowAlphaSlider.allowsTickMarkValuesOnly = false; windowAlphaSlider.numberOfTickMarks = 10; windowAlphaSlider.translatesAutoresizingMaskIntoConstraints = false
        let currentWindowAlphaDisplayLabel = NSTextField(labelWithString: String(format: "Overall Opacity: %.0f%%", currentWindowAlpha * 100)); currentWindowAlphaDisplayLabel.isEditable = false; currentWindowAlphaDisplayLabel.isSelectable = false; currentWindowAlphaDisplayLabel.translatesAutoresizingMaskIntoConstraints = false; currentWindowAlphaDisplayLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let windowAlphaSliderAndDisplay = NSStackView(views: [windowAlphaSlider, currentWindowAlphaDisplayLabel]); windowAlphaSliderAndDisplay.orientation = .horizontal; windowAlphaSliderAndDisplay.spacing = hStackSpacing; windowAlphaSliderAndDisplay.alignment = .centerY
        let windowAlphaRow = createSettingRow(labelString: "Window Transparency:", control: windowAlphaSliderAndDisplay); windowAlphaRow.alignment = .centerY
        mainVerticalStackView.addArrangedSubview(windowAlphaRow)

        let webViewAlphaSlider = NSSlider(value: Double(currentWebViewAlpha), minValue: 0.1, maxValue: 1.0, target: nil, action: nil); webViewAlphaSlider.allowsTickMarkValuesOnly = false; webViewAlphaSlider.numberOfTickMarks = 10; webViewAlphaSlider.translatesAutoresizingMaskIntoConstraints = false
        let currentWebViewAlphaDisplayLabel = NSTextField(labelWithString: String(format: "Content Opacity: %.0f%%", currentWebViewAlpha * 100)); currentWebViewAlphaDisplayLabel.isEditable = false; currentWebViewAlphaDisplayLabel.isSelectable = false; currentWebViewAlphaDisplayLabel.translatesAutoresizingMaskIntoConstraints = false; currentWebViewAlphaDisplayLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let webViewAlphaSliderAndDisplay = NSStackView(views: [webViewAlphaSlider, currentWebViewAlphaDisplayLabel]); webViewAlphaSliderAndDisplay.orientation = .horizontal; webViewAlphaSliderAndDisplay.spacing = hStackSpacing; webViewAlphaSliderAndDisplay.alignment = .centerY
        let webViewAlphaRow = createSettingRow(labelString: "Web Page Opacity:", control: webViewAlphaSliderAndDisplay); webViewAlphaRow.alignment = .centerY
        mainVerticalStackView.addArrangedSubview(webViewAlphaRow)
        
        let temperatureSlider = NSSlider(value: currentWebpageTemperature, minValue: 0, maxValue: 100, target: nil, action: nil)
        temperatureSlider.allowsTickMarkValuesOnly = false; temperatureSlider.numberOfTickMarks = 11; temperatureSlider.translatesAutoresizingMaskIntoConstraints = false
        let temperatureDisplayLabel = NSTextField(labelWithString: "Cold / Warm"); temperatureDisplayLabel.isEditable = false; temperatureDisplayLabel.isSelectable = false; temperatureDisplayLabel.translatesAutoresizingMaskIntoConstraints = false; temperatureDisplayLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let temperatureSliderAndDisplay = NSStackView(views: [temperatureSlider, temperatureDisplayLabel]); temperatureSliderAndDisplay.orientation = .horizontal; temperatureSliderAndDisplay.spacing = hStackSpacing; temperatureSliderAndDisplay.alignment = .centerY
        let temperatureRow = createSettingRow(labelString: "Page Color Tone:", control: temperatureSliderAndDisplay); temperatureRow.alignment = .centerY
        mainVerticalStackView.addArrangedSubview(temperatureRow)

        let brightnessSlider = NSSlider(value: currentWebpageBrightness, minValue: 0, maxValue: 100, target: nil, action: nil)
        brightnessSlider.allowsTickMarkValuesOnly = false; brightnessSlider.numberOfTickMarks = 11; brightnessSlider.translatesAutoresizingMaskIntoConstraints = false
        let brightnessDisplayLabel = NSTextField(labelWithString: "Darker / Brighter"); brightnessDisplayLabel.isEditable = false; brightnessDisplayLabel.isSelectable = false; brightnessDisplayLabel.translatesAutoresizingMaskIntoConstraints = false; brightnessDisplayLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let brightnessSliderAndDisplay = NSStackView(views: [brightnessSlider, brightnessDisplayLabel]); brightnessSliderAndDisplay.orientation = .horizontal; brightnessSliderAndDisplay.spacing = hStackSpacing; brightnessSliderAndDisplay.alignment = .centerY
        let brightnessRow = createSettingRow(labelString: "Page Brightness:", control: brightnessSliderAndDisplay); brightnessRow.alignment = .centerY
        mainVerticalStackView.addArrangedSubview(brightnessRow)

        let globalBoldFontCheckbox = NSButton(checkboxWithTitle: "Force Bold Font Style on Web Pages", target: nil, action: nil)
        globalBoldFontCheckbox.state = globalBoldFontEnabled ? .on : .off
        globalBoldFontCheckbox.translatesAutoresizingMaskIntoConstraints = false
        let boldFontIndentView = NSView(); boldFontIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true
        let boldFontRow = NSStackView(views: [boldFontIndentView, globalBoldFontCheckbox])
        boldFontRow.orientation = .horizontal; boldFontRow.spacing = 0; boldFontRow.alignment = .firstBaseline
        mainVerticalStackView.addArrangedSubview(boldFontRow)
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: boldFontRow); mainVerticalStackView.addArrangedSubview(createSeparatorBox()); mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)

        // --- Global Shortcut Section ---
        let globalShortcutSectionHeader = createSectionHeader(title: "Global Toggle Shortcut (Show/Hide Window)")
        mainVerticalStackView.addArrangedSubview(globalShortcutSectionHeader)
        mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: globalShortcutSectionHeader)
        let currentShortcutDisplayLabel = NSTextField(labelWithString: "Current: \( (NSApp.delegate as? AppDelegate)?.formattedShortcutString() ?? "Not Set" )"); currentShortcutDisplayLabel.isEditable = false; currentShortcutDisplayLabel.isSelectable = false
        let currentShortcutIndentView = NSView(); currentShortcutIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true; let currentShortcutRow = NSStackView(views: [currentShortcutIndentView, currentShortcutDisplayLabel]); currentShortcutRow.orientation = .horizontal; currentShortcutRow.alignment = .firstBaseline
        mainVerticalStackView.addArrangedSubview(currentShortcutRow)
        let keyTextField = NSTextField(string: (NSApp.delegate as? AppDelegate)?.currentShortcutKeyCharacter ?? ""); keyTextField.placeholderString = "e.g., . or A"; keyTextField.widthAnchor.constraint(equalToConstant: 70).isActive = true; let keyRow = createSettingRow(labelString: "Key:", control: keyTextField)
        mainVerticalStackView.addArrangedSubview(keyRow)
        let optionCheckbox = NSButton(checkboxWithTitle: "Option (⌥)", target: nil, action: nil); let commandCheckbox = NSButton(checkboxWithTitle: "Command (⌘)", target: nil, action: nil); let shiftCheckbox = NSButton(checkboxWithTitle: "Shift (⇧)", target: nil, action: nil); let controlCheckbox = NSButton(checkboxWithTitle: "Control (⌃)", target: nil, action: nil)
        if let appDelegate = NSApp.delegate as? AppDelegate { optionCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.option) ? .on : .off; commandCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.command) ? .on : .off; shiftCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.shift) ? .on : .off; controlCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.control) ? .on : .off }
        let modifiersCheckboxHStack = NSStackView(views: [optionCheckbox, commandCheckbox, shiftCheckbox, controlCheckbox]); modifiersCheckboxHStack.orientation = .horizontal; modifiersCheckboxHStack.spacing = hStackSpacing * 1.2; modifiersCheckboxHStack.alignment = .centerY; let modifiersRow = createSettingRow(labelString: "Modifiers:", control: modifiersCheckboxHStack); modifiersRow.alignment = .centerY
        mainVerticalStackView.addArrangedSubview(modifiersRow)
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: modifiersRow); mainVerticalStackView.addArrangedSubview(createSeparatorBox()); mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)

        // --- In-App Shortcut Section ---
        let otherShortcutsSectionHeader = createSectionHeader(title: "In-App Shortcuts")
        mainVerticalStackView.addArrangedSubview(otherShortcutsSectionHeader)
        mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: otherShortcutsSectionHeader)
        
        let cycleLabel = NSTextField(labelWithString: "Cycle Pages:  Command (⌘) + `"); cycleLabel.isEditable = false; cycleLabel.isSelectable = false
        let cycleIndentView = NSView(); cycleIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true; let cycleRow = NSStackView(views: [cycleIndentView, cycleLabel]); cycleRow.orientation = .horizontal; cycleRow.alignment = .firstBaseline
        mainVerticalStackView.addArrangedSubview(cycleRow)

        let shortcutTogglePageLabel = NSTextField(labelWithString: "Switch to Page:  Command (⌘) + 1...9, 0"); shortcutTogglePageLabel.isEditable = false; shortcutTogglePageLabel.isSelectable = false
        let togglePageIndentView = NSView(); togglePageIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true; let togglePageRow = NSStackView(views: [togglePageIndentView, shortcutTogglePageLabel]); togglePageRow.orientation = .horizontal; togglePageRow.alignment = .firstBaseline
        mainVerticalStackView.addArrangedSubview(togglePageRow)
        
        let actualSizeLabel = NSTextField(labelWithString: "Reset Zoom:  Command (⌘) + Backspace"); actualSizeLabel.isEditable = false; actualSizeLabel.isSelectable = false
        let actualSizeIndentView = NSView(); actualSizeIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true; let actualSizeRow = NSStackView(views: [actualSizeIndentView, actualSizeLabel]); actualSizeRow.orientation = .horizontal; actualSizeRow.alignment = .firstBaseline
        mainVerticalStackView.addArrangedSubview(actualSizeRow)
        
        mainVerticalStackView.translatesAutoresizingMaskIntoConstraints = false; mainVerticalStackView.frame = NSRect(x: 0, y: 0, width: desiredAccessoryViewWidth, height: 10); mainVerticalStackView.layoutSubtreeIfNeeded()
        let requiredHeight = mainVerticalStackView.fittingSize.height; mainVerticalStackView.frame = NSRect(x: 0, y: 0, width: desiredAccessoryViewWidth, height: requiredHeight)
        alert.accessoryView = mainVerticalStackView
        if let accessory = alert.accessoryView { accessory.widthAnchor.constraint(equalToConstant: desiredAccessoryViewWidth).isActive = true }
        alert.window.layoutIfNeeded()

        alert.beginSheetModal(for: window) { response in
            self.handleSettingsAlertResponse(response, alert: alert,
                                             urlTFs: urlTextFields,
                                             labelTFs: labelTextFields,
                                             enabledCBs: enabledCheckboxes,
                                             persistCBs: persistCheckboxes,
                                             unloadPopup: unloadPopup,
                                             cycleBehaviorControl: cycleBehaviorControl, // NEW
                                             autohideCB: autohideCheckbox,
                                             desktopAssignmentControl: desktopAssignmentControl,
                                             windowAlphaSlider: windowAlphaSlider, windowAlphaDisplayLabel: currentWindowAlphaDisplayLabel,
                                             webViewAlphaSlider: webViewAlphaSlider, webViewAlphaDisplayLabel: currentWebViewAlphaDisplayLabel,
                                             temperatureSlider: temperatureSlider,
                                             brightnessSlider: brightnessSlider,
                                             globalBoldFontCB: globalBoldFontCheckbox,
                                             keyTF: keyTextField, optionCB: optionCheckbox, commandCB: commandCheckbox, shiftCB: shiftCheckbox, controlCB: controlCheckbox, currentShortcutDisplayLabel: currentShortcutDisplayLabel)
        }
    }

    private func handleSettingsAlertResponse(
        _ response: NSApplication.ModalResponse, alert: NSAlert,
        urlTFs: [NSTextField],
        labelTFs: [NSTextField],
        enabledCBs: [NSButton],
        persistCBs: [NSButton],
        unloadPopup: NSPopUpButton,
        cycleBehaviorControl: NSSegmentedControl, // NEW
        autohideCB: NSButton,
        desktopAssignmentControl: NSSegmentedControl,
        windowAlphaSlider: NSSlider, windowAlphaDisplayLabel: NSTextField,
        webViewAlphaSlider: NSSlider, webViewAlphaDisplayLabel: NSTextField,
        temperatureSlider: NSSlider,
        brightnessSlider: NSSlider,
        globalBoldFontCB: NSButton,
        keyTF: NSTextField, optionCB: NSButton, commandCB: NSButton, shiftCB: NSButton, controlCB: NSButton, currentShortcutDisplayLabel: NSTextField
    ) {
        if response == .alertFirstButtonReturn {
            NSLog("VC: Settings Save button clicked.")
            
            let newLabels = labelTFs.map { $0.stringValue }
            if newLabels != self.webTabLabels {
                self.webTabLabels = newLabels
                UserDefaults.standard.set(newLabels, forKey: ViewController.webTabLabelsKey)
                NSLog("VC: Settings - Saved labels: \(newLabels)")
            }
            
            let newEnabledStates = enabledCBs.map { $0.state == .on }
            if newEnabledStates != self.webTabEnabledStates {
                self.webTabEnabledStates = newEnabledStates
                UserDefaults.standard.set(newEnabledStates, forKey: ViewController.webTabEnabledKey)
                NSLog("VC: Settings - Saved enabled states: \(newEnabledStates)")
                loadInitialContent()
            }
            
            let newPersistStates = persistCBs.map { $0.state == .on }
            if newPersistStates != self.webTabPersistStates {
                self.webTabPersistStates = newPersistStates
                UserDefaults.standard.set(newPersistStates, forKey: ViewController.webTabPersistKey)
                NSLog("VC: Settings - Saved persist states: \(newPersistStates)")

                for (index, shouldPersist) in newPersistStates.enumerated() {
                    if shouldPersist, let timer = unloadTimers[index] {
                        timer.cancel()
                        unloadTimers.removeValue(forKey: index)
                        NSLog("VC: Settings - Cancelled pending unload for newly persisted tab \(index + 1).")
                    }
                }
            }
            
            for (index, textField) in urlTFs.enumerated() {
                saveURLSetting(for: index, from: textField.stringValue)
            }
            
            if !webTabEnabledStates[activeWebViewIndex] {
                activeWebViewIndex = webTabEnabledStates.firstIndex(of: true) ?? 0
                for (i, webView) in webViews.enumerated() {
                    webView?.isHidden = (i != activeWebViewIndex)
                }
            }
            
            // NEW: Save unload timer duration
            if let selectedDuration = unloadPopup.selectedItem?.representedObject as? Double {
                currentUnloadDelay = selectedDuration
                UserDefaults.standard.set(selectedDuration, forKey: ViewController.unloadTimerDurationKey)
                NSLog("VC: Settings - Unload delay set to: \(selectedDuration) seconds.")
            }
            
            // NEW: Save cycle behavior
            let newCycleBehavior = cycleBehaviorControl.selectedSegment == 1
            if newCycleBehavior != self.cycleWithPersistOnly {
                self.cycleWithPersistOnly = newCycleBehavior
                UserDefaults.standard.set(newCycleBehavior, forKey: ViewController.cycleWithPersistOnlyKey)
                NSLog("VC: Settings - Cycle behavior set to persist only: \(newCycleBehavior)")
            }

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
            
            webViews.compactMap { $0 }.forEach { $0.alphaValue = newWebViewAlphaValue }

            webViewAlphaDisplayLabel.stringValue = String(format: "Content Opacity: %.0f%%", newWebViewAlphaValue * 100)
            NSLog("VC: Settings - Web View alpha set to: \(newWebViewAlphaValue)")
            
            let newTemperatureValue = temperatureSlider.doubleValue
            currentWebpageTemperature = newTemperatureValue
            UserDefaults.standard.set(newTemperatureValue, forKey: ViewController.webpageTemperatureKey)
            applyTemperatureEffect()
            NSLog("VC: Settings - Webpage temperature set to: \(newTemperatureValue)")

            let newBrightnessValue = brightnessSlider.doubleValue
            currentWebpageBrightness = newBrightnessValue
            UserDefaults.standard.set(newBrightnessValue, forKey: ViewController.webpageBrightnessKey)
            applyBrightnessEffect()
            NSLog("VC: Settings - Webpage brightness set to: \(newBrightnessValue)")
            
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

    private func saveURLSetting(for index: Int, from urlString: String) {
        let key = "customURL\(index + 1)_MultiAssistant_v2"
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousUrl = self.urlStrings[index]
        
        guard trimmedUrl != previousUrl else { return }

        if trimmedUrl.isEmpty {
            self.urlStrings[index] = ""
            UserDefaults.standard.set("", forKey: key)
            if let webView = webViews[index], webView.url?.absoluteString != "about:blank" {
                 webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            }
            NSLog("VC: Settings - \(key) cleared. Loading blank page.")
        
        } else if let url = URL(string: trimmedUrl), (url.scheme == "http" || url.scheme == "https") {
            self.urlStrings[index] = trimmedUrl
            UserDefaults.standard.set(trimmedUrl, forKey: key)
            // The view will be loaded/reloaded on next switch if needed
            if let webView = webViews[index], webView.url?.absoluteString != trimmedUrl {
                webView.load(URLRequest(url: url))
            }
            NSLog("VC: Settings - \(key) updated to: \(trimmedUrl)")
            
        } else {
            NSLog("VC: Settings - Invalid URL for \(key): '\(trimmedUrl)'. Not saved. The old value '\(previousUrl)' remains.")
        }
    }
    
    // MARK: - HUD
    private func showTabSwitchHUD(for index: Int) {
        let labelText = webTabLabels[index]
        guard !labelText.isEmpty else { return }

        // Cancel any pending dismissal and remove existing HUD
        hudWorkItem?.cancel()
        view.subviews.filter { $0.tag == 1001 }.forEach { $0.removeFromSuperview() }

        let hudLabel = NSTextField(labelWithString: labelText)
        hudLabel.tag = 1001
        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        hudLabel.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.8)
        hudLabel.textColor = .white
        hudLabel.alignment = .center
        hudLabel.font = .systemFont(ofSize: 24, weight: .bold)
        hudLabel.wantsLayer = true
        hudLabel.layer?.cornerRadius = 16
        hudLabel.isBezeled = false
        hudLabel.drawsBackground = true
        hudLabel.alphaValue = 0.0
        
        // Add padding inside the label
        hudLabel.sizeToFit()
        let horizontalPadding: CGFloat = 40
        let verticalPadding: CGFloat = 20
        let hudWidth = hudLabel.frame.width + horizontalPadding
        let hudHeight = hudLabel.frame.height + verticalPadding

        view.addSubview(hudLabel)
        hudLabel.layer?.zPosition = .greatestFiniteMagnitude
        
        NSLayoutConstraint.activate([
            hudLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hudLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hudLabel.widthAnchor.constraint(equalToConstant: hudWidth),
            hudLabel.heightAnchor.constraint(equalToConstant: hudHeight)
        ])

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hudLabel.animator().alphaValue = 1.0
        })

        let workItem = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                hudLabel.animator().alphaValue = 0.0
            }, completionHandler: {
                hudLabel.removeFromSuperview()
            })
        }
        
        self.hudWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
}

