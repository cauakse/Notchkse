import SwiftUI

struct NotchRootView: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        let model = ctx.model
        let size = currentSize
        let topRadius = model.isExpanded ? NotchMetrics.openTopRadius : NotchMetrics.closedTopRadius
        let bottomRadius = model.isExpanded ? NotchMetrics.openBottomRadius : NotchMetrics.closedBottomRadius
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(model.isExpanded ? 0.55 : 0), radius: 16, y: 8)

            Group {
                if model.isExpanded {
                    ExpandedView()
                        .padding(.horizontal, topRadius)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                                .animation(.notchOpen.delay(0.05)),
                            removal: .opacity.animation(.easeOut(duration: 0.12))))
                } else {
                    ClosedView(notchWidth: model.notchSize.width, height: model.notchSize.height)
                        .padding(.horizontal, topRadius)
                        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(model.isDropTargeted ? 1.02 : 1, anchor: .top)
        .frame(width: NotchMetrics.windowWidth, height: NotchMetrics.windowHeight, alignment: .top)
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
            let side: CGFloat = activity.hasPeekRow ? 90 : (activity.trailingText != nil ? 46 : 34)
            let extraHeight = activity.hasPeekRow ? NotchMetrics.peekRowHeight : 0
            return CGSize(width: base + 2 * side, height: notch.height + extraHeight)
        }
        if ClosedView.showsMedia(ctx) {
            return CGSize(width: base + 2 * 34, height: notch.height)
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

    static func activeActivity(_ ctx: AppContext) -> LiveActivity? {
        ctx.activities.transient ?? ctx.activities.download
    }

    static func showsMedia(_ ctx: AppContext) -> Bool {
        ctx.isOn(.media) && ctx.settings.mediaLiveActivity && ctx.media.hasTrack && ctx.media.isPlaying
    }

    var body: some View {
        if let activity = Self.activeActivity(ctx) {
            VStack(spacing: 0) {
                row(leading: leading(activity), trailing: trailing(activity))
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
        } else if Self.showsMedia(ctx) {
            row(leading: AnyView(artwork(ctx.media.artwork, size: height - 12)),
                trailing: AnyView(AudioBars(playing: ctx.media.isPlaying, color: ctx.media.accent)))
                .transition(.blurReplace)
        } else {
            Color.clear
        }
    }

    private func row(leading: AnyView, trailing: AnyView) -> some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
    }

    private func leading(_ a: LiveActivity) -> AnyView {
        if let image = a.image {
            return AnyView(artwork(image, size: height - 12))
        }
        return AnyView(Image(systemName: a.symbol ?? "circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(a.tint)
            .symbolEffect(.bounce, value: a.id))
    }

    private func trailing(_ a: LiveActivity) -> AnyView {
        if a.kind == .download {
            return AnyView(ProgressRing(progress: a.progress ?? 0, color: a.tint).frame(width: 16, height: 16))
        }
        if let text = a.trailingText {
            return AnyView(Text(text).font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(a.kind == .charging ? .green : .white)
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

/// Visualizador "fake" de áudio: ~8 quadros/s e pausado quando não toca.
struct AudioBars: View {
    var playing: Bool
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.14, paused: !playing)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
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

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.03, progress))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
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
