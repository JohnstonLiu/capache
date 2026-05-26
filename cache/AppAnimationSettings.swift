import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppAnimationSettings {
    static var defaultDisableAnimations: Bool {
#if targetEnvironment(macCatalyst)
        true
#else
        false
#endif
    }
}

private struct AppAnimationPolicyModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldDisableAnimations: Bool {
        AppAnimationSettings.defaultDisableAnimations || reduceMotion
    }

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                guard shouldDisableAnimations else { return }
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .onAppear(perform: applyUIKitPolicy)
            .onChange(of: shouldDisableAnimations) { _, _ in
                applyUIKitPolicy()
            }
    }

    private func applyUIKitPolicy() {
#if canImport(UIKit)
        UIView.setAnimationsEnabled(!shouldDisableAnimations)
#endif
    }
}

extension View {
    func appAnimationPolicy() -> some View {
        modifier(AppAnimationPolicyModifier())
    }
}
