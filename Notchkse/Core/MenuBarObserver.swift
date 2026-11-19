import AppKit
import ApplicationServices
import SwiftUI

/// Mede quanto espaço livre existe na barra de menus ao lado do notch:
/// à esquerda até o último menu do app em primeiro plano, à direita até o
/// primeiro ícone de status. Assim o notch não se alarga por cima dos menus.
///
/// Só recalcula quando muda o app ativo, o Space ou a tela (sem polling).
final class MenuBarObserver {
    private let model: NotchModel
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var pendingWork: DispatchWorkItem?
    /// Borda esquerda dos ícones de status (cache; muda só quando apps abrem/fecham).
    private var statusMinX: CGFloat?
    private let statusQueue = DispatchQueue(label: "dev.notchkse.statusitems", qos: .utility)

    init(model: NotchModel) {
        self.model = model
    }

    /// Pede a permissão de Acessibilidade (necessária para ler os menus de outros apps).
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start() {
        guard tokens.isEmpty else { return }
        Self.requestAccess()
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            let token = ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleMeasure() }
            }
            tokens.append((ws, token))
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Ícones novos aparecem um pouco depois do app abrir.
                MainActor.assumeIsolated { self?.refreshStatusItems(after: 1.5) }
            }
            tokens.append((ws, token))
        }
        let nc = NotificationCenter.default
        let token = nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleMeasure() }
        }
        tokens.append((nc, token))
        measure()
        refreshStatusItems(after: 0)
    }

    /// Varre a "barra de extras" de cada app (ícones de status) em segundo plano.
    private func refreshStatusItems(after delay: TimeInterval) {
        guard let screen = NSScreen.builtIn, let primary = NSScreen.screens.first else { return }
        let notchMaxX = screen.frame.midX + screen.notchSize.width / 2
        let barTop = primary.frame.maxY - screen.frame.maxY
        let barHeight = screen.notchSize.height
        let pids = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        statusQueue.asyncAfter(deadline: .now() + delay) {
            let minX = Self.statusItemsMinX(pids: pids, afterX: notchMaxX, barTop: barTop, barHeight: barHeight)
            DispatchQueue.main.async { [weak self] in
                self?.statusMinX = minX
                self?.measure()
            }
        }
    }

    func stop() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens.removeAll()
        model.leftRoom = .infinity
        model.rightRoom = .infinity
    }

    /// O app recém-ativado demora alguns ms para montar a barra de menus.
    private func scheduleMeasure() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.measure() }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func measure() {
        guard let screen = NSScreen.builtIn, let primary = NSScreen.screens.first else { return }
        let notch = screen.notchSize
        let notchMinX = screen.frame.midX - notch.width / 2
        let notchMaxX = screen.frame.midX + notch.width / 2
        // Coordenadas de AX/CGWindow têm origem no topo-esquerdo da tela principal.
        let screenTop = primary.frame.maxY - screen.frame.maxY

        // Menus do app: o macOS coloca os que não cabem à esquerda do notch
        // do lado direito dele (ex.: "Janela", "Ajuda").
        let menus = Self.frontmostMenuFrames(onBarAtY: screenTop, barHeight: notch.height)
        let center = screen.frame.midX
        let leftMenusMaxX = menus.filter { $0.midX < center }.map(\.maxX).max()
        let rightMenusMinX = menus.filter { $0.midX >= center }.map(\.minX).min()

        let left = leftMenusMaxX.map { notchMinX - $0 } ?? .infinity
        let rightEdge = [rightMenusMinX, statusMinX].compactMap { $0 }.min()
        let right = rightEdge.map { $0 - notchMaxX } ?? .infinity
        #if DEBUG
        NSLog("Notchkse: AX=\(AXIsProcessTrusted()) menus=\(menus.count) leftRoom=\(left) rightRoom=\(right)")
        #endif
        guard model.leftRoom != left || model.rightRoom != right else { return }
        // Encolhe/expande com mola ao trocar de app.
        withAnimation(.notchFit) {
            model.leftRoom = left
            model.rightRoom = right
        }
    }

    /// Posição de cada menu (Arquivo, Editar…) do app em primeiro plano.
    private static func frontmostMenuFrames(onBarAtY barTop: CGFloat, barHeight: CGFloat) -> [CGRect] {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else { return [] }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return [] }

        // Ignora o menu da maçã e menus ocultos; só a barra desta tela.
        return children.compactMap(frame(of:)).filter { $0.width > 0 && abs($0.minY - barTop) < barHeight }
    }

    /// Borda esquerda do primeiro ícone de status (relógio, Wi-Fi, apps de menu).
    nonisolated private static func statusItemsMinX(pids: [pid_t], afterX notchMaxX: CGFloat,
                                                    barTop: CGFloat, barHeight: CGFloat) -> CGFloat? {
        guard AXIsProcessTrusted() else { return nil }
        var minX: CGFloat?
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.05)
            var extrasRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
                  let extras = extrasRef else { continue }
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else { continue }
            for child in children {
                guard let f = frame(of: child), f.width > 0, abs(f.minY - barTop) < barHeight,
                      f.minX >= notchMaxX else { continue }
                minX = min(minX ?? f.minX, f.minX)
            }
        }
        return minX
    }

    nonisolated private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}
