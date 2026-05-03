import AppKit
import SwiftUI

/// Owns the lifecycle of the Preferences `NSWindow`. `MenuBarController` calls
/// `present()`; subsequent calls just bring the existing window to the front.
@MainActor
public final class PreferencesWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let model: AppModel
    private let services: AppServices
    private var window: NSWindow?
    private let selection = PreferencesSelection(.general)

    public init(model: AppModel, services: AppServices) {
        self.model = model
        self.services = services
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshToolbarLabels),
            name: .appLanguageChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func refreshToolbarLabels() {
        guard let toolbar = window?.toolbar else { return }
        for item in toolbar.items {
            guard let tab = PreferencesTab(toolbarIdentifier: item.itemIdentifier.rawValue) else { continue }
            item.label = tab.title
            item.paletteLabel = tab.title
        }
    }

    public func present(tab: PreferencesTab? = nil) {
        if let window {
            if let tab {
                selection.tab = tab
                window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.toolbarIdentifier)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let initialTab: PreferencesTab = tab ?? (model.isConfigured ? .general : .printer)
        selection.tab = initialTab

        let view = PreferencesView(model: model, services: services, selection: selection)
        let host = NSHostingController(rootView: view)
        let newWindow = NSWindow(contentViewController: host)
        newWindow.title = "Prusa StatusBar - Preferences"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 560, height: 620))
        newWindow.contentMinSize = NSSize(width: 560, height: 620)
        newWindow.center()
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false

        let toolbar = NSToolbar(identifier: "PreferencesToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        newWindow.toolbarStyle = .preference
        newWindow.toolbar = toolbar
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(initialTab.toolbarIdentifier)

        window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_: Notification) {
        window = nil
    }

    // MARK: - NSToolbarDelegate

    public func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        PreferencesTab.allCases.map { NSToolbarItem.Identifier($0.toolbarIdentifier) }
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        guard let tab = PreferencesTab(toolbarIdentifier: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.image = tab.toolbarImage
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = PreferencesTab(toolbarIdentifier: sender.itemIdentifier.rawValue) else { return }
        selection.tab = tab
    }
}

/// Drives the active tab. Held by the controller and observed by the SwiftUI
/// hosting view so toolbar clicks (AppKit) and view re-renders (SwiftUI) stay
/// in sync.
@MainActor
@Observable
final class PreferencesSelection {
    var tab: PreferencesTab
    init(_ tab: PreferencesTab) {
        self.tab = tab
    }
}

/// Toolbar-driven preferences root. The visible body is swapped based on
/// `selection.tab`; the toolbar lives on the hosting `NSWindow`.
struct PreferencesView: View {
    @Bindable var model: AppModel
    let services: AppServices
    let selection: PreferencesSelection

    var body: some View {
        Group {
            switch selection.tab {
            case .general:
                GeneralTab(model: model, services: services)
            case .menuBar:
                MenuBarTab(model: model, services: services)
            case .menuContent:
                MenuContentTab(model: model, services: services)
            case .printer:
                PrinterTab(model: model, services: services)
            case .about:
                AboutTab()
            }
        }
        .frame(minWidth: 560, minHeight: 620)
        .environment(\.brandAccent, model.accent)
        .environment(\.brandCustomHex, model.customAccentHex)
    }
}

public extension Notification.Name {
    static let appLanguageChanged = Notification.Name("PrusaStatusBar.appLanguageChanged")
}

public enum PreferencesTab: String, Hashable, CaseIterable {
    case general
    case menuBar
    case menuContent
    case printer
    case about

    var toolbarIdentifier: String {
        "PreferencesTab." + rawValue
    }

    init?(toolbarIdentifier: String) {
        let prefix = "PreferencesTab."
        guard toolbarIdentifier.hasPrefix(prefix) else { return nil }
        self.init(rawValue: String(toolbarIdentifier.dropFirst(prefix.count)))
    }

    @MainActor
    var title: String {
        switch self {
        case .general: L10n.t("prefs.tab.general")
        case .menuBar: L10n.t("prefs.tab.menu_bar")
        case .menuContent: L10n.t("prefs.tab.menu_content")
        case .printer: L10n.t("prefs.tab.printer")
        case .about: L10n.t("prefs.tab.about")
        }
    }

    @MainActor
    var toolbarImage: NSImage? {
        switch self {
        case .general:
            NSImage(systemSymbolName: "gearshape", accessibilityDescription: title)
        case .menuBar:
            NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: title)
        case .menuContent:
            NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: title)
        case .printer:
            NSImage(named: "PrinterIcon")
        case .about:
            NSImage(systemSymbolName: "info.circle", accessibilityDescription: title)
        }
    }
}
