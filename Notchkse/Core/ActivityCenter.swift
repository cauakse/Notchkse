import AppKit
import Observation
import SwiftUI

/// Uma "Live Activity" exibida com o notch fechado: ícone à esquerda,
/// valor à direita e, opcionalmente, uma linha de texto abaixo do notch.
struct LiveActivity: Identifiable, Equatable {
    enum Kind { case charging, device, download, downloadDone, screenshot, track, agent }

    let id = UUID()
    var kind: Kind
    var symbol: String? = nil
    var image: NSImage? = nil
    var tint: Color = .white
    var trailingText: String? = nil
    var trailingSymbol: String? = nil
    var progress: Double? = nil
    var title: String? = nil
    var subtitle: String? = nil

    var hasPeekRow: Bool { title != nil }

    static func == (a: LiveActivity, b: LiveActivity) -> Bool {
        a.id == b.id && a.progress == b.progress && a.trailingText == b.trailingText && a.subtitle == b.subtitle
    }
}

@Observable
final class ActivityCenter {
    /// Evento curto (carregador, AirPods, captura…). Some sozinho.
    private(set) var transient: LiveActivity?
    /// Download em andamento: fica enquanto houver download.
    var download: LiveActivity?

    @ObservationIgnored private var clearWork: DispatchWorkItem?

    func flash(_ activity: LiveActivity, duration: TimeInterval = 3.2) {
        clearWork?.cancel()
        withAnimation(.notchPeek) { transient = activity }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.notchPeek) { self?.transient = nil }
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Atualiza a atividade atual sem reiniciar o tempo (ex.: bateria chegou depois).
    func update(id: UUID, _ change: (inout LiveActivity) -> Void) {
        guard var current = transient, current.id == id else { return }
        change(&current)
        transient = current
    }

    func dismiss() {
        clearWork?.cancel()
        withAnimation(.notchPeek) { transient = nil }
    }
}
