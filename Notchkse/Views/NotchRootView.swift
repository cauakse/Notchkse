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
    private var currentSize: CGSize {
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
        if let side = ClosedView.mediaSide(ctx) {
            return CGSize(width: base + 2 * side, height: notch.height)
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
        if let download = ctx.activities.download, ctx.model.sideRoom >= minSide { return download }
        return nil
    }

    /// Largura de cada lado para a música, ou nil se não deve aparecer.
    static func mediaSide(_ ctx: AppContext) -> CGFloat? {
        guard ctx.isOn(.media), ctx.settings.mediaLiveActivity, ctx.media.hasTrack, ctx.media.isPlaying,
              ctx.model.sideRoom >= minSide else { return nil }
        return min(fullSide, ctx.model.sideRoom)
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
        } else if let side = Self.mediaSide(ctx) {
            mediaRow(side: side)
                .transition(.blurReplace)
        } else {
            Color.clear
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
        let mode = usable >= 20 ? "full" : (usable >= 12 ? "compact" : "dot")
        if usable >= 12 {
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

/// Ponto que pulsa suavemente (modo mínimo quando quase não há espaço).
struct PulseDot: View {
    var size: CGFloat
    var delay: Double = 0
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: max(3, size), height: max(3, size))
            .opacity(on ? 1 : 0.35)
            .scaleEffect(on ? 1 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(delay)) { on = true }
            }
    }
}

/// Visualizador "fake" de áudio: ~8 quadros/s e pausado quando não toca.
struct AudioBars: View {
    var playing: Bool
    var color: Color
    var count: Int = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.14, paused: !playing)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: 3, height: playing ? barHeight(i, t) : 3)
                }
            }
            .frame(height: 14)
            .animation(.easeInOut(duration: 0.14), value: t)
        }
    }

    private func barHeight(_ i: Int, _ t: Double) -> CGFloat {
        let speeds = [5.1, 7.3, 4.2, 6.6]
        let v = (sin(t * speeds[i] + Double(i) * 1.7) + sin(t * speeds[(i + 2) % 4] * 0.6)) / 2
        return CGFloat(4 + (v + 1) / 2 * 10)
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
