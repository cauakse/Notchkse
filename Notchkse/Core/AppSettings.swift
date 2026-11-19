import Foundation
import Observation
import ServiceManagement

/// Cada funcionalidade do notch é um módulo que pode ser ligado/desligado.
enum ModuleID: String, CaseIterable, Identifiable {
    case media, lyrics, calendar, mirror, shortcuts
    case tray, airdrop, screenshots
    case clipboard, ai
    case battery, bluetooth, downloads, stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Música"
        case .lyrics: "Letra sincronizada"
        case .calendar: "Calendário"
        case .mirror: "Espelho (câmera)"
        case .shortcuts: "Atalhos"
        case .tray: "Bandeja de arquivos"
        case .airdrop: "AirDrop"
        case .screenshots: "Prateleira de capturas"
        case .clipboard: "Histórico do clipboard"
        case .ai: "Prompt de IA"
        case .battery: "Carregamento"
        case .bluetooth: "Dispositivos conectados"
        case .downloads: "Progresso de downloads"
        case .stats: "Medidores do sistema"
        }
    }

    var subtitle: String {
        switch self {
        case .media: "Capa, controles e visualizador (Spotify e Music)"
        case .lyrics: "Linha atual da música em tempo real (LRCLIB)"
        case .calendar: "Próximos eventos e botão para entrar na reunião"
        case .mirror: "Prévia da câmera antes de uma call"
        case .shortcuts: "Rode seus Atalhos favoritos"
        case .tray: "Arraste arquivos para o notch e guarde por um tempo"
        case .airdrop: "Solte arquivos para enviar via AirDrop"
        case .screenshots: "Capturas de tela vão direto para a bandeja"
        case .clipboard: "Os 10 últimos itens copiados"
        case .ai: "Pergunte ao Claude, Codex ou outro agente instalado"
        case .battery: "Aviso ao conectar o carregador"
        case .bluetooth: "Bateria de AirPods, teclado, mouse… ao conectar"
        case .downloads: "Progresso e aviso de download concluído"
        case .stats: "CPU, GPU e RAM no topo do notch aberto (só lê com ele aberto)"
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .lyrics: "quote.bubble"
        case .calendar: "calendar"
        case .mirror: "person.crop.square"
        case .shortcuts: "square.stack.3d.up"
        case .tray: "tray.full"
        case .airdrop: "airplayaudio"
        case .screenshots: "camera.viewfinder"
        case .clipboard: "doc.on.clipboard"
        case .ai: "sparkles"
        case .battery: "battery.100percent.bolt"
        case .bluetooth: "airpodspro"
        case .downloads: "arrow.down.circle"
        case .stats: "gauge.with.dots.needle.67percent"
        }
    }

    var defaultOn: Bool { self != .calendar }

    static let groups: [(String, [ModuleID])] = [
        ("Nook", [.media, .lyrics, .calendar, .mirror, .shortcuts]),
        ("Bandeja", [.tray, .airdrop, .screenshots]),
        ("Produtividade", [.clipboard, .ai]),
        ("Sistema", [.stats, .battery, .bluetooth, .downloads]),
    ]
}

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Chamado sempre que algo que exige iniciar/parar serviços muda.
    @ObservationIgnored var onModulesChanged: (() -> Void)?
    @ObservationIgnored var onAppearanceChanged: (() -> Void)?

    var modules: Set<String> {
        didSet { defaults.set(Array(modules), forKey: "modules"); onModulesChanged?() }
    }
    var hoverToOpen: Bool { didSet { defaults.set(hoverToOpen, forKey: "hoverToOpen") } }
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon"); onAppearanceChanged?() }
    }
    var mediaLiveActivity: Bool { didSet { defaults.set(mediaLiveActivity, forKey: "mediaLiveActivity") } }
    var preferredAgent: String { didSet { defaults.set(preferredAgent, forKey: "preferredAgent") } }
    var ollamaModel: String { didSet { defaults.set(ollamaModel, forKey: "ollamaModel") } }
    var agentWorkingDirectory: String { didSet { defaults.set(agentWorkingDirectory, forKey: "agentWorkingDirectory") } }
    var addDownloadsToTray: Bool { didSet { defaults.set(addDownloadsToTray, forKey: "addDownloadsToTray") } }
    var pinnedShortcuts: [String] { didSet { defaults.set(pinnedShortcuts, forKey: "pinnedShortcuts") } }
    /// Fundo do notch aberto com efeito de vidro (blur do que está atrás).
    var glassBackground: Bool { didSet { defaults.set(glassBackground, forKey: "glassBackground") } }
    /// 0 = vidro bem transparente, 1 = quase preto sólido.
    var glassDarkness: Double { didSet { defaults.set(glassDarkness, forKey: "glassDarkness") } }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Notchkse: launch at login failed: \(error)")
            }
            launchAtLoginTick &+= 1
        }
    }
    /// Força o SwiftUI a reler `launchAtLogin` depois de alterar.
    private var launchAtLoginTick = 0

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "modules": ModuleID.allCases.filter(\.defaultOn).map(\.rawValue),
            "hoverToOpen": true,
            "hoverDelay": 0.12,
            "haptics": true,
            "showMenuBarIcon": true,
            "mediaLiveActivity": true,
            "preferredAgent": "claude",
            "ollamaModel": "llama3.2",
            "agentWorkingDirectory": NSHomeDirectory(),
            "addDownloadsToTray": false,
            "pinnedShortcuts": [String](),
            "glassBackground": true,
            "glassDarkness": 0.45,
        ])
        modules = Set(d.stringArray(forKey: "modules") ?? [])
        hoverToOpen = d.bool(forKey: "hoverToOpen")
        hoverDelay = d.double(forKey: "hoverDelay")
        haptics = d.bool(forKey: "haptics")
        showMenuBarIcon = d.bool(forKey: "showMenuBarIcon")
        mediaLiveActivity = d.bool(forKey: "mediaLiveActivity")
        preferredAgent = d.string(forKey: "preferredAgent") ?? "claude"
        ollamaModel = d.string(forKey: "ollamaModel") ?? "llama3.2"
        agentWorkingDirectory = d.string(forKey: "agentWorkingDirectory") ?? NSHomeDirectory()
        addDownloadsToTray = d.bool(forKey: "addDownloadsToTray")
        pinnedShortcuts = d.stringArray(forKey: "pinnedShortcuts") ?? []
        glassBackground = d.bool(forKey: "glassBackground")
        glassDarkness = d.double(forKey: "glassDarkness")
    }

    func isOn(_ module: ModuleID) -> Bool { modules.contains(module.rawValue) }

    func set(_ module: ModuleID, _ on: Bool) {
        if on { modules.insert(module.rawValue) } else { modules.remove(module.rawValue) }
    }

    func readLaunchAtLogin() -> Bool {
        _ = launchAtLoginTick
        return launchAtLogin
    }
}
