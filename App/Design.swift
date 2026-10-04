import SwiftUI
import UIKit
import LibraryCore

extension Color {
    static let paper = archiveColor(light: 0xF1EBDD, dark: 0x102C25)
    static let forest = archiveColor(light: 0x1C4036, dark: 0xF1EBDD)
    static let forestFill = forest
    static let archiveText = archiveColor(light: 0x201F1A, dark: 0xF1EBDD)
    static let archiveSecondary = archiveColor(light: 0x615F57, dark: 0xBCCAC0)
    static let archiveSurface = archiveColor(light: 0xF7F2E7, dark: 0x1C4036)
    static let archiveRule = archiveColor(light: 0xD0C9BB, dark: 0x426157)
    static let archiveHeader = archiveColor(light: 0x1C4036, dark: 0x102C25)
    static let archiveOnHeader = Color(uiColor: UIColor(archiveHex: 0xF1EBDD))
    static let archiveActionText = archiveColor(light: 0xF1EBDD, dark: 0x102C25)
    // Native toggles and swipe actions supply a white thumb/label themselves.
    static let archiveControlFill = Color(uiColor: UIColor(archiveHex: 0x2D6B57))

    private static func archiveColor(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(archiveHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(archiveHex: UInt32) {
        self.init(red: CGFloat((archiveHex >> 16) & 0xff) / 255,
                  green: CGFloat((archiveHex >> 8) & 0xff) / 255,
                  blue: CGFloat(archiveHex & 0xff) / 255, alpha: 1)
    }
}

/// Colors in the navigation bar deliberately stay light in both themes.
/// Resolve its background outside the bar's forced dark color scheme.
private struct ArchiveScreen: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.archiveText)
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(uiColor: UIColor(archiveHex: colorScheme == .dark ? 0x102C25 : 0x1C4036)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    }
}

extension View {
    func archiveScreen() -> some View { modifier(ArchiveScreen()) }
    func archiveRow() -> some View {
        listRowBackground(Color.archiveSurface)
            .listRowSeparatorTint(.archiveRule)
    }
}

struct ArchivePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .frame(minHeight: 48)
            .foregroundStyle(Color.archiveActionText)
            .background(Color.forestFill, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.38)
    }
}

struct ArchiveSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(minHeight: 44)
            .foregroundStyle(Color.forest)
            .background(configuration.isPressed ? Color.forest.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.archiveRule, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.38)
    }
}

struct ArchivePageHeader: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.largeTitle, design: .serif, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle { Text(subtitle).font(.subheadline) }
        }
        .foregroundStyle(Color.archiveOnHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 22)
        .background(Color.archiveHeader)
    }
}

/// Plain, high-contrast controls on the archive's opaque navigation header.
/// iOS 26's automatic glass grouping otherwise adds a pale fill beneath them.
struct ArchiveToolbarItem<Content: View>: ToolbarContent {
    var placement: ToolbarItemPlacement = .automatic
    @ViewBuilder var content: () -> Content

    @ToolbarContentBuilder var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: placement) {
                content().buttonStyle(ArchiveToolbarButtonStyle())
                    .foregroundStyle(Color.archiveOnHeader).tint(.archiveOnHeader)
            }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) {
                content().buttonStyle(ArchiveToolbarButtonStyle())
                    .foregroundStyle(Color.archiveOnHeader).tint(.archiveOnHeader)
            }
        }
    }
}

private struct ArchiveToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Color.archiveOnHeader)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

struct BookCover: View {
    let edition: BookEdition
    var large = false
    private var palette: (Color, Color) {
        let choices: [(Color, Color)] = [(.init(red: 0.31, green: 0.39, blue: 0.33), .init(red: 0.91, green: 0.83, blue: 0.59)), (.init(red: 0.73, green: 0.38, blue: 0.26), .init(red: 1, green: 0.92, blue: 0.73)), (.init(red: 0.24, green: 0.33, blue: 0.47), .init(red: 0.89, green: 0.84, blue: 0.71)), (.init(red: 0.71, green: 0.61, blue: 0.43), .init(red: 0.23, green: 0.24, blue: 0.20))]
        return choices[edition.title.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % choices.count }]
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                placeholder(width: proxy.size.width)
                if let data = edition.coverData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else if let url = URL(string: edition.coverURL), url.scheme == "https" {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            .overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.09)).frame(width: 5) }
            .clipShape(RoundedRectangle(cornerRadius: large ? 6 : 3))
        }
        .aspectRatio(0.68, contentMode: .fit)
        .accessibilityHidden(true)
    }
    private func placeholder(width: CGFloat) -> some View {
        let scale = width / 170
        return ZStack {
            palette.0
            VStack(spacing: 6 * scale) {
                Text(edition.author.isEmpty ? L("ЛИЧНАЯ БИБЛИОТЕКА") : edition.author.uppercased())
                    .font(.system(size: 9 * scale, weight: .medium, design: .serif)).tracking(scale).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(displayBookTitle(edition)).font(.system(size: 22 * scale, weight: .medium, design: .serif)).lineLimit(4).minimumScaleFactor(0.65).fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(palette.1.opacity(0.5)).frame(width: 36 * scale, height: 1)
                Image(systemName: "leaf").font(.system(size: 22 * scale, weight: .ultraLight))
                Spacer(minLength: 0)
                Text(L("B O O K R E I G N")).font(.system(size: 7 * scale, weight: .medium))
            }.foregroundStyle(palette.1).multilineTextAlignment(.center).padding(16 * scale)
        }
    }
}

struct EmptyLibraryView: View {
    var title: String
    var message: String
    var symbol = "books.vertical"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 48, weight: .light)).foregroundStyle(Color.forest).padding(.bottom, 10)
            Text(title).font(.system(.title2, design: .serif, weight: .medium))
            Text(message).font(.subheadline).foregroundStyle(Color.archiveSecondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(ArchivePrimaryButtonStyle()).padding(.top, 8) }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LocationChip: View {
    var text: String
    var symbol = "mappin.and.ellipse"
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(Color.forest)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(Color.forest.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }
}

@MainActor
func displayBookTitle(_ edition: BookEdition) -> String {
    edition.hasPlaceholderTitle ? L("Книга · \(edition.isbn)") : edition.title
}

@MainActor
func locationIconName(_ symbol: String) -> String {
    switch symbol {
    case "house": L("Дом")
    case "tree": L("Дерево")
    case "building.2": L("Здание")
    case "books.vertical": L("Книги")
    case "archivebox": L("Коробка")
    case "briefcase": L("Портфель")
    case "heart": L("Сердце")
    default: symbol
    }
}
