import SwiftUI
import UIKit

extension View {
    /// iOS 26 이상에서는 Liquid Glass, 그 이전에는 단색 패널로 그린다.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(tint ?? Color.taPanel, in: shape)
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: false), in: Capsule())
        } else {
            self.background(tint ?? Color.taPanel, in: Capsule())
        }
    }

    @available(iOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// 여러 유리 요소를 한 묶음으로 그려 서로 자연스럽게 어울리게 한다(iOS 26 이상).
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// 숨긴 내비게이션 바에서도 화면 왼쪽 가장자리를 밀어 이전 화면으로 돌아가게 한다.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
