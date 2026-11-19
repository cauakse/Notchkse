import Foundation
import Observation

struct LyricLine: Equatable {
    let time: Double
    let text: String
}

/// Busca letras sincronizadas (formato LRC) no LRCLIB, uma vez por faixa,
/// com cache pequeno em memória.
@Observable
final class LyricsService {
    enum State: Equatable { case idle, loading, ready, notFound }

    private(set) var state: State = .idle
    private(set) var lines: [LyricLine] = []

    @ObservationIgnored private var cache: [String: [LyricLine]] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var currentKey = ""

    func load(key: String, title: String, artist: String, album: String, duration: Double) {
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()
        guard !title.isEmpty else { reset(); return }
        if let cached = cache[key] {
            lines = cached
            state = cached.isEmpty ? .notFound : .ready
            return
        }
        lines = []
        state = .loading
        task = Task { [weak self] in
            let result = await Self.fetch(title: title, artist: artist, album: album, duration: duration)
            guard !Task.isCancelled, let self, self.currentKey == key else { return }
            self.remember(key, result)
            self.lines = result
            self.state = result.isEmpty ? .notFound : .ready
        }
    }

    func reset() {
        task?.cancel()
        currentKey = ""
        lines = []
        state = .idle
    }

    /// Índice da linha que deve estar em destaque no tempo `t`.
    func index(at t: Double) -> Int? {
        guard !lines.isEmpty, t + 0.3 >= lines[0].time else { return nil }
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].time <= t + 0.3 { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private func remember(_ key: String, _ value: [LyricLine]) {
        cache[key] = value
        cacheOrder.append(key)
        if cacheOrder.count > 25 { cache[cacheOrder.removeFirst()] = nil }
    }

    // MARK: Rede

    nonisolated private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = ["User-Agent": "Notchkse/1.0"]
        return URLSession(configuration: config)
    }()

    nonisolated private static func fetch(title: String, artist: String, album: String, duration: Double) async -> [LyricLine] {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        if let url = get.url,
           let (data, response) = try? await session.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let synced = object["syncedLyrics"] as? String {
            let parsed = parse(synced)
            if !parsed.isEmpty { return parsed }
        }

        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = search.url,
              let (data, _) = try? await session.data(from: url),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let synced = results.compactMap { $0["syncedLyrics"] as? String }.first { !$0.isEmpty }
        return synced.map(parse) ?? []
    }

    /// "[01:23.45] texto" → LyricLine(time: 83.45, text: "texto")
    nonisolated static func parse(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    times.append(m * 60 + s)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in times { result.append(LyricLine(time: t, text: text)) }
        }
        return result.sorted { $0.time < $1.time }
    }
}
