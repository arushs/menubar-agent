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

        // Update icon periodically
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusIcon()
            }
        }
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
