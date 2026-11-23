import SwiftUI

struct ScriptLine: Codable, Hashable {
    var t: Int?
    var en: String
    var ko: String
    var est: Bool? = nil   // 문장 시각이 추정값(≈)일 때
}

struct Script: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var channel: String
    var youtubeID: String?
    var lines: [ScriptLine]
}

/// 단어장에 저장한 단어
struct VocabWord: Codable, Identifiable, Hashable {
    var id: String          // 소문자로 바꾼 단어(중복 방지 키)
    var word: String
    var meaning: String?    // 한글 뜻(기기 내 번역, 없을 수 있음)
    var sentence: String    // 단어가 나온 영어 문장
    var sentenceKo: String  // 그 문장의 한글 번역(있을 때)
    var scriptTitle: String
    var youtubeID: String?
    var time: Int?
    var added: Date
}

enum VocabAddResult { case added, exists, invalid }

struct Progress: Codable {
    var typed: [String]
    var cur: Int
    var correct: Int
    var keys: Int
    var activeSeconds: Double
    var view: Int? = nil   // 마지막으로 보던 화면의 맨 위 문장
}

enum ScriptRow: Identifiable {
    case minute(Int)
    case line(Int)

    var id: String {
        switch self {
        case .minute(let m): return "m\(m)"
        case .line(let i): return "l\(i)"
        }
    }
}

func formatTime(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

extension Color {
    static let taBG = Color(red: 0.16, green: 0.19, blue: 0.28)
    static let taBGTop = Color(red: 0.20, green: 0.24, blue: 0.36)
    static let taPanel = Color(red: 0.23, green: 0.27, blue: 0.40)
    static let taLine = Color(red: 0.32, green: 0.37, blue: 0.52)
    static let taDim = Color(red: 0.72, green: 0.77, blue: 0.90)
    static let taText = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let taKo = Color(red: 0.76, green: 0.81, blue: 0.90)
    static let taMain = Color(red: 0.95, green: 0.88, blue: 0.64) // 연한 파스텔 노랑
    static let taBad = Color(red: 0.79, green: 0.28, blue: 0.33)
}

/// 붙여넣은 텍스트를 연습용 문장으로 바꾼다.
enum ScriptParser {
    static func youtubeID(from text: String) -> String? {
        let patterns = ["v=([\\w-]{11})", "youtu\\.be/([\\w-]{11})", "embed/([\\w-]{11})", "shorts/([\\w-]{11})"]
        for p in patterns {
            guard let r = try? NSRegularExpression(pattern: p),
                  let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  m.numberOfRanges > 1,
                  let range = Range(m.range(at: 1), in: text) else { continue }
            return String(text[range])
        }
        return nil
    }

    /// 키보드로 칠 수 있는 ASCII 문자만 남긴다.
    static func clean(_ raw: String) -> String {
        let s = raw.replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: ">>", with: " ")
        let map: [Character: String] = [
            "\u{2018}": "'", "\u{2019}": "'", "\u{201C}": "\"", "\u{201D}": "\"",
            "\u{2026}": "...", "\u{2013}": "-", "\u{2014}": "-", "\u{00A0}": " ",
        ]
        var out = ""
        for ch in s {
            if let m = map[ch] { out += m }
            else if let a = ch.asciiValue, a >= 32, a < 127 { out.append(ch) }
        }
        return out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    static func timestamp(_ line: String) -> Int? {
        let parts = line.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isNumber) }) else { return nil }
        return parts.reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }

    private static func isSecondsLabel(_ l: String) -> Bool {
        l.range(of: "^\\d+\\s*(초|seconds?|minutes?|분)", options: .regularExpression) != nil
    }

    private static func splitSentences(_ text: String) -> [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s { out.append(s) }
        }
        return out.isEmpty ? [text] : out
    }

    private static func nonEmptyLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func lines(en: String, ko: String) -> [ScriptLine] {
        let raw = nonEmptyLines(en)
        let hasTimestamps = raw.contains { timestamp($0) != nil }
        let source = (!hasTimestamps && raw.count <= 2) ? splitSentences(raw.joined(separator: " ")) : raw
        let koLines = nonEmptyLines(ko)

        var out: [ScriptLine] = []
        var t: Int?
        for l in source {
            if let ts = timestamp(l) { t = ts; continue }
            if isSecondsLabel(l) { continue }
            let e = clean(l)
            if e.isEmpty { continue }
            out.append(ScriptLine(t: hasTimestamps ? t : nil, en: e, ko: ""))
            t = nil
        }
        for i in out.indices where i < koLines.count { out[i].ko = koLines[i] }
        return hasTimestamps ? splitIntoSentences(out) : out
    }

    /// 자막 덩어리를 문장 단위로 다시 묶는다(WordAhead 방식).
    /// 단어마다 시각을 덩어리 길이에 비례해 추정하고, 문장 끝 부호(약어 제외)에서 끊는다.
    /// 문장은 덩어리 경계를 넘을 수 있고, 시각은 첫 단어 기준(덩어리 중간이면 추정 ≈)이다.
    static func splitIntoSentences(_ segs: [ScriptLine]) -> [ScriptLine] {
        struct W { var text: String; var t: Double; var est: Bool }
        var words: [W] = []
        var starts: [Int] = []   // 각 덩어리의 첫 단어 위치
        for (i, seg) in segs.enumerated() {
            guard let t0 = seg.t else { return segs }   // 시각이 없는 스크립트는 그대로
            let parts = seg.en.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !parts.isEmpty else { continue }
            let next = segs[(i + 1)...].compactMap(\.t).first.map(Double.init)
            let start = Double(t0)
            let end = (next.map { $0 > start ? $0 : nil } ?? nil) ?? start + Double(parts.count) / 2.5
            starts.append(words.count)
            for (k, w) in parts.enumerated() {
                words.append(W(text: w, t: start + (end - start) * Double(k) / Double(parts.count), est: k > 0))
            }
        }
        let abbr = try? NSRegularExpression(pattern: "(?:\\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|St|vs|etc)|\\b[A-Z])\\.$", options: .caseInsensitive)
        let enders = try? NSRegularExpression(pattern: "[.!?][\"'”’\\])]*$")
        func isEnd(_ w: String) -> Bool {
            let r = NSRange(w.startIndex..., in: w)
            return enders?.firstMatch(in: w, range: r) != nil && abbr?.firstMatch(in: w, range: r) == nil
        }
        var out: [ScriptLine] = []
        var cur: [W] = []
        func flush() {
            guard let first = cur.first else { return }
            let text = clean(cur.map(\.text).joined(separator: " "))
            if !text.isEmpty { out.append(ScriptLine(t: Int(first.t), en: text, ko: "", est: first.est ? true : nil)) }
            cur = []
        }
        for w in words { cur.append(w); if isEnd(w.text) { flush() } }
        flush()
        // 덩어리가 그대로 한 문장이면 기존 한글 번역을 유지
        if out.count == segs.count { for i in out.indices { out[i].ko = segs[i].ko; out[i].est = nil } }
        return out
    }
}
