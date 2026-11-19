import AppKit
import EventKit
import Observation
import SwiftUI

// MARK: - Calendário

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let meetingURL: URL?

    var isNow: Bool { start <= Date() && end > Date() }
}

@Observable
final class CalendarService {
    enum Access { case unknown, granted, denied }

    private(set) var events: [CalendarEvent] = []
    private(set) var access: Access = .unknown

    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var token: NSObjectProtocol?

    func start() {
        guard store == nil else { return }
        let store = EKEventStore()
        self.store = store
        token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            reload()
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        store = nil
        events = []
    }

    /// Chamado ao abrir o notch (barato: só lê o banco local do EventKit).
    func reload() {
        guard let store, access == .granted else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now)) ?? now
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
            .map { event in
                CalendarEvent(id: event.eventIdentifier ?? UUID().uuidString,
                              title: event.title ?? "Sem título",
                              start: event.startDate, end: event.endDate,
                              isAllDay: event.isAllDay,
                              color: Color(cgColor: event.calendar.cgColor),
                              meetingURL: Self.meetingURL(in: event))
            }
    }

    private static let meetingPattern = try? NSRegularExpression(
        pattern: #"https://[^\s"<>]*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|facetime\.apple\.com)[^\s"<>]*"#)

    private static func meetingURL(in event: EKEvent) -> URL? {
        if let url = event.url, url.host.map({ $0.contains("meet") || $0.contains("zoom") || $0.contains("teams") }) == true {
            return url
        }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        let range = NSRange(text.startIndex..., in: text)
        guard let match = meetingPattern?.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        return URL(string: String(text[r]))
    }
}

// MARK: - Atalhos (app Shortcuts)

@Observable
final class ShortcutsService {
    private(set) var all: [String] = []
    private(set) var loaded = false
    private(set) var runningName: String?

    func loadList() {
        DispatchQueue.global(qos: .utility).async {
            let out = Shell.run("/usr/bin/shortcuts", ["list"]) ?? ""
            let names = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
            DispatchQueue.main.async { [weak self] in
                self?.all = names
                self?.loaded = true
            }
        }
    }

    func run(_ name: String) {
        runningName = name
        DispatchQueue.global(qos: .userInitiated).async {
            Shell.run("/usr/bin/shortcuts", ["run", name])
            DispatchQueue.main.async { [weak self] in
                if self?.runningName == name { self?.runningName = nil }
            }
        }
    }
}
