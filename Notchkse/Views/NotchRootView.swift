import SwiftUI

struct NotchRootView: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        let model = ctx.model
        let size = currentSize
        let topRadius = model.isExpanded ? NotchMetrics.openTopRadius : NotchMetrics.closedTopRadius
        let bottomRadius = model.isExpanded ? NotchMetrics.openBottomRadius : NotchMetrics.closedBottomRadius
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)

        let glass = model.isExpanded && ctx.settings.glassBackground

        ZStack(alignment: .top) {
            // Sombra separada do vidro (senão ela "suja" o blur).
            shape
                .fill(Color.black.opacity(model.isExpanded ? 0.01 : 0))
                .shadow(color: .black.opacity(model.isExpanded ? 0.55 : 0), radius: 18, y: 10)

            // Fechado: preto sólido (se funde com o notch físico).
            // Aberto com vidro: blur do que está atrás + camada preta ajustável.
            shape.fill(Color.black.opacity(glass ? ctx.settings.glassDarkness : 1))
                .animation(.easeInOut(duration: 0.25), value: glass)
                .animation(.easeInOut(duration: 0.2), value: ctx.settings.glassDarkness)

            Group {
                if model.isExpanded {
                    ExpandedView()
                        .padding(.horizontal, topRadius)
                        .transition(.notchContent)
                } else {
                    ClosedView(notchWidth: model.notchSize.width, height: model.notchSize.height)
                        .padding(.horizontal, topRadius)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
                                                removal: .opacity.animation(.easeOut(duration: 0.08))))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(model.isDropTargeted ? 1.02 : 1, anchor: .top)
        .frame(width: NotchMetrics.windowWidth, height: NotchMetrics.windowHeight, alignment: .top)
        .background(alignment: .top) {
            // O blur tem tamanho fixo (a janela toda) e é recortado pelo formato
            // animado do notch: assim os dois crescem juntos, quadro a quadro.
            if glass {
                VisualEffectBlur()
                    .frame(width: NotchMetrics.windowWidth, height: NotchMetrics.windowHeight)
                    .mask(alignment: .top) {
                        shape.frame(width: size.width, height: size.height)
                            .scaleEffect(model.isDropTargeted ? 1.02 : 1, anchor: .top)
                    }
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// Tamanho do "corpo" preto em cada estado.
    private var currentSize: CGSize { Self.bodySize(ctx) }

    /// Tamanho do corpo preto (usado também pelo sensor de mouse do controlador).
    static func bodySize(_ ctx: AppContext) -> CGSize {
        let model = ctx.model
        let notch = model.notchSize
        if model.isExpanded {
            return CGSize(width: NotchMetrics.expandedWidth + 2 * NotchMetrics.openTopRadius,
                          height: NotchMetrics.expandedHeight)
        }
        let base = notch.width + 2 * NotchMetrics.closedTopRadius
        if let activity = ClosedView.activeActivity(ctx) {
            let side = ClosedView.side(for: activity, ctx)
            let extraHeight = activity.hasPeekRow ? NotchMetrics.peekRowHeight : 0
            return CGSize(width: base + 2 * side, height: notch.height + extraHeight)
        }
        let strip: CGFloat = ClosedView.downloadStrip(ctx) != nil ? ClosedView.stripHeight : 0
        if let side = ClosedView.mediaSide(ctx) {
            return CGSize(width: base + 2 * side, height: notch.height + strip)
        }
        if strip > 0 {
            return CGSize(width: base, height: notch.height + strip)
        }
        if model.isHovering {
            return CGSize(width: base + 18, height: notch.height + 4)
        }
        return CGSize(width: base, height: notch.height)
    }
}

// MARK: - Notch fechado (live activities)

struct ClosedView: View {
    @Environment(AppContext.self) private var ctx
    let notchWidth: CGFloat
    let height: CGFloat

    /// Largura ideal de cada lado para música/download.
    static let fullSide: CGFloat = 34
    /// Música pausada: cabe ⏮ ⏯ ⏭ do lado direito.
    static let pausedSide: CGFloat = 72
    /// Abaixo disso não cabe nem o ponto: some.
    static let minSide: CGFloat = 4

    /// Largura ideal de cada lado que a atividade ocupa no notch fechado.
    static func idealSide(_ a: LiveActivity) -> CGFloat {
        a.hasPeekRow ? 90 : (a.trailingText != nil ? 46 : fullSide)
    }

    /// Persistentes (download, música) se encaixam no espaço livre entre os
    /// menus do app e o notch. Avisos rápidos usam a largura ideal (somem logo).
    static func side(for a: LiveActivity, _ ctx: AppContext) -> CGFloat {
        a.kind == .download ? min(fullSide, ctx.model.sideRoom) : idealSide(a)
    }

    static func activeActivity(_ ctx: AppContext) -> LiveActivity? {
        if let transient = ctx.activities.transient { return transient }
        // Download nas laterais só sem música e com espaço; senão vira barrinha.
        if let download = ctx.activities.download, ctx.model.sideRoom >= fullSide, mediaSide(ctx) == nil {
            return download
        }
        return nil
    }

    /// Altura extra da barrinha de download embaixo do notch encolhido.
    static let stripHeight: CGFloat = 5

    /// Progresso do download como barrinha fina embaixo do notch quando a
    /// música ocupa as laterais ou quando o notch está encolhido.
    static func downloadStrip(_ ctx: AppContext) -> Double? {
        guard ctx.activities.transient == nil, let download = ctx.activities.download,
              ctx.model.sideRoom < fullSide || mediaSide(ctx) != nil else { return nil }
        return download.progress ?? 0
    }

    /// Largura de cada lado para a música, ou nil se não deve aparecer.
    static func mediaSide(_ ctx: AppContext) -> CGFloat? {
        guard ctx.isOn(.media), ctx.settings.mediaLiveActivity, ctx.media.hasTrack,
              ctx.model.sideRoom >= minSide else { return nil }
        return min(ctx.media.isPlaying ? fullSide : pausedSide, ctx.model.sideRoom)
    }

    static func showsMedia(_ ctx: AppContext) -> Bool { mediaSide(ctx) != nil }

    var body: some View {
        if let activity = Self.activeActivity(ctx) {
            VStack(spacing: 0) {
                row(side: Self.side(for: activity, ctx), leading: leading(activity, side: Self.side(for: activity, ctx)),
                    trailing: trailing(activity, side: Self.side(for: activity, ctx)))
                if let title = activity.title {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        if let subtitle = activity.subtitle {
                            Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: NotchMetrics.peekRowHeight - 4)
                    .transition(.opacity)
                }
            }
            .id(activity.id)
            .transition(.blurReplace)
        } else {
            VStack(spacing: 0) {
                if let side = Self.mediaSide(ctx) {
                    mediaRow(side: side)
                        .transition(.blurReplace)
                } else {
                    Color.clear.frame(height: height)
                }
                if let progress = Self.downloadStrip(ctx) {
                    DownloadStrip(progress: progress)
                        .padding(.horizontal, NotchMetrics.closedBottomRadius + 4)
                        .frame(height: Self.stripHeight)
                        .transition(.opacity)
                }
            }
        }
    }

    /// Margem interna proporcional: lados estreitos ficam com pouca margem.
    private func padding(for side: CGFloat) -> CGFloat { min(10, max(1, side * 0.28)) }

    private func row(side: CGFloat, leading: AnyView, trailing: AnyView) -> some View {
        let pad = padding(for: side)
        return HStack(spacing: 0) {
            leading.frame(width: max(0, side - pad), alignment: .center)
            Color.clear.frame(width: notchWidth)
            trailing.frame(width: max(0, side - pad), alignment: .center)
        }
        .padding(.horizontal, pad)
        .frame(height: height)
    }

    /// Música no notch fechado, em três tamanhos conforme o espaço:
    /// completo (capa + 4 barras), compacto (capa menor + 2 barras), mínimo (pontos).
    private func mediaRow(side: CGFloat) -> some View {
        let media = ctx.media
        let usable = side - padding(for: side)
        let leading: AnyView
        let trailing: AnyView
        // Modo muda o "id" → o conteúdo troca com blur enquanto o notch anima.
        var mode = usable >= 20 ? "full" : (usable >= 12 ? "compact" : "dot")
        if !media.isPlaying {
            // Pausada: capa (ou nada) à esquerda, controles à direita conforme o espaço.
            mode = usable >= 54 ? "paused3" : (usable >= 14 ? "paused1" : "pausedDot")
            leading = usable >= 12
                ? AnyView(artwork(media.artwork, size: min(height - 12, usable)).opacity(0.7))
                : AnyView(EmptyView())
            trailing = AnyView(PausedControls(full: usable >= 54, compact: usable < 14))
        } else if usable >= 12 {
            leading = AnyView(artwork(media.artwork, size: min(height - 12, usable)))
            trailing = AnyView(AudioBars(playing: media.isPlaying, color: media.accent, count: usable >= 20 ? 4 : 2))
        } else {
            leading = AnyView(PulseDot(size: min(6, usable)))
            trailing = AnyView(PulseDot(size: min(6, usable), delay: 0.35))
        }
        return row(side: side,
                   leading: AnyView(leading.id("L" + mode).transition(.blurReplace.combined(with: .scale(0.6)))),
                   trailing: AnyView(trailing.id("R" + mode).transition(.blurReplace.combined(with: .scale(0.6)))))
    }

    private func leading(_ a: LiveActivity, side: CGFloat) -> AnyView {
        if a.kind == .download, side - padding(for: side) < 12 {
            return AnyView(PulseDot(size: min(6, side - padding(for: side))))
        }
        if let image = a.image {
            return AnyView(artwork(image, size: height - 12))
        }
        return AnyView(Image(systemName: a.symbol ?? "circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(a.tint)
            .symbolEffect(.bounce, value: a.id))
    }

    private func trailing(_ a: LiveActivity, side: CGFloat) -> AnyView {
        if a.kind == .download {
            let ring = min(16, max(5, side - padding(for: side)))
            return AnyView(ProgressRing(progress: a.progress ?? 0, color: a.tint, lineWidth: ring < 10 ? 1.5 : 2.5)
                .frame(width: ring, height: ring))
        }
        if let text = a.trailingText {
            return AnyView(Text(text).font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText()))
        }
        if let symbol = a.trailingSymbol {
            if a.kind == .track {
                return AnyView(AudioBars(playing: true, color: a.tint))
            }
            return AnyView(Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText))
        }
        return AnyView(EmptyView())
    }

    private func artwork(_ image: NSImage?, size: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - Componentes

/// Desfoque nativo do macOS (o mesmo material dos HUDs do sistema).
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Barrinha fina de progresso do download (notch encolhido).
struct DownloadStrip: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white)
                    .frame(width: max(2, geo.size.width * min(max(progress, 0), 1)))
            }
            .frame(height: 2)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Controles da música pausada no notch fechado.
struct PausedControls: View {
    @Environment(AppContext.self) private var ctx
    var full: Bool
    var compact: Bool

    var body: some View {
        let media = ctx.media
        HStack(spacing: 2) {
            if full {
                button("backward.fill", size: 10, action: media.previous)
            }
            button("play.fill", size: compact ? 8 : 12, action: media.togglePlay)
            if full {
                button("forward.fill", size: 10, action: media.next)
            }
        }
    }

    private func button(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: compact ? 10 : 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle(size: compact ? 10 : 18))
    }
}

