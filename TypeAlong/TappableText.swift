import SwiftUI
import UIKit

/// 글자를 탭한 위치(문자 번호)를 알려 주는 읽기 전용 텍스트.
struct TappableText: UIViewRepresentable {
    let text: NSAttributedString
    let onTap: (Int) -> Void
    var onLongPress: (Int) -> Void = { _ in }
    var prefix = 0            // 앞에 붙인 타임스탬프 글자 수(탭 위치 보정)
    var onStamp: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var onTap: (Int) -> Void = { _ in }
        var onLongPress: (Int) -> Void = { _ in }
        var prefix = 0
        var onStamp: (() -> Void)?

        @objc func pressed(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let tv = g.view as? UITextView else { return }
            guard let pos = tv.closestPosition(to: g.location(in: tv)) else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let i = tv.offset(from: tv.beginningOfDocument, to: pos)
            if i >= prefix { onLongPress(i - prefix) }
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let tv = g.view as? UITextView else { return }
            let point = g.location(in: tv)
            guard let pos = tv.closestPosition(to: point) else { return }
            let i = tv.offset(from: tv.beginningOfDocument, to: pos)
            if i < prefix { onStamp?() } else { onTap(i - prefix) }
        }
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0.45
        tv.addGestureRecognizer(press)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.prefix = prefix
        context.coordinator.onStamp = onStamp
        if !tv.attributedText.isEqual(to: text) { tv.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 320
        let s = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        return CGSize(width: w, height: ceil(s.height))
    }
}
