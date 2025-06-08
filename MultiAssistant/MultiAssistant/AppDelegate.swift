import Cocoa
import Carbon // For kVK_Space and other key codes
import Carbon.HIToolbox.Events // For kVK_ constants

// Notification name for shortcut changes
extension Notification.Name {
    static let shortcutSettingsChanged = Notification.Name("shortcutSettingsChangedNotification")
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var appWindow: NSWindow? // To keep a reference to your app's main window
    var eventMonitor: Any? // For global keyboard shortcut

    // UserDefaults key for autohide setting
    static let autohideWindowKey = "autohideWindowEnabled"

    // UserDefaults keys for custom shortcut
    static let shortcutKeyCodeKey = "customShortcutKeyCodeKey_v1"
    static let shortcutModifierFlagsKey = "customShortcutModifierFlagsKey_v1"
    static let shortcutKeyCharacterKey = "customShortcutKeyCharacterKey_v1" // For display purposes

    // Properties to store the current shortcut configuration
    var currentShortcutKeyCode: UInt16 = UInt16(kVK_ANSI_Period) // Default: Period
    var currentShortcutModifierFlags: NSEvent.ModifierFlags = .option // Default: Option
    var currentShortcutKeyCharacter: String = "." // Default: Character for Period

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("AppDelegate: applicationDidFinishLaunching. App Active: \(NSApp.isActive)")
        
        // Register default for autohide if not set
        UserDefaults.standard.register(defaults: [AppDelegate.autohideWindowKey: true])
        
        // Load custom shortcut settings or register defaults
        loadShortcutSettings()
        
        setupStatusItem()
        setupGlobalShortcut() // Will now use loaded/default custom shortcut

