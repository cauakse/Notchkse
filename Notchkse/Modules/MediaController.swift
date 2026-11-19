import AppKit
import Observation
import SwiftUI

enum MediaSource: String {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var scriptName: String { self == .spotify ? "Spotify" : "Music" }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty }
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) }
}

/// "Now Playing" orientado a eventos: Spotify e Music avisam por notificação
/// distribuída a cada mudança. Nada fica consultando em loop.
@Observable
final class MediaController {
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var artwork: NSImage?
    /// Cor de destaque da música (fixa em branco no tema monocromático).
    let accent: Color = .white
    private(set) var isPlaying = false
    private(set) var duration: Double = 0
    private(set) var source: MediaSource?
    private(set) var trackKey = ""
    private(set) var basePosition: Double = 0
    private(set) var baseDate = Date()

    @ObservationIgnored var onTrackChange: (() -> Void)?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var running = false
    @ObservationIgnored private let queue = DispatchQueue(label: "dev.notchkse.applescript", qos: .userInitiated)

    var hasTrack: Bool { !title.isEmpty }

    func position(at date: Date = Date()) -> Double {
        let p = isPlaying ? basePosition + date.timeIntervalSince(baseDate) : basePosition
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }

    // MARK: Ciclo de vida

    func start() {
        guard !running else { return }
        running = true
        let dnc = DistributedNotificationCenter.default()
        observe(dnc, "com.spotify.client.PlaybackStateChanged") { $0.handle($1, from: .spotify) }
        observe(dnc, "com.apple.Music.playerInfo") { $0.handle($1, from: .music) }

        let ws = NSWorkspace.shared.notificationCenter
        let token = ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, id == self.source?.rawValue else { return }
                self.clear()
            }
        }
        observers.append((ws, token))
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        clear()
    }

    private func observe(_ center: DistributedNotificationCenter, _ name: String,
                         _ handler: @escaping (MediaController, [AnyHashable: Any]) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self, info)
            }
        }
        observers.append((center, token))
    }

    // MARK: Eventos

    private func handle(_ info: [AnyHashable: Any], from src: MediaSource) {
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" {
            if source == src || source == nil { clear() }
            return
        }
        // Outro player tocando e este só pausou: ignora.
        if state != "Playing", let current = source, current != src, isPlaying { return }

        let name = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        let durationMs = (info[src == .spotify ? "Duration" : "Total Time"] as? NSNumber)?.doubleValue ?? 0
        let key: String
        if src == .spotify {
            key = info["Track ID"] as? String ?? "\(name)|\(artist)"
        } else {
            key = (info["PersistentID"] as? NSNumber)?.stringValue ?? "\(name)|\(artist)"
        }
        let position = src == .spotify ? (info["Playback Position"] as? NSNumber)?.doubleValue : nil
        apply(src: src, title: name, artist: artist, album: album, duration: durationMs / 1000,
              key: key, playing: state == "Playing", position: position)
        if src == .music { fetchMusicPosition() }
    }

    private func apply(src: MediaSource, title: String, artist: String, album: String,
                       duration: Double, key: String, playing: Bool, position: Double?) {
        guard !title.isEmpty else { return }
        let changed = key != trackKey || src != source
        let current = self.position()
        source = src
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        trackKey = key
        if let position { basePosition = position } else if changed { basePosition = 0 } else { basePosition = current }
        baseDate = Date()
        isPlaying = playing
        if changed {
            artwork = nil
            loadArtwork(src: src, key: key)
            onTrackChange?()
        }
    }

    private func clear() {
        title = ""; artist = ""; album = ""; artwork = nil
        isPlaying = false; duration = 0; source = nil; trackKey = ""
        basePosition = 0
        onTrackChange?()
    }

    /// Estado inicial ao abrir o app (os players só avisam na próxima mudança).
    private func refresh() {
        for src in [MediaSource.spotify, .music] where src.isRunning {
            let script = """
            tell application "\(src.scriptName)"
                set s to player state as string
                if s is "stopped" then return s
                set t to current track
                return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) as string) & linefeed & ((player position) as string) & linefeed & (\(src == .spotify ? "id" : "persistent ID") of t)
            end tell
            """
            queue.async {
                let result = AppleScript.run(script)?.stringValue
                DispatchQueue.main.async { [weak self] in
                    guard let self, let result else { return }
                    let parts = result.components(separatedBy: "\n")
                    guard parts.count >= 7 else { return }
                    let num = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                    let playing = parts[0] == "playing"
                    if self.isPlaying && !playing { return }
                    let duration = src == .spotify ? num(parts[4]) / 1000 : num(parts[4])
                    self.apply(src: src, title: parts[1], artist: parts[2], album: parts[3], duration: duration,
                               key: parts[6], playing: playing, position: num(parts[5]))
                }
            }
        }
    }

    private func fetchMusicPosition() {
        queue.async {
            let value = AppleScript.run("tell application \"Music\" to return player position")?.doubleValue
            DispatchQueue.main.async { [weak self] in
                guard let self, let value, self.source == .music else { return }
                self.basePosition = value
                self.baseDate = Date()
            }
        }
    }

    private func loadArtwork(src: MediaSource, key: String) {
        queue.async {
            var data: Data?
            if src == .spotify {
                if let urlString = AppleScript.run("tell application \"Spotify\" to return artwork url of current track")?.stringValue,
                   let url = URL(string: urlString) {
                    data = try? Data(contentsOf: url) // fila em background, ~30 KB
                }
            } else {
                data = AppleScript.run("tell application \"Music\" to return raw data of artwork 1 of current track")?.data
            }
            let image = data.flatMap { ImageUtils.thumbnail(data: $0, maxPixel: 300) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.trackKey == key else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.artwork = image
                }
            }
        }
    }

    // MARK: Controles

    func togglePlay() {
        guard let src = activeSource else { openPlayer(); return }
        send("playpause", to: src)
        let current = position()
        isPlaying.toggle()
        basePosition = current
        baseDate = Date()
    }

    func next() { if let src = activeSource { send("next track", to: src) } }
    func previous() { if let src = activeSource { send("previous track", to: src) } }

    func seek(to seconds: Double) {
        guard let src = activeSource else { return }
        send("set player position to \(seconds)", to: src)
        basePosition = seconds
        baseDate = Date()
    }

    func openPlayer() {
        let url = source?.appURL ?? MediaSource.spotify.appURL ?? MediaSource.music.appURL
        if let url { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }

    private var activeSource: MediaSource? {
        if let source, source.isRunning { return source }
        if MediaSource.spotify.isRunning { return .spotify }
        if MediaSource.music.isRunning { return .music }
        return nil
    }

    private func send(_ command: String, to src: MediaSource) {
        let script = "tell application \"\(src.scriptName)\" to \(command)"
        queue.async { _ = AppleScript.run(script) }
    }
}
