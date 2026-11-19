import SwiftUI

struct SettingsView: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        @Bindable var settings = ctx.settings
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notchkse").font(.title2.bold())
                        Text("Versão \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Geral") {
                Toggle("Abrir ao passar o mouse", isOn: $settings.hoverToOpen)
                if settings.hoverToOpen {
                    LabeledContent("Atraso para abrir") {
                        Slider(value: $settings.hoverDelay, in: 0...0.6, step: 0.05) {
                            Text("\(Int(settings.hoverDelay * 1000)) ms")
                        }
                        .frame(width: 220)
                    }
                }
                Toggle("Vibração no trackpad", isOn: $settings.haptics)
                Toggle("Abrir ao iniciar sessão", isOn: Binding(
                    get: { settings.readLaunchAtLogin() },
                    set: { settings.launchAtLogin = $0 }))
                Toggle("Ícone na barra de menus", isOn: $settings.showMenuBarIcon)
                Text("Gestos: deslize dois dedos para baixo no notch para abrir, para cima para fechar e para os lados para trocar de música.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Aparência") {
                Toggle("Efeito de vidro (blur) no notch aberto", isOn: $settings.glassBackground)
                if settings.glassBackground {
                    LabeledContent("Escurecimento") {
                        Slider(value: $settings.glassDarkness, in: 0.05...0.9) {
                            Text("\(Int(settings.glassDarkness * 100))%")
                        }
                        .frame(width: 220)
                    }
                }
                Text("Fechado, o notch continua preto sólido para se fundir com o notch físico.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(ModuleID.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { module in
                        Toggle(isOn: Binding(get: { settings.isOn(module) }, set: { settings.set(module, $0) })) {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(module.title)
                                    Text(module.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: module.symbol).foregroundStyle(.primary)
                            }
                        }
                        .disabled(module == .lyrics && !settings.isOn(.media))
                    }
                    if group.0 == "Nook", settings.isOn(.media) {
                        Toggle("Mostrar música no notch fechado", isOn: $settings.mediaLiveActivity)
                    }
                    if group.0 == "Sistema", settings.isOn(.downloads), settings.isOn(.tray) {
                        Toggle("Colocar downloads concluídos na bandeja", isOn: $settings.addDownloadsToTray)
                    }
                }
            }

            if settings.isOn(.ai) {
                Section("Prompt de IA") {
                    Picker("Agente padrão", selection: $settings.preferredAgent) {
                        ForEach(AgentDefinition.known) { agent in
                            let installed = ctx.agent.available.contains(agent)
                            Text(agent.name + (installed ? "" : " (não instalado)")).tag(agent.id)
                        }
                    }
                    TextField("Modelo do Ollama", text: $settings.ollamaModel)
                    LabeledContent("Pasta de trabalho") {
                        HStack {
                            Text((settings.agentWorkingDirectory as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Button("Escolher…") { chooseFolder() }
                        }
                    }
                    Button("Procurar agentes instalados") { ctx.agent.detect(force: true) }
                }
            }

            if settings.isOn(.shortcuts) {
                Section("Atalhos no Nook") {
                    if !ctx.shortcuts.loaded {
                        ProgressView().controlSize(.small)
                    } else if ctx.shortcuts.all.isEmpty {
                        Text("Nenhum atalho encontrado no app Atalhos.").foregroundStyle(.secondary)
                    }
                    ForEach(ctx.shortcuts.all, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { settings.pinnedShortcuts.contains(name) },
                            set: { on in
                                if on { settings.pinnedShortcuts.append(name) }
                                else { settings.pinnedShortcuts.removeAll { $0 == name } }
                            }))
                    }
                }
            }

            Section {
                Button("Sair do Notchkse", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
        .onAppear {
            if settings.isOn(.shortcuts) { ctx.shortcuts.loadList() }
            if settings.isOn(.ai) { ctx.agent.detect() }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: ctx.settings.agentWorkingDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            ctx.settings.agentWorkingDirectory = url.path
        }
    }
}