/// Ponto que pulsa suavemente (modo mínimo quando quase não há espaço).
/// Animado pelo Core Animation: roda no servidor de janelas, ~0% de CPU no app.
struct PulseDot: NSViewRepresentable {
    var size: CGFloat
    var delay: Double = 0

    func makeNSView(context: Context) -> PulseDotView { PulseDotView() }
    func updateNSView(_ view: PulseDotView, context: Context) { view.configure(size: max(3, size), delay: delay) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PulseDotView, context: Context) -> CGSize? {
        CGSize(width: max(3, size), height: max(3, size))
    }
}

final class PulseDotView: NSView {
    private let dot = CALayer()
    private var configured: (CGFloat, Double)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dot.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(dot)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(size: CGFloat, delay: Double) {
        guard configured.map({ $0 != (size, delay) }) ?? true else { return }
        configured = (size, delay)
        dot.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        dot.cornerRadius = size / 2
        needsLayout = true

        let pulse = CAAnimationGroup()
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.35; opacity.toValue = 1
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.7; scale.toValue = 1
        pulse.animations = [opacity, scale]
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.beginTime = CACurrentMediaTime() + delay
        dot.add(pulse, forKey: "pulse")
    }

    override func layout() {
        super.layout()
        dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

/// Visualizador de áudio. As barras são animadas pelo Core Animation
/// (o app só configura uma vez; quem anima é o servidor de janelas).
struct AudioBars: NSViewRepresentable {
    var playing: Bool
    var color: Color
    var count: Int = 4

    func makeNSView(context: Context) -> AudioBarsView { AudioBarsView() }
    func updateNSView(_ view: AudioBarsView, context: Context) {
        view.configure(count: count, color: NSColor(color), playing: playing)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AudioBarsView, context: Context) -> CGSize? {
        CGSize(width: CGFloat(count) * 3 + CGFloat(max(0, count - 1)) * 2, height: 14)
    }
}

final class AudioBarsView: NSView {
    private var bars: [CALayer] = []
    private var state: (Int, NSColor, Bool)?
    private static let durations: [CFTimeInterval] = [0.42, 0.57, 0.36, 0.5]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(count: Int, color: NSColor, playing: Bool) {
        if let state, state.0 == count, state.1 == color, state.2 == playing { return }
        state = (count, color, playing)
        if bars.count != count {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in
                let bar = CALayer()
                bar.cornerRadius = 1.5
                layer?.addSublayer(bar)
                return bar
            }
            needsLayout = true
        }
        for (i, bar) in bars.enumerated() {
            bar.backgroundColor = color.cgColor
            bar.removeAnimation(forKey: "bounce")
            if playing {
                let anim = CABasicAnimation(keyPath: "transform.scale.y")
                anim.fromValue = 0.28
                anim.toValue = 1
                anim.duration = Self.durations[i % Self.durations.count]
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                anim.beginTime = CACurrentMediaTime() + Double(i) * 0.11
                bar.add(anim, forKey: "bounce")
                bar.transform = CATransform3DIdentity
            } else {
                bar.transform = CATransform3DMakeScale(1, 0.22, 1)
            }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let height = min(bounds.height, 14)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: height)
            bar.position = CGPoint(x: CGFloat(i) * 5 + 1.5, y: bounds.midY)
        }
        CATransaction.commit()
    }
}

struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.03, progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)
        }
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardStroke))
    }
}

extension View {
    func card(padding: CGFloat = 12) -> some View { modifier(CardBackground(padding: padding)) }
}

struct HoverButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, size: size)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false
        var body: some View {
            configuration.label
                .frame(minWidth: size, minHeight: size)
                .background(Color.white.opacity(hovering ? 0.12 : 0), in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .contentShape(Capsule())
        }
    }
}
