import AVFoundation
import SwiftUI

struct HomeView: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        HStack(spacing: 10) {
            if ctx.isOn(.media) { MediaCard() }
            if ctx.isOn(.calendar) { CalendarCard().frame(width: 180) }
            if ctx.isOn(.shortcuts) { ShortcutsCard().frame(width: 150) }
            if ctx.isOn(.mirror) { MirrorTile().frame(width: 120) }
        }
    }
}

// MARK: - Música

struct MediaCard: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        let media = ctx.media
        HStack(spacing: 12) {
            ZStack {
                if let art = media.artwork {
                    // "Glow" da capa por trás, como no sistema.
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 84, height: 84).blur(radius: 20).opacity(0.5)
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.opacity)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08))
                        .frame(width: 84, height: 84)
                        .overlay(Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(Theme.secondaryText))
                }
            }
            .scaleEffect(media.isPlaying ? 1 : 0.92)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: media.isPlaying)

            VStack(alignment: .leading, spacing: 4) {
                if media.hasTrack {
                    HStack {
                        Text(media.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                        Spacer(minLength: 4)
                        AudioBars(playing: media.isPlaying, color: media.accent)
                    }
                    Text(media.artist).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    if ctx.isOn(.lyrics) { LyricLineView() }
                    Spacer(minLength: 0)
                    ProgressBar()
                } else {
                    Text("Nada tocando").font(.system(size: 15, weight: .bold))
                    Text("Abra o Spotify ou o Music").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    Spacer(minLength: 0)
                }
                controls
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    private var controls: some View {
        let media = ctx.media
        return HStack(spacing: 8) {
            Spacer()
            Button(action: media.previous) { Image(systemName: "backward.fill").font(.system(size: 15)) }
            Button(action: media.togglePlay) {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
            }
            Button(action: media.next) { Image(systemName: "forward.fill").font(.system(size: 15)) }
            Spacer()
        }
        .buttonStyle(HoverButtonStyle(size: 30))
    }
}

/// Barra de progresso arrastável. Atualiza 1x/s apenas enquanto toca.
struct ProgressBar: View {
    @Environment(AppContext.self) private var ctx
    @State private var dragValue: Double?

    var body: some View {
        let media = ctx.media
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let position = dragValue ?? media.position(at: timeline.date)
            let fraction = media.duration > 0 ? position / media.duration : 0
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(media.accent).frame(width: max(4, geo.size.width * fraction))
                    }
                    .frame(height: dragValue == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            dragValue = min(max(v.location.x / geo.size.width, 0), 1) * media.duration
                        }
                        .onEnded { _ in
                            if let dragValue { media.seek(to: dragValue) }
                            dragValue = nil
                        })
                    .animation(.spring(response: 0.25), value: dragValue == nil)
                }
                .frame(height: 10)
                HStack {
                    Text(format(position)); Spacer(); Text("-" + format(max(0, media.duration - position)))
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func format(_ t: Double) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct LyricLineView: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        let lyrics = ctx.lyrics
        Group {
            switch lyrics.state {
            case .ready:
                TimelineView(.periodic(from: .now, by: 0.35)) { timeline in
                    let index = lyrics.index(at: ctx.media.position(at: timeline.date))
                    let text = index.map { lyrics.lines[$0].text } ?? "♪"
                    Text(text.isEmpty ? "♪" : text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ctx.media.accent)
                        .lineLimit(2)
                        .id(index ?? -1)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
                }
            case .loading:
                Text("Buscando letra…").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

// MARK: - Calendário

struct CalendarCard: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Date.now, format: .dateTime.weekday(.wide).day())
                    .font(.system(size: 12, weight: .bold)).textCase(.uppercase)
                    .foregroundStyle(Theme.accentSoft)
                Spacer()
            }
            switch ctx.calendar.access {
            case .denied:
                Text("Sem acesso ao calendário. Libere em Ajustes do Sistema › Privacidade.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            case .unknown:
                ProgressView().controlSize(.small)
            case .granted:
                if ctx.calendar.events.isEmpty {
                    Text("Nada na agenda 🎉").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                ForEach(ctx.calendar.events.prefix(3)) { event in
                    HStack(spacing: 6) {
                        Capsule().fill(event.color).frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text(event.isAllDay ? "Dia todo" : event.start.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                        if let url = event.meetingURL {
                            Button { NSWorkspace.shared.open(url); ctx.closeNotch() } label: {
                                Image(systemName: "video.fill").font(.system(size: 10))
                                    .foregroundStyle(event.isNow ? .black : .white).padding(5).background(Color.white.opacity(event.isNow ? 0.95 : 0.2), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Entrar na reunião")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }
}

// MARK: - Atalhos

struct ShortcutsCard: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Atalhos").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentSoft)
            if ctx.settings.pinnedShortcuts.isEmpty {
                Text("Escolha seus atalhos nos Ajustes.").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                Button("Abrir Ajustes") { ctx.openSettings() }.controlSize(.small)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(ctx.settings.pinnedShortcuts, id: \.self) { name in
                        Button { ctx.shortcuts.run(name) } label: {
                            HStack {
                                Image(systemName: ctx.shortcuts.runningName == name ? "hourglass" : "play.fill")
                                    .font(.system(size: 9))
                                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }
}

// MARK: - Espelho

struct MirrorTile: View {
    @State private var active = false

    var body: some View {
        ZStack {
            if active {
                CameraPreview()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.square").font(.system(size: 26))
                    Text("Espelho").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardStroke))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { active.toggle() } }
        .help("Clique para ligar/desligar a câmera")
    }
}

/// A câmera só roda enquanto o espelho está visível; ao fechar o notch, desliga.
struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraView { CameraView() }
    func updateNSView(_ nsView: CameraView, context: Context) {}
    static func dismantleNSView(_ nsView: CameraView, coordinator: ()) { nsView.stop() }
}

final class CameraView: NSView {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.notchkse.camera")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.connection?.automaticallyAdjustsVideoMirroring = false
        preview.connection?.isVideoMirrored = true
        layer = preview
        session.sessionPreset = .medium
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        let session = self.session
        queue.async { session.startRunning() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func stop() {
        let session = self.session
        queue.async { session.stopRunning() }
    }
}
