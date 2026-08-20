import AppKit
import SwiftUI

@main
struct KvartzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: .shared)
                .frame(width: 620, height: 600)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: QueryPanelController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: NSWindowController?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = QueryPanelController(model: .shared)
        hotKeyManager = HotKeyManager(shortcut: AppModel.shared.shortcut) { [weak self] in
            Task { @MainActor in self?.panelController?.toggle() }
        }
        configureMenuBarItem()

        observers.append(NotificationCenter.default.addObserver(
            forName: .kvartzShortcutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hotKeyManager?.register(AppModel.shared.shortcut) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .kvartzOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showSettings() }
        })

        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.panelController?.show()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func configureMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "message", accessibilityDescription: "Kvartz")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        let ask = NSMenuItem(title: "Ask Kvartz", action: #selector(showPanel), keyEquivalent: "")
        ask.target = self
        menu.addItem(ask)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Kvartz", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func showPanel() { panelController?.show() }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Kvartz Settings"
            window.minSize = NSSize(width: 560, height: 520)
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(
                rootView: SettingsView(model: AppModel.shared)
                    .frame(minWidth: 560, minHeight: 520)
            )
            settingsWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

extension Notification.Name {
    static let kvartzShortcutChanged = Notification.Name("kvartzShortcutChanged")
    static let kvartzOpenSettings = Notification.Name("kvartzOpenSettings")
}
