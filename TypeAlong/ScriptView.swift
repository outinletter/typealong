import SwiftUI

struct ScriptView: View {
    @ObservedObject var store: Store
    var onTapLine: (Int) -> Void
    var onTapChar: (Int, Int) -> Void
    var onWord: (Int, String) -> Void
    var onSeek: (Int) -> Void

    @State private var topRow: String?
    private let anchor = UnitPoint(x: 0.5, y: 0.0)

    /// 맨 위에는 방금 친 이전 문장(한글 번역 포함)을 두고, 현재 문장은 그 바로 아래에 둔다.
    private func topID(_ cur: Int) -> String { "l\(max(cur - 1, 0))" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.rows) { row in
                        switch row {
                        case .minute(let m):
                            MinuteMarker(minute: m)
                                .id(row.id)
                                .onTapGesture { onSeek(m * 60) }
                        case .line(let i):
                            LineView(line: store.lines[i], typed: store.typed[i],
                                     isCurrent: i == store.cur, fontSize: store.fontSize, showKo: store.showKorean,
                                     ignoreCase: store.ignoreCase, fontStyle: store.fontStyle,
                                     saved: store.savedWordIDs,
                                     onSeek: { if let t = store.lines[i].t { onSeek(t) } },
                                     onTapChar: { onTapChar(i, $0) },
                                     onWord: { onWord(i, $0) })
                                .equatable()
                                .id(row.id)
                                .onTapGesture { onTapLine(i) }
                        }
                    }
                    if store.isFinished {
                        Text("🎉 끝까지 완주했습니다!")
                            .font(.title3.bold()).foregroundStyle(Color.taMain)
                            .frame(maxWidth: .infinity).padding(.top, 24)
                    }
                    Color.clear.frame(height: 700)
                }
                .scrollTargetLayout()
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
            .scrollPosition(id: $topRow, anchor: .top)
            .onChange(of: topRow) { _, id in
                if let id, id.hasPrefix("l"), let n = Int(id.dropFirst()) { store.noteView(n) }
            }
            .scrollDismissesKeyboard(.never)
            .onAppear {
                if let v = store.viewLine { proxy.scrollTo("l\(v)", anchor: anchor) }
                else { proxy.scrollTo(topID(store.cur), anchor: anchor) }
            }
            .onChange(of: store.cur) { _, c in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(topID(c), anchor: anchor) }
            }
            .onChange(of: store.fontSize) { _, _ in proxy.scrollTo(topID(store.cur), anchor: anchor) }
            .onChange(of: store.current.id) { _, _ in proxy.scrollTo(topID(store.cur), anchor: anchor) }
        }
    }
}

struct MinuteMarker: View {
    let minute: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(minute)분 · \(formatTime(minute * 60))")
                .font(.footnote.bold().monospacedDigit())
                .foregroundStyle(Color.taMain)
            Rectangle().fill(Color.taLine).frame(height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 16).padding(.bottom, 4)
        .contentShape(Rectangle())
    }
}

struct LineView: View, Equatable {
    let line: ScriptLine
    let typed: String
    let isCurrent: Bool
    let fontSize: Double
    let showKo: Bool
    let ignoreCase: Bool
    let fontStyle: Store.FontStyle
    let saved: Set<String>
    var onSeek: (() -> Void)? = nil
    let onTapChar: (Int) -> Void
    let onWord: (String) -> Void

