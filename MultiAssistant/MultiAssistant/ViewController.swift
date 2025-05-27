import Cocoa
import WebKit
import Carbon.HIToolbox.Events // For kVK_ constants

class ViewController: NSViewController,
                     WKNavigationDelegate,
                     WKUIDelegate,
                     NSWindowDelegate {

    // MARK: - UI Elements & State
    private var webView1: WKWebView!
    private var webView2: WKWebView!

    // Configuration constants
    private let defaultUrlString1 = "https://chat.openai.com/"
    private let defaultUrlString2 = "https://gemini.google.com/app"
    private let cornerRadiusValue: CGFloat = 12.0
    private let zoomStep: CGFloat   = 0.1
    private let minZoom: CGFloat    = 0.5
    private let maxZoom: CGFloat    = 3.0
    private let windowAutosaveName = "MultiAssistantMainWindow_v1"

    // Runtime state
    private var webView1ZoomScale: CGFloat = 1.0
    private var webView2ZoomScale: CGFloat = 1.0
    private var urlString1: String!
    private var urlString2: String!
    // Removed: static let idleHideDelaySecondsKey
    
    private var webViewsReloadingAfterTermination: Set<WKWebView> = []
    private var activeWebView: WKWebView { webView1.isHidden ? webView2 : webView1 }
    private var windowChromeConfigured = false

    // MARK: - View / Window Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("VC: viewDidLoad")
        // Removed: UserDefaults.standard.register(defaults: [ViewController.idleHideDelaySecondsKey: 5.0])
        loadSettings()
        configureContainerLayer()
        setupWebViews()
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
        NSLog("VC: Container layer configured.")
    }

    private func setupWebViews() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView1 = WKWebView(frame: .zero, configuration: config)
        webView2 = WKWebView(frame: .zero, configuration: config)
        
        [webView1, webView2].forEach { wv in
            wv.navigationDelegate = self
            wv.uiDelegate = self
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
        NSLog("VC: WebViews setup complete.")
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
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.setFrameAutosaveName(windowAutosaveName)
        window.collectionBehavior = .canJoinAllSpaces

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
        NSLog("VC: setupWindowChrome - Configuration complete.")
    }

    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers else { return event }
            if self.view.window?.attachedSheet != nil {
                return event
            }
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
        NSLog("VC: Settings loaded. URL1: \(urlString1 ?? "nil"), URL2: \(urlString2 ?? "nil"), Zoom1: \(webView1ZoomScale), Zoom2: \(webView2ZoomScale)")
    }

    private func loadInitialContent() {
        if let u1 = URL(string: urlString1) { webView1.load(URLRequest(url: u1)) } else { NSLog("VC: Invalid URL1: \(urlString1 ?? "nil")")}
        if let u2 = URL(string: urlString2) { webView2.load(URLRequest(url: u2)) } else { NSLog("VC: Invalid URL2: \(urlString2 ?? "nil")")}
    }

    // MARK: - Focus Handling
    @objc func attemptWebViewFocus() {
        NSLog("VC: attemptWebViewFocus called.")
        guard let window = self.view.window else {
            NSLog("VC: attemptWebViewFocus - No window.")
            return
        }
        
        let webViewToFocus = self.activeWebView
        let webViewName = webViewToFocus == self.webView1 ? "WebView1" : "WebView2"
        
        NSLog("VC: attemptWebViewFocus for \(webViewName). AppIsActive: \(NSApp.isActive), WindowIsKey: \(window.isKeyWindow), WindowIsVisible: \(window.isVisible)")

        if !window.isKeyWindow {
            NSLog("VC: attemptWebViewFocus - Window is NOT key. Attempting to make it key.")
            window.makeKeyAndOrderFront(nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSLog("VC: attemptWebViewFocus (after 0.05s delay) - WindowIsKey: \(window.isKeyWindow)")
                if window.isKeyWindow {
                    self.proceedWithFirstResponder(for: webViewToFocus, window: window)
                } else {
                    NSLog("VC: attemptWebViewFocus (delayed) - Window STILL NOT key. Focus might fail.")
                    self.proceedWithFirstResponder(for: webViewToFocus, window: window)
                }
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
            executeJavaScriptFocus(reason: "proceedWithFirstResponder")
        } else {
            NSLog("VC: proceedWithFirstResponder - FAILED: Could not make \(webViewName) first responder.")
            if window.firstResponder != webViewToFocus && window.canBecomeKey {
                 NSLog("VC: proceedWithFirstResponder - Making window itself first responder as a fallback.")
                 window.makeFirstResponder(self.view)
                 executeJavaScriptFocus(reason: "proceedWithFirstResponder_fallbackFR")
            }
        }
    }

    private func executeJavaScriptFocus(reason: String) {
        let webViewToFocus = self.activeWebView
        let webViewName = webViewToFocus == self.webView1 ? "WebView1" : "WebView2"
        let jsReason = "JS Focus Attempt - \(reason)"
        NSLog("VC: executeJavaScriptFocus for \(webViewName) - Reason: \(reason)")
        
        let javascript = """
            (function() {
                console.log('[\(jsReason)] Starting. document.hasFocus(): ' + document.hasFocus());
                let target = document.getElementById('prompt-textarea'); 
                if (!target) { 
                     target = document.querySelector('textarea:not([disabled]):not([readonly]), input[type="text"]:not([disabled]):not([readonly]), div[contenteditable="true"]:not([disabled])');
                }
                if (target) {
                    console.log('[\(jsReason)] Found target. Attempting focus/click.');
                    if (typeof target.focus === 'function') { target.focus(); }
                    if (typeof target.click === 'function') { target.click(); } 
                    setTimeout(function() {
                        console.log('[\(jsReason)] After attempts. Active element: ' + (document.activeElement ? document.activeElement.tagName : 'null') + '. Document has focus: ' + document.hasFocus());
                    }, 100);
                } else {
                    console.log('[\(jsReason)] No suitable target found. Focusing body.');
                    if (document.body && typeof document.body.focus === 'function') { document.body.focus(); }
                }
            })();
        """
        webViewToFocus.evaluateJavaScript(javascript) { result, error in
            if let error = error { NSLog("VC: \(jsReason) Error exec JS for \(webViewName): \(error.localizedDescription)") }
            else { NSLog("VC: \(jsReason) JS exec for \(webViewName) initiated. Result: \(String(describing: result))") }
        }
    }
    
    // MARK: - Actions & Web Control
    @objc func togglePage() {
        NSLog("VC: Toggling page.")
        webView1.isHidden.toggle()
        webView2.isHidden.toggle()

        // --- START OF PROPOSED FIX ---
        // Ensure the currently visible webView is the top-most view
        // to correctly receive drag-and-drop events.
        // The 'activeWebView' computed property will correctly give us the one that is now visible.
        let currentActiveWebView = activeWebView
        view.addSubview(currentActiveWebView) // This removes it and re-adds it on top
        // --- END OF PROPOSED FIX ---

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
        if wv == webView1 {
            webView1ZoomScale = scale
            targetScaleKey = "webView1ZoomScale_MultiAssistant_v1"
        } else {
            webView2ZoomScale = scale
            targetScaleKey = "webView2ZoomScale_MultiAssistant_v1"
        }
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

        if view.window?.isKeyWindow == true || webViewsReloadingAfterTermination.contains(wv) {
            NSLog("VC: WebView \(webViewName) finished, attempting focus.")
            attemptWebViewFocus()
        }
        webViewsReloadingAfterTermination.remove(wv)
    }

    func webViewWebContentProcessDidTerminate(_ wv: WKWebView) {
        let webViewName = wv == webView1 ? "WebView1" : "WebView2"
        NSLog("VC: CRITICAL - WebView \(webViewName) content process did terminate. Reloading.")
        webViewsReloadingAfterTermination.insert(wv)
        wv.reload()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let webViewName = (webView == webView1) ? "Page 1" : "Page 2"
        NSLog("VC: \(webViewName) failed provisional navigation: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let webViewName = (webView == webView1) ? "Page 1" : "Page 2"
        NSLog("VC: \(webViewName) failed navigation: \(error.localizedDescription)")
    }

    // MARK: - Settings Sheet (⌘,)
    @objc func openSettings() {
        NSLog("VC: Open Settings action triggered.")
        guard let window = view.window else {
            NSLog("VC: OpenSettings - No window. Attempting to show via AppDelegate.")
            (NSApp.delegate as? AppDelegate)?.showWindowAction()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.view.window != nil { self.presentSettingsAlert() }
                else { NSLog("VC: OpenSettings - Window still not available after delay.")}
            }
            return
        }

        if !window.isVisible || !window.isKeyWindow {
            NSLog("VC: OpenSettings - Window not visible/key. Activating.")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.presentSettingsAlert()
            }
        } else {
            presentSettingsAlert()
        }
    }
    
    private func createSeparatorBox() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    private func createSectionHeader(title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func presentSettingsAlert() {
        guard let window = self.view.window, window.isVisible, window.isKeyWindow else {
            NSLog("VC: PresentSettingsAlert - Window conditions not met (not visible or not key).")
            if let w = self.view.window, !w.isKeyWindow {
                w.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.presentSettingsAlert() }
                return
            }
            return
        }
        NSLog("VC: PresentSettingsAlert - Preparing settings UI.")

        let alert = NSAlert()
        alert.messageText = "MultiAssistant Settings"
        alert.informativeText = "Customize URLs, window behavior, and global shortcuts."
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Cancel")

        let desiredAccessoryViewWidth: CGFloat = 720
                                        
        let labelColumnWidth: CGFloat = 140
        
        let hStackSpacing: CGFloat = 12
        let vStackRowSpacing: CGFloat = 16
        let sectionHeaderSpacing: CGFloat = 8
        let sectionBottomSpacing: CGFloat = 24
        let outerPadding: CGFloat = 25

        func createSettingRow(labelString: String, control: NSView) -> NSStackView {
            let label = NSTextField(labelWithString: labelString)
            label.alignment = .right
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            label.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true
            
            control.translatesAutoresizingMaskIntoConstraints = false
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let hStack = NSStackView(views: [label, control])
            hStack.orientation = .horizontal
            hStack.spacing = hStackSpacing
            hStack.alignment = .firstBaseline
            hStack.distribution = .fill
            
            return hStack
        }
        
        let urlSectionHeader = createSectionHeader(title: "Web Page URLs")
        let url1TextField = NSTextField(string: urlString1 ?? defaultUrlString1)
        url1TextField.placeholderString = "e.g., https://chat.openai.com"
        let url1Row = createSettingRow(labelString: "Page 1 URL:", control: url1TextField)

        let url2TextField = NSTextField(string: urlString2 ?? defaultUrlString2)
        url2TextField.placeholderString = "e.g., https://gemini.google.com"
        let url2Row = createSettingRow(labelString: "Page 2 URL:", control: url2TextField)

        let behaviorSectionHeader = createSectionHeader(title: "Window Behavior")
        let autohideCheckbox = NSButton(checkboxWithTitle: "Auto-hide window when application is inactive", target: nil, action: nil)
        autohideCheckbox.state = UserDefaults.standard.bool(forKey: AppDelegate.autohideWindowKey) ? .on : .off
        autohideCheckbox.translatesAutoresizingMaskIntoConstraints = false
        
        let autohideIndentView = NSView()
        autohideIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true
        let autohideControlRow = NSStackView(views: [autohideIndentView, autohideCheckbox])
        autohideControlRow.orientation = .horizontal
        autohideControlRow.spacing = 0
        autohideControlRow.alignment = .firstBaseline

        // Removed Idle Time UI elements:
        // let idleTimeLabel = NSTextField(labelWithString: "seconds (0 to disable)")
        // let idleTimeTextField = NSTextField(string: String(format: "%.1f", UserDefaults.standard.double(forKey: ViewController.idleHideDelaySecondsKey)))
        // let idleTimeHStack = NSStackView(views: [idleTimeTextField, idleTimeLabel])
        // let idleTimeRow = createSettingRow(labelString: "Auto-hide after inactivity:", control: idleTimeHStack)

        let globalShortcutSectionHeader = createSectionHeader(title: "Global Toggle Shortcut (Show/Hide Window)")
        
        let currentShortcutDisplayLabel = NSTextField(labelWithString: "Current: \( (NSApp.delegate as? AppDelegate)?.formattedShortcutString() ?? "Not Set" )")
        currentShortcutDisplayLabel.isEditable = false
        currentShortcutDisplayLabel.isSelectable = false
        let currentShortcutIndentView = NSView()
        currentShortcutIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true
        let currentShortcutRow = NSStackView(views: [currentShortcutIndentView, currentShortcutDisplayLabel])
        currentShortcutRow.orientation = .horizontal
        currentShortcutRow.alignment = .firstBaseline

        let keyTextField = NSTextField(string: (NSApp.delegate as? AppDelegate)?.currentShortcutKeyCharacter ?? "")
        keyTextField.placeholderString = "e.g., . or A"
        keyTextField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let keyRow = createSettingRow(labelString: "Key:", control: keyTextField)

        let optionCheckbox = NSButton(checkboxWithTitle: "Option (⌥)", target: nil, action: nil)
        let commandCheckbox = NSButton(checkboxWithTitle: "Command (⌘)", target: nil, action: nil)
        let shiftCheckbox = NSButton(checkboxWithTitle: "Shift (⇧)", target: nil, action: nil)
        let controlCheckbox = NSButton(checkboxWithTitle: "Control (⌃)", target: nil, action: nil)
        
        if let appDelegate = NSApp.delegate as? AppDelegate {
            optionCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.option) ? .on : .off
            commandCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.command) ? .on : .off
            shiftCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.shift) ? .on : .off
            controlCheckbox.state = appDelegate.currentShortcutModifierFlags.contains(.control) ? .on : .off
        }
        
        let modifiersCheckboxHStack = NSStackView(views: [optionCheckbox, commandCheckbox, shiftCheckbox, controlCheckbox])
        modifiersCheckboxHStack.orientation = .horizontal
        modifiersCheckboxHStack.spacing = hStackSpacing * 1.2
        modifiersCheckboxHStack.alignment = .centerY
        modifiersCheckboxHStack.distribution = .fillProportionally
        let modifiersRow = createSettingRow(labelString: "Modifiers:", control: modifiersCheckboxHStack)
        
        let otherShortcutsSectionHeader = createSectionHeader(title: "In-App Shortcuts")
        let shortcutTogglePageLabel = NSTextField(labelWithString: "Toggle Page 1/2:  Command (⌘) + 1")
        shortcutTogglePageLabel.isEditable = false
        shortcutTogglePageLabel.isSelectable = false
        let togglePageIndentView = NSView()
        togglePageIndentView.widthAnchor.constraint(equalToConstant: labelColumnWidth + hStackSpacing).isActive = true
        let togglePageRow = NSStackView(views: [togglePageIndentView, shortcutTogglePageLabel])
        togglePageRow.orientation = .horizontal
        togglePageRow.alignment = .firstBaseline

        let mainVerticalStackView = NSStackView()
        mainVerticalStackView.orientation = .vertical
        mainVerticalStackView.spacing = vStackRowSpacing
        mainVerticalStackView.alignment = .leading
        mainVerticalStackView.edgeInsets = NSEdgeInsets(top: outerPadding, left: outerPadding, bottom: outerPadding, right: outerPadding)
        
        mainVerticalStackView.addArrangedSubview(urlSectionHeader)
        mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: urlSectionHeader)
        mainVerticalStackView.addArrangedSubview(url1Row)
        mainVerticalStackView.addArrangedSubview(url2Row)
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: url2Row)

        mainVerticalStackView.addArrangedSubview(createSeparatorBox())
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)

        mainVerticalStackView.addArrangedSubview(behaviorSectionHeader)
        mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: behaviorSectionHeader)
        mainVerticalStackView.addArrangedSubview(autohideControlRow)
        // Removed: mainVerticalStackView.addArrangedSubview(idleTimeRow)
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: autohideControlRow) // Adjusted to space after autohideControlRow

        mainVerticalStackView.addArrangedSubview(createSeparatorBox())
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)

        mainVerticalStackView.addArrangedSubview(globalShortcutSectionHeader)
        mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: globalShortcutSectionHeader)
        mainVerticalStackView.addArrangedSubview(currentShortcutRow)
        mainVerticalStackView.addArrangedSubview(keyRow)
        mainVerticalStackView.addArrangedSubview(modifiersRow)
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing, after: modifiersRow)
        
        mainVerticalStackView.addArrangedSubview(createSeparatorBox())
        mainVerticalStackView.setCustomSpacing(sectionBottomSpacing * 0.8, after: mainVerticalStackView.arrangedSubviews.last!)

        mainVerticalStackView.addArrangedSubview(otherShortcutsSectionHeader)
        mainVerticalStackView.setCustomSpacing(sectionHeaderSpacing, after: otherShortcutsSectionHeader)
        mainVerticalStackView.addArrangedSubview(togglePageRow)

        mainVerticalStackView.translatesAutoresizingMaskIntoConstraints = false
        alert.accessoryView = mainVerticalStackView
        
        mainVerticalStackView.frame = NSRect(x: 0, y: 0, width: desiredAccessoryViewWidth, height: 0)
        mainVerticalStackView.layoutSubtreeIfNeeded()
        let requiredHeight = mainVerticalStackView.fittingSize.height
        mainVerticalStackView.frame = NSRect(x: 0, y: 0, width: desiredAccessoryViewWidth, height: requiredHeight)
        
        if let accessory = alert.accessoryView {
             accessory.widthAnchor.constraint(equalToConstant: desiredAccessoryViewWidth).isActive = true
        }
        
        alert.window.layoutIfNeeded()
        
        alert.beginSheetModal(for: window) { response in
            self.handleSettingsAlertResponse(response,
                                             alert: alert,
                                             url1TF: url1TextField,
                                             url2TF: url2TextField,
                                             autohideCB: autohideCheckbox,
                                             // Removed: idleTimeTF: idleTimeTextField,
                                             keyTF: keyTextField,
                                             optionCB: optionCheckbox,
                                             commandCB: commandCheckbox,
                                             shiftCB: shiftCheckbox,
                                             controlCB: controlCheckbox,
                                             currentShortcutDisplayLabel: currentShortcutDisplayLabel
                                            )
        }
    }
    
    private func handleSettingsAlertResponse(
        _ response: NSApplication.ModalResponse,
        alert: NSAlert,
        url1TF: NSTextField, url2TF: NSTextField,
        autohideCB: NSButton, // Removed idleTimeTF parameter
        keyTF: NSTextField,
        optionCB: NSButton, commandCB: NSButton, shiftCB: NSButton, controlCB: NSButton,
        currentShortcutDisplayLabel: NSTextField
    ) {
        if response == .alertFirstButtonReturn {
            NSLog("VC: Settings Save button clicked.")
            self.saveSettings(urlString: url1TF.stringValue, forKey: "customURL1_MultiAssistant_v1", defaultURL: self.defaultUrlString1, webView: self.webView1) { self.urlString1 = $0 }
            self.saveSettings(urlString: url2TF.stringValue, forKey: "customURL2_MultiAssistant_v1", defaultURL: self.defaultUrlString2, webView: self.webView2) { self.urlString2 = $0 }
            
            let autohideEnabled = autohideCB.state == .on
            UserDefaults.standard.set(autohideEnabled, forKey: AppDelegate.autohideWindowKey)
            NSLog("VC: Settings - Autohide window set to: \(autohideEnabled)")

            // Removed saving logic for Idle Time
            // if let idleTimeValue = Double(idleTimeTF.stringValue) { ... }

            var newModifiers = NSEvent.ModifierFlags()
            if optionCB.state == .on { newModifiers.insert(.option) }
            if commandCB.state == .on { newModifiers.insert(.command) }
            if shiftCB.state == .on { newModifiers.insert(.shift) }
            if controlCB.state == .on { newModifiers.insert(.control) }

            let rawKeyString = keyTF.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var finalKeyCode: UInt16 = UInt16.max
            var finalKeyCharacter: String = ""

            if !rawKeyString.isEmpty {
                finalKeyCharacter = String(rawKeyString.prefix(1)).uppercased()
                
                switch finalKeyCharacter {
                    case ".": finalKeyCode = UInt16(kVK_ANSI_Period)
                    case ",": finalKeyCode = UInt16(kVK_ANSI_Comma)
                    case ";": finalKeyCode = UInt16(kVK_ANSI_Semicolon)
                    case "'": finalKeyCode = UInt16(kVK_ANSI_Quote)
                    case "/": finalKeyCode = UInt16(kVK_ANSI_Slash)
                    case "\\": finalKeyCode = UInt16(kVK_ANSI_Backslash)
                    case "`": finalKeyCode = UInt16(kVK_ANSI_Grave)
                    case "-": finalKeyCode = UInt16(kVK_ANSI_Minus)
                    case "=": finalKeyCode = UInt16(kVK_ANSI_Equal)
                    case "[": finalKeyCode = UInt16(kVK_ANSI_LeftBracket)
                    case "]": finalKeyCode = UInt16(kVK_ANSI_RightBracket)
                    case "A": finalKeyCode = UInt16(kVK_ANSI_A); case "B": finalKeyCode = UInt16(kVK_ANSI_B)
                    case "C": finalKeyCode = UInt16(kVK_ANSI_C); case "D": finalKeyCode = UInt16(kVK_ANSI_D)
                    case "E": finalKeyCode = UInt16(kVK_ANSI_E); case "F": finalKeyCode = UInt16(kVK_ANSI_F)
                    case "G": finalKeyCode = UInt16(kVK_ANSI_G); case "H": finalKeyCode = UInt16(kVK_ANSI_H)
                    case "I": finalKeyCode = UInt16(kVK_ANSI_I); case "J": finalKeyCode = UInt16(kVK_ANSI_J)
                    case "K": finalKeyCode = UInt16(kVK_ANSI_K); case "L": finalKeyCode = UInt16(kVK_ANSI_L)
                    case "M": finalKeyCode = UInt16(kVK_ANSI_M); case "N": finalKeyCode = UInt16(kVK_ANSI_N)
                    case "O": finalKeyCode = UInt16(kVK_ANSI_O); case "P": finalKeyCode = UInt16(kVK_ANSI_P)
                    case "Q": finalKeyCode = UInt16(kVK_ANSI_Q); case "R": finalKeyCode = UInt16(kVK_ANSI_R)
                    case "S": finalKeyCode = UInt16(kVK_ANSI_S); case "T": finalKeyCode = UInt16(kVK_ANSI_T)
                    case "U": finalKeyCode = UInt16(kVK_ANSI_U); case "V": finalKeyCode = UInt16(kVK_ANSI_V)
                    case "W": finalKeyCode = UInt16(kVK_ANSI_W); case "X": finalKeyCode = UInt16(kVK_ANSI_X)
                    case "Y": finalKeyCode = UInt16(kVK_ANSI_Y); case "Z": finalKeyCode = UInt16(kVK_ANSI_Z)
                    case "0": finalKeyCode = UInt16(kVK_ANSI_0); case "1": finalKeyCode = UInt16(kVK_ANSI_1)
                    case "2": finalKeyCode = UInt16(kVK_ANSI_2); case "3": finalKeyCode = UInt16(kVK_ANSI_3)
                    case "4": finalKeyCode = UInt16(kVK_ANSI_4); case "5": finalKeyCode = UInt16(kVK_ANSI_5)
                    case "6": finalKeyCode = UInt16(kVK_ANSI_6); case "7": finalKeyCode = UInt16(kVK_ANSI_7)
                    case "8": finalKeyCode = UInt16(kVK_ANSI_8); case "9": finalKeyCode = UInt16(kVK_ANSI_9)
                    case "F1": finalKeyCode = UInt16(kVK_F1); case "F2": finalKeyCode = UInt16(kVK_F2)
                    default:
                        NSLog("VC: Warning - Key character '\(finalKeyCharacter)' not in simple map. Shortcut might not work as expected or will be unset if mapping fails.")
                        finalKeyCode = UInt16.max
                        finalKeyCharacter = ""
                }
            } else {
                finalKeyCode = UInt16.max
                finalKeyCharacter = ""
                newModifiers = []
            }
            
            let defaults = UserDefaults.standard
            defaults.set(NSNumber(value: finalKeyCode), forKey: AppDelegate.shortcutKeyCodeKey)
            defaults.set(newModifiers.rawValue, forKey: AppDelegate.shortcutModifierFlagsKey)
            defaults.set(finalKeyCharacter, forKey: AppDelegate.shortcutKeyCharacterKey)
            NSLog("VC: Saved shortcut - KeyCode: \(finalKeyCode), Modifiers: \(newModifiers.rawValue), Char: '\(finalKeyCharacter)'")

            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.currentShortcutKeyCode = finalKeyCode
                appDelegate.currentShortcutModifierFlags = newModifiers
                appDelegate.currentShortcutKeyCharacter = finalKeyCharacter
            }
            
            NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)

        } else {
            NSLog("VC: Settings Cancel button clicked or sheet dismissed.")
        }
    }

    private func saveSettings(urlString: String, forKey key: String, defaultURL: String, webView: WKWebView, assignToInstanceVar: @escaping (String) -> Void) {
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUrl.isEmpty {
            UserDefaults.standard.set(defaultURL, forKey: key)
            assignToInstanceVar(defaultURL)
            if let url = URL(string: defaultURL) { webView.load(URLRequest(url: url)) }
             NSLog("VC: Settings - \(key) reset to default: \(defaultURL)")
        } else if let url = URL(string: trimmedUrl), (url.scheme == "http" || url.scheme == "https") {
            UserDefaults.standard.set(trimmedUrl, forKey: key)
            assignToInstanceVar(trimmedUrl)
            webView.load(URLRequest(url: url))
             NSLog("VC: Settings - \(key) updated to: \(trimmedUrl)")
        } else {
            NSLog("VC: Settings - Invalid URL for \(key): '\(trimmedUrl)'. Not saved.")
        }
    }
}

// Helper extension for NumberFormatter (can be removed if no longer needed by other parts of the app)
// extension NumberFormatter {
//    static func decimalFormatter(minimum: NSNumber? = nil, maximum: NSNumber? = nil, minimumFractionDigits: Int = 0, maximumFractionDigits: Int = 2) -> NumberFormatter {
//        let formatter = NumberFormatter()
//        formatter.numberStyle = .decimal
//        formatter.minimum = minimum
//        formatter.maximum = maximum
//        formatter.minimumFractionDigits = minimumFractionDigits
//        formatter.maximumFractionDigits = maximumFractionDigits
//        formatter.allowsFloats = true
//        return formatter
//    }
// }
