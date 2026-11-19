import AppKit
import Observation
import SwiftUI

/// Posiciona a janela no notch do MacBook e decide quando abrir/fechar.
///
/// Economia de CPU: com o notch fechado NÃO existe monitor global de mouse.
/// Uma janelinha invisível ("sensor") cobre só a área do notch e o macOS só
/// avisa quando o mouse entra/sai dela. Monitores globais existem apenas
/// enquanto o notch está aberto (para detectar saída e clique fora).
final class NotchController {
    private let context: AppContext
    private var panel: NotchPanel?
    private var sensor: SensorPanel?
    private var expandedMonitors: [Any] = []
    private var localMonitor: Any?
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var screenFrame: NSRect = .zero
    private var scrollAccumX: CGFloat = 0
    private var scrollAccumY: CGFloat = 0
    private var overControls = false

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

        let sensor = SensorPanel()
        sensor.sensorView.controller = self
        self.sensor = sensor

        layout()
        installLocalMonitor()
        trackClosedSize()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel?.orderFrontRegardless()
                if self?.model.isExpanded == false { self?.sensor?.orderFrontRegardless() }
            }
        }
    }

    /// Sempre na tela do MacBook. Com a tampa fechada (sem tela interna), esconde.
    private func layout() {
        guard let panel else { return }
        guard let screen = NSScreen.builtIn else {
            panel.orderOut(nil)
            sensor?.orderOut(nil)
            return
        }
        model.notchSize = screen.notchSize
        model.hasHardwareNotch = screen.hasHardwareNotch
        screenFrame = screen.frame
        let w = NotchMetrics.windowWidth, h = NotchMetrics.windowHeight
        panel.setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h), display: true)
        panel.orderFrontRegardless()
        updateSensorFrame()
    }

    // MARK: Sensor (notch fechado)

    /// Reposiciona o sensor sempre que o tamanho do notch fechado muda
    /// (música, download, encaixe nos menus…). Observação, não polling.
    private func trackClosedSize() {
        withObservationTracking {
            _ = NotchRootView.bodySize(context)
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateSensorFrame()
                self?.trackClosedSize()
            }
        }
    }

    private func updateSensorFrame() {
        guard let sensor, !screenFrame.isEmpty else { return }
        guard !model.isExpanded else { sensor.orderOut(nil); return }
        let body = NotchRootView.bodySize(context)
        let notch = model.notchSize
        let width = max(body.width, notch.width + 24)
        let height = max(body.height, notch.height) + 2
        let frame = NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
        if sensor.frame != frame { sensor.setFrame(frame, display: false) }
        if !sensor.isVisible { sensor.orderFrontRegardless() }
    }

    func sensorEntered() {
        guard !model.isExpanded else { return }
        withAnimation(.notchPeek) { model.isHovering = true }
        scheduleOpen()
    }

    func sensorExited() {
        openWork?.cancel(); openWork = nil
        if model.isHovering { withAnimation(.notchPeek) { model.isHovering = false } }
    }

    /// Só chega enquanto o mouse está DENTRO do sensor (barato).
    func sensorMoved(to point: NSPoint) {
        let inControls = controlsRect?.contains(point) ?? false
        guard inControls != overControls else { return }
        overControls = inControls
        if inControls {
            // Entrega o mouse para a janela do notch: os botões ⏮ ⏯ ⏭ ficam clicáveis.
            openWork?.cancel(); openWork = nil
            if model.isHovering { withAnimation(.notchPeek) { model.isHovering = false } }
            sensor?.ignoresMouseEvents = true
            panel?.ignoresMouseEvents = false
        } else {
            scheduleOpen()
        }
    }

    func sensorClicked() { open() }
    func sensorScrolled(_ event: NSEvent) { handleScroll(event) }
    func sensorDragEntered() {
        guard context.isOn(.tray) || context.isOn(.airdrop) else { return }
        open(tab: .tray)
    }

    private func scheduleOpen() {
        guard context.settings.hoverToOpen, openWork == nil, !model.isExpanded else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.openWork = nil
            if self.model.isHovering { self.open() }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + context.settings.hoverDelay, execute: work)
    }

    /// Área dos controles da música pausada, à direita do notch.
    private var controlsRect: NSRect? {
        guard !model.isExpanded, ClosedView.activeActivity(context) == nil,
              !context.media.isPlaying, let side = ClosedView.mediaSide(context) else { return nil }
        let size = model.notchSize
        return NSRect(x: screenFrame.midX + size.width / 2, y: screenFrame.maxY - size.height,
                      width: side + NotchMetrics.closedTopRadius, height: size.height)
    }

    // MARK: Monitores

    /// Monitor local: só recebe eventos das NOSSAS janelas (custo desprezível).
    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .scrollWheel, self.model.isExpanded {
                    self.handleScroll(event)
                } else if event.type == .mouseMoved {
                    self.mouseMovedLocally(NSEvent.mouseLocation)
                }
            }
            return event
        }
    }

    private func mouseMovedLocally(_ point: NSPoint) {
        if model.isExpanded {
            expandedMouseMoved(point)
        } else if overControls, !(controlsRect?.contains(point) ?? false) {
            // Saiu dos controles: o sensor volta a cuidar do mouse.
            overControls = false
            panel?.ignoresMouseEvents = true
            sensor?.ignoresMouseEvents = false
        }
    }

    /// Monitores globais apenas com o notch aberto.
    private func installExpandedMonitors() {
        guard expandedMonitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let point = NSEvent.mouseLocation
                if event.type == .leftMouseDown {
                    if !self.expandedRect.contains(point) { self.close() }
                } else {
                    self.expandedMouseMoved(point)
                }
            }
        }) { expandedMonitors.append(m) }
    }

    private func removeExpandedMonitors() {
        expandedMonitors.forEach(NSEvent.removeMonitor)
        expandedMonitors.removeAll()
    }

    private var expandedRect: NSRect {
        let w = NotchMetrics.expandedWidth + 2 * NotchMetrics.openTopRadius
        let h = NotchMetrics.expandedHeight
        return NSRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
    }

    private var coreRect: NSRect {
        let size = model.notchSize
        let width = size.width + 24
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - size.height - 4,
                      width: width, height: size.height + 4)
    }

    private func expandedMouseMoved(_ point: NSPoint) {
        if expandedRect.insetBy(dx: -10, dy: -10).contains(point) {
            closeWork?.cancel()
            closeWork = nil
        } else if !isPinnedOpen, closeWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.close() }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        }
    }

    /// Gestos no trackpad: deslizar para baixo abre, para cima fecha,
    /// para os lados (no notch fechado) troca de música.
    private func handleScroll(_ event: NSEvent) {
        if event.phase == .began { scrollAccumX = 0; scrollAccumY = 0 }
        guard event.phase == .changed || event.phase == .began else { return }
        let natural = event.isDirectionInvertedFromDevice
        scrollAccumY += natural ? event.scrollingDeltaY : -event.scrollingDeltaY
        scrollAccumX += natural ? event.scrollingDeltaX : -event.scrollingDeltaX

        if !model.isExpanded {
            if scrollAccumY > 14 {
                scrollAccumY = -1000
                open()
            } else if abs(scrollAccumX) > 40, context.media.hasTrack, context.isOn(.media) {
                scrollAccumX > 0 ? context.media.previous() : context.media.next()
                Haptics.tap(enabled: context.settings.haptics)
                scrollAccumX = 0
                scrollAccumY = -1000
            }
        } else if coreRect.contains(NSEvent.mouseLocation), scrollAccumY < -18 {
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

        overControls = false
        panel?.ignoresMouseEvents = false
        sensor?.orderOut(nil)
        installExpandedMonitors()
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
        removeExpandedMonitors()
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
        sensor?.ignoresMouseEvents = false
        updateSensorFrame()
    }
}

// MARK: - Sensor

/// Janela praticamente invisível sobre o notch que só recebe o mouse
/// quando ele está em cima do notch (entrar/sair/clicar/rolar/arrastar).
final class SensorPanel: NSPanel {
    let sensorView = SensorView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Alfa mínimo: janelas 100% transparentes não recebem eventos de mouse.
        backgroundColor = NSColor.black.withAlphaComponent(0.004)
        isOpaque = false
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        contentView = sensorView
        sensorView.registerForDraggedTypes([.fileURL])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SensorView: NSView {
    weak var controller: NotchController?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { controller?.sensorEntered() }
    override func mouseExited(with event: NSEvent) { controller?.sensorExited() }
    override func mouseMoved(with event: NSEvent) { controller?.sensorMoved(to: NSEvent.mouseLocation) }
    override func mouseDown(with event: NSEvent) { controller?.sensorClicked() }
    override func scrollWheel(with event: NSEvent) { controller?.sensorScrolled(event) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.sensorDragEntered()
        return .copy
    }
}
