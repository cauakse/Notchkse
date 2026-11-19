import AppKit
import Observation

struct TrayItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var path: String
    var addedAt = Date()
    var isScreenshot = false

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

/// Bandeja de arquivos: guarda só referências (caminhos), não copia nada.
@Observable
final class TrayStore {
    private(set) var items: [TrayItem] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: "trayItems"),
           let saved = try? JSONDecoder().decode([TrayItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func add(_ urls: [URL], screenshot: Bool = false) {
        let existing = Set(items.map(\.path))
        let new = urls.filter { $0.isFileURL && !existing.contains($0.path) }
            .map { TrayItem(path: $0.path, isScreenshot: screenshot) }
        guard !new.isEmpty else { return }
        items.insert(contentsOf: new, at: 0)
        if items.count > 40 { items.removeLast(items.count - 40) }
        save()
    }

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "trayItems")
        }
    }
}

/// Cache de miniaturas compartilhado (limitado para manter a RAM baixa).
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 60
        return c
    }()

    func image(for url: URL) -> NSImage? { cache.object(forKey: url.path as NSString) }
    func store(_ image: NSImage, for url: URL) { cache.setObject(image, forKey: url.path as NSString) }
}
