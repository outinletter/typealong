import SwiftUI
import UIKit
import GameController

/// 숨은 입력창을 직접 켜고 끄는 컨트롤러. 키보드 버튼과 아이콘 상태가 이것을 쓴다.
@MainActor
final class TypingController: ObservableObject {
    weak var field: UITextField? { didSet { applyHardware() } }
    @Published var isActive = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.applyHardware() }
            })
        }
    }

    /// 무선 키보드가 연결돼 있으면 팝업 키보드를 띄우지 않는다(입력창은 계속 키를 받는다).
    func applyHardware() {
        guard let f = field else { return }
        let hw = GCKeyboard.coalesced != nil
        let wasActive = f.isFirstResponder
        f.inputView = hw ? UIView(frame: .zero) : nil
        f.inputAccessoryView = hw ? nil : keyboardBar()
        if wasActive { f.reloadInputViews() }
    }

    /// 키보드 팝업 오른쪽 위에 놓는 '키보드 닫기' 아이콘 줄
    private func keyboardBar() -> UIView {
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 40))
        bar.autoresizingMask = .flexibleWidth
        bar.backgroundColor = .clear
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        b.tintColor = UIColor(Color.taText)
        b.backgroundColor = UIColor(Color.taPanel).withAlphaComponent(0.95)
        b.layer.cornerRadius = 10
        b.frame = CGRect(x: 320 - 62, y: 2, width: 54, height: 34)
        b.autoresizingMask = .flexibleLeftMargin
        b.accessibilityLabel = "키보드 닫기"
        b.addAction(UIAction { [weak self] _ in self?.hide() }, for: .touchUpInside)
        bar.addSubview(b)
        return bar
    }

    func show() { field?.becomeFirstResponder() }
    func hide() { field?.resignFirstResponder() }
    func toggle() { (field?.isFirstResponder ?? false) ? hide() : show() }
}

/// 무선·하드웨어 키보드의 키를 입력 언어(한/영)와 상관없이 물리 키 위치로 직접 받는 입력창.
/// 한글 입력 상태나 입력기 조합 때문에 영문이 들어오지 않는 문제를 피하려고,
/// 하드웨어 키는 텍스트 입력 시스템을 거치지 않고 여기서 바로 글자로 바꾼다.
final class EnglishTextField: UITextField {
    var onChar: ((Character) -> Void)?
    var onBackspace: (() -> Void)?
    var onReturn: (() -> Void)?
    var onSpace: (() -> Void)?

    private static let punctuation: [Int: (String, String)] = [
        0x2D: ("-", "_"), 0x2E: ("=", "+"), 0x2F: ("[", "{"), 0x30: ("]", "}"), 0x31: ("\\", "|"),
        0x33: (";", ":"), 0x34: ("'", "\""), 0x35: ("`", "~"), 0x36: (",", "<"), 0x37: (".", ">"), 0x38: ("/", "?"),
    ]
    private static let digits = Array("1234567890")
    private static let shiftedDigits = Array("!@#$%^&*()")

    /// 이 키가 입력할 글자(US 배열 기준). 글자가 아닌 키는 nil.
    private func character(for key: UIKey) -> Character? {
        let raw = key.keyCode.rawValue
        let shift = key.modifierFlags.contains(.shift)
        let caps = key.modifierFlags.contains(.alphaShift)
        if (0x04...0x1D).contains(raw) {
            let lower = Character(UnicodeScalar(UInt8(97 + raw - 0x04)))
            return (shift != caps) ? Character(String(lower).uppercased()) : lower
        }
        if (0x1E...0x27).contains(raw) {
            let i = raw - 0x1E
            return shift ? Self.shiftedDigits[i] : Self.digits[i]
        }
        if let p = Self.punctuation[raw] { return Character(shift ? p.1 : p.0) }
        return nil
    }

    private func isShortcut(_ key: UIKey) -> Bool {
        let m = key.modifierFlags
        return m.contains(.command) || m.contains(.control) || m.contains(.alternate)
    }

    /// 이 키를 우리가 직접 처리하는가(처리하면 시스템 쪽에는 넘기지 않는다).
    private func handles(_ press: UIPress) -> Bool {
        guard let key = press.key, !isShortcut(key) else { return false }
        switch key.keyCode {
        case .keyboardSpacebar, .keyboardDeleteOrBackspace, .keyboardReturnOrEnter, .keyboardTab, .keyboardEscape,
             .keyboardUpArrow, .keyboardDownArrow, .keyboardLeftArrow, .keyboardRightArrow:
            return true
        default:
            return character(for: key) != nil
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var rest = Set<UIPress>()
        for p in presses {
            guard handles(p), let key = p.key else { rest.insert(p); continue }
            switch key.keyCode {
            case .keyboardSpacebar: onSpace?()
            case .keyboardDeleteOrBackspace: onBackspace?()
            case .keyboardReturnOrEnter: onReturn?()
            case .keyboardTab, .keyboardEscape, .keyboardUpArrow, .keyboardDownArrow, .keyboardLeftArrow, .keyboardRightArrow:
                break // Tab·방향키는 화면 버튼의 포커스를 옮기므로 무시
            default:
                if let ch = character(for: key) { onChar?(ch) }
            }
        }
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { !handles($0) }
        if !rest.isEmpty { super.pressesChanged(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { !handles($0) }
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { !handles($0) }
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }
}

/// 화면에 보이지 않는 입력창. 소프트·하드 키보드의 글자와 지우기를 모두 받는다.
struct TypingInput: UIViewRepresentable {
    let controller: TypingController
    var onChar: (Character) -> Void
    var onBackspace: () -> Void
    var onReturn: () -> Void

    private static let sentinel = "\u{200B}"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let f = EnglishTextField()
        f.delegate = context.coordinator
        f.text = Self.sentinel // 비어 있으면 Backspace가 전달되지 않아 더미 글자를 둔다
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.smartQuotesType = .no
        f.smartDashesType = .no
        f.smartInsertDeleteType = .no
        f.inlinePredictionType = .no
        f.keyboardType = .asciiCapable
        f.returnKeyType = .next
        f.inputAssistantItem.leadingBarButtonGroups = []
        f.inputAssistantItem.trailingBarButtonGroups = []
        f.onChar = { [weak coordinator = context.coordinator] c in coordinator?.parent.onChar(c) }
        f.onSpace = { [weak coordinator = context.coordinator] in coordinator?.parent.onChar(" ") }
        f.onBackspace = { [weak coordinator = context.coordinator] in coordinator?.parent.onBackspace() }
        f.onReturn = { [weak coordinator = context.coordinator] in coordinator?.parent.onReturn() }
        controller.field = f
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { f.becomeFirstResponder() }
        return f
    }

    func updateUIView(_ f: UITextField, context: Context) {
        context.coordinator.parent = self
        controller.field = f
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TypingInput
        init(_ parent: TypingInput) { self.parent = parent }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async { self.parent.controller.isActive = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            DispatchQueue.main.async { self.parent.controller.isActive = false }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty { parent.onBackspace() }
            else { for c in string { parent.onChar(c) } }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            return false
        }
    }
}
