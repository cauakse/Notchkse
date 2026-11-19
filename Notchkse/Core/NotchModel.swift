import AppKit
import Observation
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, tray, clipboard, ai
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Nook"
        case .tray: "Bandeja"
        case .clipboard: "Clipboard"
        case .ai: "IA"
        }
    }
    var symbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .tray: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .ai: "sparkles"
        }
    }
}

enum NotchMetrics {
    static let expandedWidth: CGFloat = 680
    static let expandedHeight: CGFloat = 236
    /// A janela tem folga para a sombra do notch expandido.
    static let windowWidth: CGFloat = 780
    static let windowHeight: CGFloat = 290

    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 10
    static let openTopRadius: CGFloat = 14
    static let openBottomRadius: CGFloat = 30

    static let peekRowHeight: CGFloat = 30
}

@Observable
final class NotchModel {
    var isExpanded = false
    var isHovering = false
    var tab: NotchTab = .home
    var isDropTargeted = false
    var notchSize = CGSize(width: 200, height: 32)
    var hasHardwareNotch = true
}

/// Animações no estilo "spring" que dão a sensação de sistema.
extension Animation {
    static let notchOpen = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let notchClose = Animation.spring(response: 0.36, dampingFraction: 0.92)
    static let notchPeek = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

enum Theme {
    static let accent = Color(red: 0.545, green: 0.361, blue: 0.965)
    static let accentSoft = Color(red: 0.70, green: 0.60, blue: 1.0)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.55)
}
