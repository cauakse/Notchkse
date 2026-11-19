import SwiftUI

@main
struct NotchkseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A janela de ajustes é gerenciada manualmente (SettingsWindowController),
        // porque o app roda como "accessory" (sem Dock).
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Abrir o app de novo (Launchpad/Finder) abre os ajustes.
        coordinator?.openSettings()
        return false
    }
}
