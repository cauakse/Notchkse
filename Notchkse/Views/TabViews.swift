import QuickLookThumbnailing
import SwiftUI

// MARK: - Bandeja (arquivos + capturas + AirDrop)

struct TrayView: View {
    @Environment(AppContext.self) private var ctx
    @State private var airDropTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            if ctx.isOn(.tray) || ctx.isOn(.screenshots) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Bandeja").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentSoft)
                        Text("\(ctx.tray.items.count)").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if !ctx.tray.items.isEmpty {
                            Button("Limpar") { withAnimation(.spring) { ctx.tray.clear() } }
                                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if ctx.tray.items.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "tray.and.arrow.down").font(.system(size: 26))
                            Text("Arraste arquivos para cá").font(.system(size: 12))
                        }
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .foregroundStyle(ctx.model.isDropTargeted ? Theme.accent : Theme.cardStroke))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) {
                                ForEach(ctx.tray.items) { item in
                                    TrayTile(item: item)
                                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .card()
            }

            if ctx.isOn(.airdrop) {
                VStack(spacing: 8) {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: airDropTargeted)
                    Text("AirDrop").font(.system(size: 12, weight: .semibold))
                    Text(ctx.tray.items.isEmpty ? "Solte aqui" : "Solte ou clique\npara enviar tudo")
                        .font(.system(size: 10)).multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText)
                }
                .frame(width: 120)
                .frame(maxHeight: .infinity)
                .background((airDropTargeted ? Color.white.opacity(0.18) : Theme.card),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardStroke))
                .scaleEffect(airDropTargeted ? 1.04 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: airDropTargeted)
                .contentShape(Rectangle())
                .onTapGesture { ctx.tray.airDrop(ctx.tray.items.map(\.url)) }
                .dropDestination(for: URL.self) { urls, _ in
                    ctx.tray.airDrop(urls)
                    return true
                } isTargeted: { airDropTargeted = $0 }
            }
        }
    }
}

struct TrayTile: View {
    @Environment(AppContext.self) private var ctx
    let item: TrayItem
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable()
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if item.isScreenshot {
                    Image(systemName: "camera.viewfinder").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black).padding(3).background(Color.white, in: Circle()).offset(x: 4, y: -4)
                }
                if hovering {
                    Button { withAnimation(.spring) { ctx.tray.remove(item) } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                            .foregroundStyle(.white, .black.opacity(0.7))
                    }
                    .buttonStyle(.plain).offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            Text(item.name).font(.system(size: 10)).lineLimit(1).truncationMode(.middle).frame(width: 72)
        }
        .padding(4)
        .background(Color.white.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(item.url) }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Enviar por AirDrop") { ctx.tray.airDrop([item.url]) }
            Divider()
            Button("Remover da bandeja") { ctx.tray.remove(item) }
        }
        .task(id: item.path) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        if let cached = ThumbnailCache.shared.image(for: item.url) { thumbnail = cached; return }
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 116, height: 116),
                                                   scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
        ThumbnailCache.shared.store(rep.nsImage, for: item.url)
        thumbnail = rep.nsImage
    }
}

// MARK: - Clipboard

struct ClipboardView: View {
    @Environment(AppContext.self) private var ctx
    @State private var copiedID: UUID?

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Clipboard").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentSoft)
                Text("últimos \(ClipboardMonitor.limit)").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                Spacer()
                if !ctx.clipboard.items.isEmpty {
                    Button("Limpar") { withAnimation(.spring) { ctx.clipboard.clear() } }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                }
            }
            if ctx.clipboard.items.isEmpty {
                Text("Copie algo (⌘C) e ele aparece aqui.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(ctx.clipboard.items) { item in
                            clipCard(item)
                        }
                    }
                }
            }
        }
        .card(padding: 10)
    }

    private func clipCard(_ item: ClipItem) -> some View {
        Button {
            ctx.clipboard.copy(item)
            withAnimation(.spring(response: 0.3)) { copiedID = item.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { if copiedID == item.id { copiedID = nil } }
            }
        } label: {
            HStack(spacing: 8) {
                if let preview = item.preview {
                    Image(nsImage: preview).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        switch item.kind {
                        case .text(let text): Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        case .image: Text("Imagem")
                        case .files(let urls): Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) arquivos")
                        }
                    }
                    .font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(item.date, style: .relative).font(.system(size: 9)).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                if copiedID == item.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).transition(.scale)
                } else if let icon = item.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16).opacity(0.8)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Remover") { ctx.clipboard.remove(item) } }
    }
}

// MARK: - Prompt de IA

struct AIView: View {
    @Environment(AppContext.self) private var ctx
    @State private var prompt = ""
    @State private var continuing = true
    @FocusState private var focused: Bool

    private var agent: AgentDefinition? {
        let list = ctx.agent.available
        return list.first { $0.id == ctx.settings.preferredAgent } ?? list.first
    }

    var body: some View {
        let runner = ctx.agent
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(runner.available) { a in
                        Button { ctx.settings.preferredAgent = a.id } label: { Label(a.name, systemImage: a.symbol) }
                    }
                    Divider()
                    Button("Procurar agentes de novo") { runner.detect(force: true) }
                } label: {
                    Label(agent?.name ?? (runner.detected ? "Nenhum agente" : "Procurando…"),
                          systemImage: agent?.symbol ?? "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                TextField(agent.map { "Pergunte ao \($0.name)…" } ?? "Instale claude, codex, gemini…", text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .focused($focused)
                    .onSubmit(send)
                    .disabled(agent == nil)

                if runner.isRunning {
                    Button(action: runner.stop) { Image(systemName: "stop.fill") }
                        .buttonStyle(HoverButtonStyle())
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                            .foregroundStyle(prompt.isEmpty ? Theme.secondaryText : .white)
                    }
                    .buttonStyle(HoverButtonStyle())
                    .disabled(prompt.isEmpty || agent == nil)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !runner.lastPrompt.isEmpty {
                            Text(runner.lastPrompt).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        }
                        if runner.isRunning && runner.output.isEmpty {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Pensando…").font(.system(size: 12)) }
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Text(runner.output.isEmpty && !runner.isRunning ? placeholder : runner.output)
                            .font(.system(size: 12))
                            .foregroundStyle(runner.output.isEmpty ? Theme.secondaryText : .white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .onChange(of: runner.output) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .card(padding: 10)

            HStack {
                if agent?.supportsContinue == true {
                    Toggle("Continuar conversa", isOn: $continuing).toggleStyle(.checkbox).font(.system(size: 10))
                }
                Spacer()
                if !runner.output.isEmpty {
                    Button("Copiar resposta") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(runner.output, forType: .string)
                    }
                    Button("Nova conversa") { runner.newConversation() }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(Theme.secondaryText)
        }
        .onAppear {
            runner.detect()
            DispatchQueue.main.async { focused = true }
        }
    }

    private var placeholder: String {
        guard ctx.agent.detected else { return "" }
        return agent == nil
            ? "Nenhum agente de IA encontrado. Instale o Claude Code, Codex, Gemini CLI, OpenCode ou Ollama."
            : "Digite e aperte Enter. A resposta aparece aqui — você pode fechar o notch que eu aviso quando terminar."
    }

    private func send() {
        guard let agent, !prompt.isEmpty else { return }
        ctx.agent.run(prompt: prompt, agent: agent, settings: ctx.settings, continuing: continuing)
        prompt = ""
    }
}
