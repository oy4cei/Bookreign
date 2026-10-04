import SwiftUI

@main
struct PolkaApp: App {
    @StateObject private var store = LibraryStore()
    @State private var preferences = AppPreferences.shared
    init() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(Color.archiveHeader)
        navigation.shadowColor = UIColor(Color.archiveRule)
        let titleFont = UIFont.preferredFont(forTextStyle: .headline)
        let largeFont = UIFont.preferredFont(forTextStyle: .largeTitle)
        let ivory = UIColor(Color.archiveOnHeader)
        navigation.titleTextAttributes = [.foregroundColor: ivory,
            .font: UIFont(descriptor: titleFont.fontDescriptor.withDesign(.serif) ?? titleFont.fontDescriptor, size: 0)]
        navigation.largeTitleTextAttributes = [.foregroundColor: ivory,
            .font: UIFont(descriptor: largeFont.fontDescriptor.withDesign(.serif) ?? largeFont.fontDescriptor, size: 0)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = ivory

    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(.forest)
                .foregroundStyle(Color.archiveText)
                .environment(\.locale, preferences.locale)
                .background {
                    AppearanceWindowBridge(appearance: preferences.appearance)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .alert(L("Не удалось выполнить действие"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button(L("Понятно"), role: .cancel) { store.errorMessage = nil }
                } message: { if let message = store.errorMessage { Text(L(message)) } }
        }
    }
}

struct RootView: View {
    @State private var selectedTab: ArchiveTab = .books
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                LibraryView().tag(ArchiveTab.books)
                LocationsView().tag(ArchiveTab.places)
                TopicsView().tag(ArchiveTab.topics)
            }
            .toolbar(.hidden, for: .tabBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                tabButton(.books, title: L("Книги"), symbol: "books.vertical")
                tabButton(.places, title: L("Места"), symbol: "mappin.and.ellipse")
                tabButton(.topics, title: L("Темы"), symbol: "tag")
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.archiveHeader.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Color.archiveOnHeader.opacity(0.2)).frame(height: 0.5) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("archiveTabBar")
        }
    }

    private func tabButton(_ tab: ArchiveTab, title: String, symbol: String) -> some View {
        let selected = selectedTab == tab
        return Button { selectedTab = tab } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 21, weight: selected ? .semibold : .regular))
                Text(title).font(.caption.weight(selected ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Rectangle().fill(selected ? Color.archiveOnHeader : .clear).frame(width: 24, height: 2)
            }
            .foregroundStyle(Color.archiveOnHeader.opacity(selected ? 1 : 0.78))
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("tab-\(tab.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private enum ArchiveTab: String { case books, places, topics }
