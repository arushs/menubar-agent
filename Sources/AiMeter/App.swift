import SwiftUI
import AppKit

@main
struct AiMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var agentManager: AgentManager!
    private var popoverContentController: NSHostingController<MenuContentView>!
    private var firstLaunchWindow: NSWindow?
    private var updateTimer: Timer?
    private var isPopoverVisible = false

    // Timer intervals - slower updates when popover is hidden to save resources
    private let activeUpdateInterval: TimeInterval = 1.0   // When popover is shown
    private let idleUpdateInterval: TimeInterval = 5.0     // When popover is hidden

    @AppStorage("hasSeenFirstLaunch") private var hasSeenFirstLaunch = false

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // Hide dock icon - we're a menu bar only app
            NSApp.setActivationPolicy(.accessory)

            // Initialize agent manager
            agentManager = AgentManager.shared

            // Setup menu bar
            setupMenuBar()

            // Show first launch if needed
            if !hasSeenFirstLaunch {
                showFirstLaunchWindow()
            }
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            invalidateTimer()
        }
    }

    private func invalidateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func startTimer(interval: TimeInterval) {
        invalidateTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusIcon()
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateStatusIcon()

            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover with cached content controller
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 400)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        // Create content view once and reuse
        let contentView = MenuContentView(
            agentManager: agentManager,
            showSettings: Binding(
                get: { false },
                set: { [weak self] _ in
                    Task { @MainActor in
                        self?.showSettings()
                    }
                }
            )
        )
        popoverContentController = NSHostingController(rootView: contentView)
        popover.contentViewController = popoverContentController

        // Start with idle (slower) update interval since popover is closed
        startTimer(interval: idleUpdateInterval)
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let symbolName = agentManager.hasActiveAgents ? "terminal.fill" : "terminal"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AiMeter")
        image?.isTemplate = true
        button.image = image?.withSymbolConfiguration(symbolConfig)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showSettings() {
        popover.performClose(nil)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func showFirstLaunchWindow() {
        let contentView = FirstLaunchView()
        let hostingController = NSHostingController(rootView: contentView)

        firstLaunchWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        firstLaunchWindow?.contentViewController = hostingController
        firstLaunchWindow?.title = "Welcome"
        firstLaunchWindow?.center()
        firstLaunchWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSPopoverDelegate
extension AppDelegate: NSPopoverDelegate {
    nonisolated func popoverWillShow(_ notification: Notification) {
        Task { @MainActor in
            isPopoverVisible = true
            // Switch to faster updates when popover is visible
            startTimer(interval: activeUpdateInterval)
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            isPopoverVisible = false
            // Switch to slower updates when popover is hidden
            startTimer(interval: idleUpdateInterval)
        }
    }
}
