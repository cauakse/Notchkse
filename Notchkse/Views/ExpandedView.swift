import SwiftUI

struct ExpandedView: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        VStack(spacing: 8) {
            header
            Group {
                switch ctx.model.tab {
                case .home: HomeView()
                case .tray: TrayView()
                case .clipboard: ClipboardView()
                case .ai: AIView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
            .id(ctx.model.tab)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
        .dropDestination(for: URL.self) { urls, _ in
            guard ctx.isOn(.tray) else { return false }
            ctx.tray.add(urls)
            withAnimation(.notchPeek) { ctx.model.tab = .tray }
            return true
        } isTargeted: { targeted in
            withAnimation(.notchPeek) { ctx.model.isDropTargeted = targeted }
        }
    }

    /// Cabeçalho na altura do notch: abas à esquerda, status à direita.
    private var header: some View {
        HStack(spacing: 4) {
            ForEach(ctx.visibleTabs) { tab in
                let selected = ctx.model.tab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { ctx.model.tab = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? .white : Theme.secondaryText)
                        .frame(width: 30, height: 24)
                        .background {
                            if selected {
                                Capsule().fill(Color.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "tab", in: tabNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
            Spacer(minLength: ctx.model.notchSize.width + 20)
            if ctx.isOn(.stats) {
                HeaderStats()
            }
            Button { ctx.openSettings() } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(HoverButtonStyle(size: 24))
            .help("Ajustes")
        }
        .frame(height: max(ctx.model.notchSize.height, 28))
    }

    @Namespace private var tabNamespace
}
