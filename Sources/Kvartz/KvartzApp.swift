import AppKit
import SwiftUI

@main
enum KvartzApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        // All windows are managed by AppDelegate. A standalone SwiftUI Settings
        // scene can otherwise become the default window during launch or reopen.
        withExtendedLifetime(delegate) {
            application.run()
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
        NSApp.mainMenu = makeMainMenu()

        panelController = QueryPanelController(model: .shared)
        hotKeyManager = HotKeyManager(shortcut: AppModel.shared.activationShortcut) { [weak self] in
            Task { @MainActor in self?.panelController?.toggle() }
        }
        configureMenuBarItem()

        observers.append(NotificationCenter.default.addObserver(
            forName: .kvartzShortcutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hotKeyManager?.register(AppModel.shared.activationShortcut) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .kvartzShortcutRecordingChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let isRecording = notification.object as? Bool else { return }
            Task { @MainActor in self?.hotKeyManager?.setSuspended(isRecording) }
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

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func makeMainMenu() -> NSMenu {
        // AppKit owns the lifecycle, so supply the standard shortcuts previously
        // installed by SwiftUI, including editing in the query and Settings fields.
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Kvartz")
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Kvartz", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Kvartz", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        return mainMenu
    }

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
            window.isRestorable = false
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
    static let kvartzShortcutRecordingChanged = Notification.Name("kvartzShortcutRecordingChanged")
    static let kvartzOpenSettings = Notification.Name("kvartzOpenSettings")
}
