import SwiftUI
import UIKit

/// Apply the choice to this scene's window, including its presented sheets.
/// Using .unspecified also restores live system appearance after an override.
struct AppearanceWindowBridge: UIViewRepresentable {
    var appearance: AppAppearance

    func makeUIView(context: Context) -> WindowStyleView {
        let view = WindowStyleView()
        view.style = appearance.interfaceStyle
        return view
    }

    func updateUIView(_ uiView: WindowStyleView, context: Context) {
        uiView.style = appearance.interfaceStyle
    }

    final class WindowStyleView: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { applyStyle() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyStyle()
        }

        private func applyStyle() {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }
}

private extension AppAppearance {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}
