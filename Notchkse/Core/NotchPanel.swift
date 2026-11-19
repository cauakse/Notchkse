import AppKit

/// Janela sem borda, transparente, acima da barra de menus e que não rouba o foco.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    // Precisa virar "key" para o campo de texto do prompt de IA receber teclado.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }

    /// Sempre a tela do MacBook (nunca um monitor externo).
    static var builtIn: NSScreen? { screens.first(where: \.isBuiltIn) }

    var hasHardwareNotch: Bool { safeAreaInsets.top > 0 }

    /// Tamanho do notch físico; em Macs sem notch, um notch "virtual".
    var notchSize: CGSize {
        let top = safeAreaInsets.top
        let menuBar = frame.maxY - visibleFrame.maxY
        if top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            // A área segura (32 pt) fica ~1 pt acima do fim do recorte físico;
            // a barra de menus (33 pt) cobre o recorte inteiro.
            return CGSize(width: frame.width - left.width - right.width, height: max(top, menuBar))
        }
        return CGSize(width: 190, height: max(menuBar, 24))
    }
}
