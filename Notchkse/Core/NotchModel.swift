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
    static let expandedWidth: CGFloat = 720
    static let expandedHeight: CGFloat = 236
    /// A janela tem folga para a sombra do notch expandido.
    static let windowWidth: CGFloat = 820
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
    /// Abertura com leve "quique" no final (o formato passa um pouco e volta).
    static let notchOpen = Animation.spring(response: 0.5, dampingFraction: 0.68)
    /// Fechamento firme e rápido, com um assentamento sutil.
    static let notchClose = Animation.spring(response: 0.36, dampingFraction: 0.8)
    static let notchPeek = Animation.spring(response: 0.4, dampingFraction: 0.72)
    /// Entrada em cascata do conteúdo.
    static func notchStagger(_ index: Int) -> Animation {
        .spring(response: 0.48, dampingFraction: 0.74).delay(0.07 + Double(index) * 0.045)
    }
}

/// Conteúdo surge desfocado, menor e um pouco acima, e "assenta" no lugar.
struct BlurFade: ViewModifier {
    var progress: Double  // 0 = escondido, 1 = visível
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 10)
            .scaleEffect(0.9 + 0.1 * progress, anchor: .top)
            .offset(y: (1 - progress) * -10)
    }
}

struct StaggerIn: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .modifier(BlurFade(progress: shown ? 1 : 0))
            .onAppear { withAnimation(.notchStagger(index)) { shown = true } }
    }
}

extension View {
    func staggerIn(_ index: Int) -> some View { modifier(StaggerIn(index: index)) }
}

extension AnyTransition {
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.15)),
            removal: .modifier(active: BlurFade(progress: 0), identity: BlurFade(progress: 1))
                .animation(.easeIn(duration: 0.14)))
    }
}

enum Theme {
    // Monocromático: só preto e branco.
    static let accent = Color.white
    static let accentSoft = Color.white.opacity(0.92)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.55)
}