    static func == (a: LineView, b: LineView) -> Bool {
        a.line == b.line && a.typed == b.typed && a.isCurrent == b.isCurrent && a.fontSize == b.fontSize
            && a.showKo == b.showKo && a.ignoreCase == b.ignoreCase && a.fontStyle == b.fontStyle && a.saved == b.saved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TappableText(text: attributed, onTap: onTapChar, onLongPress: { idx in
                if let w = word(at: idx) { onWord(w) }
            }, prefix: stampLength, onStamp: onSeek)
            if showKo, !line.ko.isEmpty {
                Text(line.ko)
                    .font(.system(size: fontSize))
                    .foregroundStyle(Color.taKo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(isCurrent ? Color.white.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .opacity(isCurrent || typed.count >= line.en.count ? 1 : 0.95)
        .contentShape(Rectangle())
    }

    private var uiFont: UIFont {
        let size = CGFloat(fontSize)
        switch fontStyle {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .sans: return .systemFont(ofSize: size)
        case .rounded, .serif:
            let base = UIFont.systemFont(ofSize: size)
            let d = base.fontDescriptor.withDesign(fontStyle == .rounded ? .rounded : .serif) ?? base.fontDescriptor
            return UIFont(descriptor: d, size: size)
        }
    }

    private static let wordRegex = try! NSRegularExpression(pattern: "[A-Za-z]+(?:'[A-Za-z]+)?")

    /// 문장 안에서 `index` 위치의 영어 단어(없으면 nil)
    private func word(at index: Int) -> String? {
        let ns = line.en as NSString
        for m in Self.wordRegex.matches(in: line.en, range: NSRange(location: 0, length: ns.length)) {
            if index >= m.range.location && index <= m.range.location + m.range.length { return ns.substring(with: m.range) }
        }
        return nil
    }

    /// 문장 앞 타임스탬프(이미지 1글자 + 공백)
    private var stampLength: Int { (line.t != nil && onSeek != nil) ? 2 : 0 }

    private var stampText: NSAttributedString? {
        guard let t = line.t, onSeek != nil else { return nil }
        let caption = "▶ " + formatTime(t)
        let size = max(11, fontSize * 0.62)
        let f = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        let textW = (caption as NSString).size(withAttributes: [.font: f]).width
        let h = ceil(size * 1.55), w = ceil(textW) + 14
        let main = UIColor(Color.taMain)
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in
            let path = UIBezierPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1), cornerRadius: 5)
            main.withAlphaComponent(0.16).setFill(); path.fill()
            main.withAlphaComponent(0.35).setStroke(); path.lineWidth = 1; path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: main]
            let sz = (caption as NSString).size(withAttributes: attrs)
            let px: CGFloat = (w - sz.width) * 0.5
            let py: CGFloat = (h - sz.height) * 0.5
            (caption as NSString).draw(at: CGPoint(x: px, y: py), withAttributes: attrs)
        }
        let att = NSTextAttachment()
        att.image = img
        att.bounds = CGRect(x: 0, y: (uiFont.capHeight - h) / CGFloat(2), width: w, height: h)
        let para = NSMutableParagraphStyle(); para.lineSpacing = 5
        let out = NSMutableAttributedString(attachment: att)
        out.append(NSAttributedString(string: " ", attributes: [.font: uiFont, .paragraphStyle: para]))
        out.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: out.length))
        return out
    }

    private var attributed: NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 5
        let font = uiFont
        let ok = UIColor(Color.taText), bad = UIColor(Color.taBad), dim = UIColor(Color.taDim), caret = UIColor(Color.taMain)
        let out = NSMutableAttributedString()
        let target = Array(line.en)
        let tc = Array(typed)
        for (i, ch) in target.enumerated() {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
            if i < tc.count {
                if Store.same(tc[i], ch, ignoreCase: ignoreCase) {
                    attrs[.foregroundColor] = ok
                } else {
                    attrs[.foregroundColor] = bad
                    if ch == " " { attrs[.backgroundColor] = bad.withAlphaComponent(0.35) }
                }
            } else {
                attrs[.foregroundColor] = dim
                if isCurrent && i == tc.count {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    attrs[.underlineColor] = caret
                }
            }
            out.append(NSAttributedString(string: String(ch), attributes: attrs))
        }
        // 단어장에 저장한 단어는 은은하게 표시한다.
        let ns = line.en as NSString
        for m in Self.wordRegex.matches(in: line.en, range: NSRange(location: 0, length: ns.length)) {
            if saved.contains(ns.substring(with: m.range).lowercased()) {
                out.addAttribute(.backgroundColor, value: caret.withAlphaComponent(0.22), range: m.range)
            }
        }
        if let stamp = stampText { out.insert(stamp, at: 0) }
        return out
    }
}
