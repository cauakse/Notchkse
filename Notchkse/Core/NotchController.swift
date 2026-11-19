import AppKit
import SwiftUI

/// Posiciona a janela no notch do MacBook e decide quando abrir/fechar.
///
/// Economia: com o notch fechado a janela ignora o mouse (cliques passam
/// direto para a barra de menus). Só observamos a posição do mouse com
/// monitores de evento — nada de timers.
final class NotchController {
    private let context: AppContext
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var screenFrame: NSRect = .zero
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var scrollAccumX: CGFloat = 0
    private var scrollAccumY: CGFloat = 0

    private var model: NotchModel { context.model }

    init(context: AppContext) {
        self.context = context
    }

    func start() {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: NotchMetrics.windowWidth, height: NotchMetrics.windowHeight))
        let hosting = NSHostingView(rootView: NotchRootView().environment(context))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        layout()
        installMonitors()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.orderFrontRegardless() }
        }
    }

    /// Sempre na tela do MacBook. Com a tampa fechada (sem tela interna), esconde.
    private func layout() {
        guard let panel else { return }
        guard let screen = NSScreen.builtIn else {
            panel.orderOut(nil)
            return
        }
        model.notchSize = screen.notchSize
        model.hasHardwareNotch = screen.hasHardwareNotch
        screenFrame = screen.frame
        let w = NotchMetrics.windowWidth, h = NotchMetrics.windowHeight
        panel.setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h), display: true)
        panel.orderFrontRegardless()
    }

    // MARK: Áreas sensíveis

    /// Área do notch fechado (com folga lateral para as live activities).
    private var hotRect: NSRect {
        let size = model.notchSize
        let width = size.width + 2 * 70
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - size.height - 6,
                      width: width, height: size.height + 6)
    }

    /// Só o notch em si (para gestos/clique, sem as laterais).
    private var coreRect: NSRect {
        let size = model.notchSize
        let width = size.width + 24
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - size.height - 4,
                      width: width, height: size.height + 4)
    }

    private var expandedRect: NSRect {
        let w = NotchMetrics.expandedWidth + 2 * NotchMetrics.openTopRadius
        let h = NotchMetrics.expandedHeight
        return NSRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
    }

    // MARK: Eventos

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .scrollWheel]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: false) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: true) }
            return event
        }) { monitors.append(local) }
    }

    private func handle(_ event: NSEvent, local: Bool) {
        let point = NSEvent.mouseLocation
        switch event.type {
        case .mouseMoved:
            mouseMoved(to: point)
        case .leftMouseDown:
            if !local { dragChangeCount = NSPasteboard(name: .drag).changeCount }
            if model.isExpanded, !local, !expandedRect.contains(point) {
                close()
            } else if !model.isExpanded, coreRect.contains(point) {
                open()
            }
        case .leftMouseDragged:
            // Arrastando arquivo até o notch → abre direto na bandeja.
            guard !model.isExpanded, hotRect.contains(point), context.isOn(.tray) || context.isOn(.airdrop) else { return }
            let pb = NSPasteboard(name: .drag)
            guard pb.changeCount != dragChangeCount,
                  pb.types?.contains(.fileURL) == true else { return }
            open(tab: .tray)
        case .scrollWheel:
            handleScroll(event, at: point)
        default:
            break
        }
    }

    private func mouseMoved(to point: NSPoint) {
        if model.isExpanded {
            if expandedRect.insetBy(dx: -10, dy: -10).contains(point) {
                closeWork?.cancel()
                closeWork = nil
            } else if !isPinnedOpen, closeWork == nil {
                let work = DispatchWorkItem { [weak self] in self?.close() }
                closeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
            }
            return
        }

        let inside = hotRect.contains(point) && coreRectOrActivity(contains: point)
        if inside != model.isHovering {
            withAnimation(.notchPeek) { model.isHovering = inside }
        }
        if inside, context.settings.hoverToOpen {
            guard openWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.openWork = nil
                if self.hotRect.contains(NSEvent.mouseLocation) { self.open() }
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + context.settings.hoverDelay, execute: work)
        } else {
            openWork?.cancel()
            openWork = nil
        }
    }

    /// Fora de live activity, só o notch físico conta como área de hover.
    private func coreRectOrActivity(contains point: NSPoint) -> Bool {
        let hasActivity = ClosedView.activeActivity(context) != nil || ClosedView.showsMedia(context)
        return hasActivity || coreRect.contains(point)
    }

    /// Gestos no trackpad: deslizar para baixo abre, para cima fecha,
    /// para os lados (no notch fechado) troca de música.
    private func handleScroll(_ event: NSEvent, at point: NSPoint) {
        if event.phase == .began { scrollAccumX = 0; scrollAccumY = 0 }
        guard event.phase == .changed || event.phase == .began else { return }
        let natural = event.isDirectionInvertedFromDevice
        let fingersDown = natural ? event.scrollingDeltaY : -event.scrollingDeltaY
        let fingersRight = natural ? event.scrollingDeltaX : -event.scrollingDeltaX
        scrollAccumY += fingersDown
        scrollAccumX += fingersRight

        if !model.isExpanded, hotRect.contains(point) {
            if scrollAccumY > 14 {
                scrollAccumY = -1000
                open()
            } else if abs(scrollAccumX) > 40, context.media.hasTrack, context.isOn(.media) {
                scrollAccumX > 0 ? context.media.previous() : context.media.next()
                Haptics.tap(enabled: context.settings.haptics)
                scrollAccumX = 0
                scrollAccumY = -1000
            }
        } else if model.isExpanded, coreRect.contains(point), scrollAccumY < -18 {
            scrollAccumY = 1000
            close()
        }
    }

    /// Não fecha sozinho enquanto o usuário está digitando no prompt de IA.
    private var isPinnedOpen: Bool {
        (panel?.isKeyWindow ?? false) && model.tab == .ai
    }

    // MARK: Abrir / fechar

    func open(tab: NotchTab? = nil) {
        openWork?.cancel(); openWork = nil
        closeWork?.cancel(); closeWork = nil
        let tabs = context.visibleTabs
        guard !tabs.isEmpty else { return }
        if let tab, tabs.contains(tab) { model.tab = tab }
        if !tabs.contains(model.tab) { model.tab = tabs[0] }
        guard !model.isExpanded else { return }

        panel?.ignoresMouseEvents = false
        context.activities.dismiss()
        if context.isOn(.calendar) { context.calendar.reload() }
        Haptics.tap(enabled: context.settings.haptics)
        withAnimation(.notchOpen) {
            model.isHovering = false
            model.isExpanded = true
        }
    }

    func close() {
        openWork?.cancel(); openWork = nil
        closeWork?.cancel(); closeWork = nil
        guard model.isExpanded else { return }
        withAnimation(.notchClose) {
            model.isExpanded = false
            model.isDropTargeted = false
        }
        panel?.ignoresMouseEvents = true
        // Devolve o teclado para o app que estava em uso.
        if let panel, panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }
}