        // Add observer for app activation
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActiveGlobally),
                                               name: NSApplication.didBecomeActiveNotification,
                                               object: nil)
        
        // Add observer for app deactivation (to auto-hide window)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillResignActiveGlobally),
                                               name: NSApplication.willResignActiveNotification,
                                               object: nil)
        
        // Add observer for shortcut settings changes from ViewController
        NotificationCenter.default.addObserver(self,
                                           selector: #selector(handleShortcutSettingsChanged),
                                           name: .shortcutSettingsChanged,
                                           object: nil)
    }

    func loadShortcutSettings() {
        let defaults = UserDefaults.standard
        // Check if a key code is saved. Use UInt16.max as a sentinel for "no key set".
        if defaults.object(forKey: AppDelegate.shortcutKeyCodeKey) != nil,
           let savedKeyCodeNumber = defaults.object(forKey: AppDelegate.shortcutKeyCodeKey) as? NSNumber {
            
            let savedKeyCode = savedKeyCodeNumber.uint16Value
            
            if savedKeyCode == UInt16.max { // Sentinel for "no key set"
                currentShortcutKeyCode = UInt16.max
                currentShortcutModifierFlags = []
                currentShortcutKeyCharacter = ""
                NSLog("AppDelegate: Loaded shortcut settings - No shortcut set.")
            } else if let savedModifiers = defaults.object(forKey: AppDelegate.shortcutModifierFlagsKey) as? UInt,
                      let savedKeyChar = defaults.string(forKey: AppDelegate.shortcutKeyCharacterKey) {
                currentShortcutKeyCode = savedKeyCode
                currentShortcutModifierFlags = NSEvent.ModifierFlags(rawValue: savedModifiers)
                currentShortcutKeyCharacter = savedKeyChar
                NSLog("AppDelegate: Loaded shortcut settings - KeyCode: \(currentShortcutKeyCode), Modifiers: \(currentShortcutModifierFlags.rawValue), Char: \(currentShortcutKeyCharacter)")
            } else {
                // Incomplete saved data, revert to default
                setDefaultShortcutSettings(defaults: defaults)
            }
        } else {
            // No settings saved, register and use default (Option + Period)
            setDefaultShortcutSettings(defaults: defaults)
        }
    }

    func setDefaultShortcutSettings(defaults: UserDefaults) {
        NSLog("AppDelegate: No/incomplete saved shortcut. Setting defaults: Option + Period")
        currentShortcutKeyCode = UInt16(kVK_ANSI_Period)
        currentShortcutModifierFlags = .option
        currentShortcutKeyCharacter = "."
        defaults.set(NSNumber(value: currentShortcutKeyCode), forKey: AppDelegate.shortcutKeyCodeKey)
        defaults.set(currentShortcutModifierFlags.rawValue, forKey: AppDelegate.shortcutModifierFlagsKey)
        defaults.set(currentShortcutKeyCharacter, forKey: AppDelegate.shortcutKeyCharacterKey)
    }

    @objc func handleShortcutSettingsChanged() {
        NSLog("AppDelegate: Received shortcutSettingsChanged notification.")
        loadShortcutSettings() // Reload from UserDefaults
        setupGlobalShortcut()  // Re-register with new settings
        // Update status item menu title if needed (it's rebuilt on click, so should be fine)
    }
    
    func formattedShortcutString() -> String {
        if currentShortcutKeyCode == UInt16.max || (currentShortcutKeyCharacter.isEmpty && currentShortcutKeyCode == 0) { // 0 can be 'A', so check char too
            return "Not Set"
        }

        var parts: [String] = []
        if currentShortcutModifierFlags.contains(.control) { parts.append("⌃") } // Control
        if currentShortcutModifierFlags.contains(.option) { parts.append("⌥") }  // Option
        if currentShortcutModifierFlags.contains(.shift) { parts.append("⇧") }   // Shift
        if currentShortcutModifierFlags.contains(.command) { parts.append("⌘") } // Command
        
        let keyString = currentShortcutKeyCharacter.isEmpty ? "Key \(currentShortcutKeyCode)" : currentShortcutKeyCharacter.uppercased()
        parts.append(keyString)
        
        return parts.joined() // No separator for typical shortcut display like ⌘⇧A
    }

    @objc func applicationDidBecomeActiveGlobally() {
        NSLog("AppDelegate: applicationDidBecomeActiveGlobally. App Active: \(NSApp.isActive)")
        guard let window = appWindow else {
            NSLog("AppDelegate: appWindow is nil during global didBecomeActive.")
            return
        }

        if !window.isVisible {
            NSLog("AppDelegate: Window was hidden on global activation, calling showWindowAction().")
            showWindowAction()
        } else {
            NSLog("AppDelegate: Window is already visible on global activation. IsKey: \(window.isKeyWindow)")
            if !window.isKeyWindow {
                NSLog("AppDelegate: Window visible but not key. Attempting makeKeyAndOrderFront.")
                window.makeKeyAndOrderFront(nil)
            }
            DispatchQueue.main.async {
                if let viewController = window.contentViewController as? ViewController {
                    NSLog("AppDelegate: Triggering attemptWebViewFocus from applicationDidBecomeActiveGlobally (window was visible).")
                    viewController.attemptWebViewFocus()
                }
            }
        }
    }
    
    @objc func applicationWillResignActiveGlobally() {
        NSLog("AppDelegate: applicationWillResignActiveGlobally. App Active: \(NSApp.isActive)")
        let autohideEnabled = UserDefaults.standard.bool(forKey: AppDelegate.autohideWindowKey)
        if autohideEnabled, let window = appWindow, window.isVisible {
            NSLog("AppDelegate: Window is visible, app is resigning active, and autohide is ON. Auto-hiding window.")
            window.orderOut(nil)
        } else if !autohideEnabled {
            NSLog("AppDelegate: App resigning active, but autohide is OFF. Window will remain visible.")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .shortcutSettingsChanged, object: nil) // Remove new observer
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NSLog("AppDelegate: deinit, removed notification observers and event monitor.")
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "MultiAssistant")
            } else {
                button.title = "MA"
            }
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            NSLog("AppDelegate: Status item setup complete.")
        } else {
            NSLog("AppDelegate: Failed to create status item button.")
        }
    }

    @objc func statusItemClicked(_ sender: AnyObject?) {
        guard let item = statusItem else {
            NSLog("AppDelegate: statusItemClicked called but statusItem is nil.")
            return
        }
        NSLog("AppDelegate: Status item clicked.")

        let menu = NSMenu()
        let viewController = appWindow?.contentViewController as? ViewController
        
        // Use the formatted string for the current shortcut
        let shortcutDisplayString = self.formattedShortcutString()

        if appWindow?.isVisible == true {
            menu.addItem(withTitle: "Hide Window (\(shortcutDisplayString))", action: #selector(hideWindowAction), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Show Window (\(shortcutDisplayString))", action: #selector(showWindowAction), keyEquivalent: "")
        }
        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh Page", action: #selector(ViewController.refreshCurrentPage), keyEquivalent: "r")
        menu.addItem(refreshItem)

        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(ViewController.zoomInPage), keyEquivalent: "=")
        menu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(ViewController.zoomOutPage), keyEquivalent: "-")
        menu.addItem(zoomOutItem)

        let actualSizeItem = NSMenuItem(title: "Actual Size", action: #selector(ViewController.actualSizePage), keyEquivalent: "0")
        menu.addItem(actualSizeItem)
        
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(ViewController.openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)
        
        let aboutItem = NSMenuItem(title: "About MultiAssistant", action: #selector(showAboutPanelAction), keyEquivalent: "")
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit MultiAssistant", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        if let vc = viewController {
            let itemsRequiringVisibleWindowAndVC = [refreshItem, zoomInItem, zoomOutItem, actualSizeItem]
            settingsItem.target = vc // ViewController handles settings
            aboutItem.target = self // AppDelegate handles about

            if appWindow?.isVisible == true {
                for menuItem in itemsRequiringVisibleWindowAndVC {
                    menuItem.target = vc
                }
            } else {
                for menuItem in itemsRequiringVisibleWindowAndVC {
                    menuItem.target = nil
                    menuItem.action = nil
                }
            }
        } else {
            [refreshItem, zoomInItem, zoomOutItem, actualSizeItem, settingsItem].forEach {
                $0.target = nil
                $0.action = nil
            }
            aboutItem.target = self // AppDelegate handles about
        }
        
        item.menu = menu
        item.button?.performClick(nil) // Show the menu
        item.menu = nil // Allow menu to be dismissed
    }

    @objc func showWindowAction() {
        NSLog("AppDelegate: showWindowAction called. App Active before activate: \(NSApp.isActive)")
        guard let window = appWindow else {
            NSLog("AppDelegate: showWindowAction - appWindow is nil.")
            if let vcWindow = (NSApp.windows.first(where: { $0.contentViewController is ViewController })) {
                NSLog("AppDelegate: showWindowAction - Found window via ViewController. Setting and retrying.")
                self.appWindow = vcWindow
                showWindowAction() // Retry
            } else {
                 NSLog("AppDelegate: showWindowAction - No appWindow and could not find window via ViewController.")
            }
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        NSLog("AppDelegate: NSApp.activate called. App Active after activate: \(NSApp.isActive)")
        
        window.makeKeyAndOrderFront(nil)
        NSLog("AppDelegate: window.makeKeyAndOrderFront called. Window isVisible: \(window.isVisible), isKey (immediately after): \(window.isKeyWindow)")

        DispatchQueue.main.async {
            NSLog("AppDelegate: Dispatching to ViewController.attemptWebViewFocus. Window isKey: \(window.isKeyWindow)")
            if let viewController = window.contentViewController as? ViewController {
                viewController.attemptWebViewFocus()
            } else {
                NSLog("AppDelegate: Could not get ViewController from appWindow to call attemptWebViewFocus.")
            }
        }
    }

    @objc func hideWindowAction() {
        NSLog("AppDelegate: hideWindowAction called.")
        appWindow?.orderOut(nil)
        NSLog("AppDelegate: Window ordered out via hideWindowAction.")
    }
    
    @objc func toggleWindowVisibility() {
        if appWindow?.isVisible == true {
            hideWindowAction()
        } else {
            showWindowAction()
        }
    }

    func setupGlobalShortcut() {
        // Remove existing monitor before setting up a new one
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            NSLog("AppDelegate: Removed existing global shortcut monitor.")
        }

        // If no key is set (using sentinel), don't register a shortcut
        if currentShortcutKeyCode == UInt16.max {
            NSLog("AppDelegate: Global shortcut setup SKIPPED: No key is set by user.")
            return
        }
        
        // Also, ensure there's actually a key character or valid keycode if modifiers are also empty.
        // A shortcut of "just modifiers" is usually not intended.
        // However, a single F-key without modifiers is valid.
        // The primary check is `currentShortcutKeyCode != UInt16.max`.

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }

            // Relevant modifier flags for comparison
            let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let eventModifiers = event.modifierFlags.intersection(relevantFlags)
            
            // Debug log for all key presses if needed, but can be verbose
            // NSLog("Global KeyDown: Event Code \(event.keyCode), Event Mods \(eventModifiers.rawValue) | Target: Code \(self.currentShortcutKeyCode), Mods \(self.currentShortcutModifierFlags.rawValue)")

            if event.keyCode == self.currentShortcutKeyCode && eventModifiers == self.currentShortcutModifierFlags {
                NSLog("AppDelegate: Global shortcut detected (KeyCode: \(self.currentShortcutKeyCode), Modifiers: \(self.currentShortcutModifierFlags.rawValue), Char: \(self.currentShortcutKeyCharacter)). Toggling window.")
                self.toggleWindowVisibility()
            }
        }
        
        if eventMonitor != nil {
            NSLog("AppDelegate: Global shortcut monitor setup for KeyCode: \(currentShortcutKeyCode), Modifiers: \(currentShortcutModifierFlags.rawValue), Char: \(currentShortcutKeyCharacter)")
        } else {
             NSLog("AppDelegate: FAILED to register global shortcut. KeyCode: \(currentShortcutKeyCode), Modifiers: \(currentShortcutModifierFlags.rawValue). This might be due to Accessibility permissions or the shortcut being used by the system/another app.")
        }
    }
    
    @objc func showAboutPanelAction() {
        NSLog("AppDelegate: showAboutPanelAction called.")
        
        let icon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
        let finalIcon = icon ?? NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "Information")

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "MultiAssistant"
        alert.informativeText = """
        Version 1.3
        Developed by ZhangZheng & Gemini 2.5 Pro
        """
        alert.icon = finalIcon
        alert.addButton(withTitle: "OK")
        
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    public func setAppWindow(_ window: NSWindow) {
        NSLog("AppDelegate: setAppWindow called by ViewController.")
        self.appWindow = window
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        NSLog("AppDelegate: applicationWillTerminate.")
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSLog("AppDelegate: applicationShouldTerminateAfterLastWindowClosed returning false.")
        return false
    }
}

