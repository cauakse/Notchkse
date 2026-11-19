import AppKit
import Observation
import SwiftUI

/// Tudo que as views precisam, injetado via `.environment(context)`.
@Observable
final class AppContext {
    let settings = AppSettings()
    let model = NotchModel()
    let activities = ActivityCenter()
    let media = MediaController()
    let lyrics = LyricsService()
    let tray = TrayStore()
    let clipboard = ClipboardMonitor()
    let agent = AgentRunner()
    let battery = BatteryMonitor()
    let downloads = DownloadsMonitor()
    let calendar = CalendarService()
    let shortcuts = ShortcutsService()
    let stats = SystemStats()
    @ObservationIgnored let bluetooth = BluetoothMonitor()
    @ObservationIgnored let screenshots = ScreenshotMonitor()

    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var closeNotch: () -> Void = {}

    func isOn(_ module: ModuleID) -> Bool { settings.isOn(module) }

    var visibleTabs: [NotchTab] {
        var tabs: [NotchTab] = []
        if [.media, .calendar, .mirror, .shortcuts].contains(where: isOn) { tabs.append(.home) }
        if [.tray, .airdrop, .screenshots].contains(where: isOn) { tabs.append(.tray) }
        if isOn(.clipboard) { tabs.append(.clipboard) }
        if isOn(.ai) { tabs.append(.ai) }
        return tabs
    }
}

final class AppCoordinator {
    let context = AppContext()
    private var notch: NotchController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func start() {
        let ctx = context
        ctx.openSettings = { [weak self] in self?.openSettings() }
        wireEvents()
        applyModules()
        ctx.settings.onModulesChanged = { [weak self] in self?.applyModules() }
        ctx.settings.onAppearanceChanged = { [weak self] in self?.updateStatusItem() }

        let notch = NotchController(context: ctx)
        notch.start()
        ctx.closeNotch = { [weak notch] in notch?.close() }
        self.notch = notch
        updateStatusItem()
    }

    // MARK: Módulos

    /// Liga/desliga serviços conforme os ajustes. Módulo desligado = zero custo.
    private func applyModules() {
        let c = context
        toggle(c.isOn(.media), c.media.start, c.media.stop)
        if !c.isOn(.lyrics) || !c.isOn(.media) { c.lyrics.reset() } else { loadLyricsIfNeeded() }
        toggle(c.isOn(.clipboard), c.clipboard.start, c.clipboard.stop)
        toggle(c.isOn(.battery), c.battery.start, c.battery.stop)
        toggle(c.isOn(.bluetooth), c.bluetooth.start, c.bluetooth.stop)
        toggle(c.isOn(.downloads), c.downloads.start, c.downloads.stop)
        toggle(c.isOn(.screenshots), c.screenshots.start, c.screenshots.stop)
        toggle(c.isOn(.calendar), c.calendar.start, c.calendar.stop)
        if c.isOn(.ai) { c.agent.detect() }
        if !c.visibleTabs.contains(c.model.tab), let first = c.visibleTabs.first { c.model.tab = first }
    }

    private func toggle(_ on: Bool, _ start: () -> Void, _ stop: () -> Void) {
        if on { start() } else { stop() }
    }

    private func loadLyricsIfNeeded() {
        let m = context.media
        guard context.isOn(.lyrics), m.hasTrack else { return }
        context.lyrics.load(key: m.trackKey, title: m.title, artist: m.artist, album: m.album, duration: m.duration)
    }

    private func wireEvents() {
        let c = context

        c.media.onTrackChange = { [weak self] in
            guard let self else { return }
            let m = c.media
            if !m.hasTrack { c.lyrics.reset(); return }
            self.loadLyricsIfNeeded()
            if c.settings.mediaLiveActivity, !c.model.isExpanded, m.isPlaying {
                c.activities.flash(LiveActivity(kind: .track, image: m.artwork, tint: m.accent,
                                                trailingSymbol: "waveform",
                                                title: m.title, subtitle: m.artist), duration: 2.8)
            }
        }

        c.battery.onPowerConnected = { level in
            guard c.isOn(.battery) else { return }
            c.activities.flash(LiveActivity(kind: .charging, symbol: "bolt.fill", tint: .white,
                                            trailingText: "\(level)%", trailingSymbol: nil))
        }

        var deviceActivityID: UUID?
        c.bluetooth.onConnect = { device in
            let activity = LiveActivity(kind: .device, symbol: device.symbol, tint: .white,
                                        trailingSymbol: "checkmark.circle.fill",
                                        title: device.name, subtitle: "Conectado")
            deviceActivityID = activity.id
            c.activities.flash(activity, duration: 5)
        }
        c.bluetooth.onBattery = { device in
            guard let id = deviceActivityID else { return }
            c.activities.update(id: id) {
                $0.trailingText = device.shortBattery
                $0.trailingSymbol = nil
                $0.subtitle = device.battery
            }
        }

        c.downloads.onChange = { list in
            guard let first = list.first else {
                withAnimation(.notchPeek) { c.activities.download = nil }
                return
            }
            let progress = list.compactMap(\.progress).min()
            let value = LiveActivity(kind: .download, symbol: "arrow.down.circle.fill", tint: Theme.accentSoft,
                                     progress: progress ?? 0)
            withAnimation(.notchPeek) {
                c.activities.download = value
            }
            _ = first
        }
        c.downloads.onFinished = { url in
            if c.settings.addDownloadsToTray, c.isOn(.tray) { c.tray.add([url]) }
            c.activities.flash(LiveActivity(kind: .downloadDone, symbol: "checkmark.circle.fill", tint: .white,
                                            trailingSymbol: "arrow.down.doc",
                                            title: url.lastPathComponent, subtitle: "Download concluído"))
        }

        c.screenshots.onNew = { url in
            c.tray.add([url], screenshot: true)
            let thumb = ImageUtils.thumbnail(url: url, maxPixel: 120)
            c.activities.flash(LiveActivity(kind: .screenshot, image: thumb, trailingSymbol: "tray.and.arrow.down.fill",
                                            title: "Captura na bandeja", subtitle: url.lastPathComponent))
        }

        c.agent.onFinish = { agent in
            guard !c.model.isExpanded else { return }
            c.activities.flash(LiveActivity(kind: .agent, symbol: "sparkles", tint: Theme.accentSoft,
                                            trailingSymbol: "checkmark",
                                            title: "\(agent.name) respondeu", subtitle: "Abra o notch para ver"), duration: 4)
        }
    }

    // MARK: Barra de menus e ajustes

    private func updateStatusItem() {
        if context.settings.showMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                         accessibilityDescription: "Notchkse")
            let menu = NSMenu()
            menu.addItem(withTitle: "Ajustes do Notchkse…", action: #selector(StatusTarget.openSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Sair do Notchkse", action: #selector(StatusTarget.quit), keyEquivalent: "q")
            StatusTarget.shared.coordinator = self
            menu.items.forEach { $0.target = StatusTarget.shared }
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func openSettings() {
        notch?.close()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Ajustes do Notchkse"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView().environment(context))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

final class StatusTarget: NSObject {
    static let shared = StatusTarget()
    weak var coordinator: AppCoordinator?

    @objc func openSettings() { coordinator?.openSettings() }
    @objc func quit() { NSApp.terminate(nil) }
}
