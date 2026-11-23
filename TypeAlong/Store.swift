import SwiftUI
import Translation

@MainActor
final class Store: ObservableObject {
    enum VideoMode: String { case compact, large, hidden }

    struct ImportJob: Identifiable {
        let id = UUID()
        let videoID: String
        var status: String
        var failed = false
    }

    struct TranslationRequest: Equatable {
        let scriptID: String
        let texts: [String]
    }

    /// 영어 문장에 쓰는 글꼴
    enum FontStyle: String, CaseIterable {
        case mono, sans, rounded, serif

        var title: String {
            switch self {
            case .mono: return "Monospaced"
            case .sans: return "Sans"
            case .rounded: return "Rounded"
            case .serif: return "Serif"
            }
        }

        var design: Font.Design {
            switch self {
            case .mono: return .monospaced
            case .sans: return .default
            case .rounded: return .rounded
            case .serif: return .serif
            }
        }
    }

    /// 목록에 없는 빈 자리표시(저장한 영상이 없을 때 현재 스크립트로 쓴다). 기본 제공 영상은 없다.
    let base = Script(id: "empty", title: "", channel: "", youtubeID: nil, lines: [])
    @Published private(set) var scripts: [Script]
    @Published private(set) var current: Script
    @Published private(set) var rows: [ScriptRow] = []
    @Published private(set) var libraryTick = 0
    @Published private(set) var jobs: [ImportJob] = []
    @Published private(set) var translating: Set<String> = []
    @Published private(set) var translationRequest: TranslationRequest?
    @Published var banner: String?
    @Published private(set) var vocab: [VocabWord] = []
    private var translationQueue: [TranslationRequest] = []
    private var daily: [String: Int] = [:]
    @Published private(set) var typed: [String] = []
    @Published private(set) var cur = 0
    @Published private(set) var correct = 0
    @Published private(set) var keys = 0
    @Published private(set) var activeSeconds = 0.0

    @Published var showKorean: Bool { didSet { defaults.set(showKorean, forKey: "showKorean") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var videoMode: VideoMode { didSet { defaults.set(videoMode.rawValue, forKey: "videoMode") } }
    @Published var fontStyle: FontStyle { didSet { defaults.set(fontStyle.rawValue, forKey: "fontStyle") } }
    @Published var ignoreCase: Bool { didSet { defaults.set(ignoreCase, forKey: "ignoreCase") } }

    private var customs: [Script]
    private var lastKey: Date?
    private var saveItem: DispatchWorkItem?
    private var defaults: UserDefaults { .standard }

    init() {
        let d = UserDefaults.standard
        var customs: [Script] = []
        if let data = d.data(forKey: "customScripts"),
           let list = try? JSONDecoder().decode([Script].self, from: data) { customs = list }
        // 이전 방식(자막 덩어리 단위)으로 저장된 스크립트를 문장 단위로 한 번 다시 나눈다.
        var migrated = false
        for i in customs.indices where !d.bool(forKey: "sentences_v1_" + customs[i].id) {
            d.set(true, forKey: "sentences_v1_" + customs[i].id)
            let old = customs[i].lines
            let new = ScriptParser.splitIntoSentences(old)
            guard new.count != old.count else { continue }
            if let data = d.data(forKey: "progress_" + customs[i].id),
               let p = try? JSONDecoder().decode(Progress.self, from: data), old.indices.contains(p.cur) {
                let t = old[p.cur].t ?? 0
                let nc = new.firstIndex { ($0.t ?? 0) >= t } ?? max(new.count - 1, 0)
                let typed = new.indices.map { $0 < nc ? new[$0].en : "" }
                let np = Progress(typed: typed, cur: nc, correct: p.correct, keys: p.keys, activeSeconds: p.activeSeconds, view: nil)
                if let out = try? JSONEncoder().encode(np) { d.set(out, forKey: "progress_" + customs[i].id) }
            }
            customs[i].lines = new
            migrated = true
        }
        if migrated, let data = try? JSONEncoder().encode(customs) { d.set(data, forKey: "customScripts") }
        let all = customs
        let id = d.string(forKey: "currentScript")

        self.customs = customs
        self.scripts = all
        self.current = all.first { $0.id == id } ?? Script(id: "empty", title: "", channel: "", youtubeID: nil, lines: [])
        self.showKorean = d.object(forKey: "showKorean") as? Bool ?? true
        self.fontSize = d.object(forKey: "fontSize") as? Double ?? 17
        self.videoMode = VideoMode(rawValue: d.string(forKey: "videoMode") ?? "") ?? .compact
        self.ignoreCase = d.object(forKey: "ignoreCase") as? Bool ?? true
        self.fontStyle = FontStyle(rawValue: d.string(forKey: "fontStyle") ?? "") ?? .mono
        loadProgress()
        daily = d.dictionary(forKey: "dailyChars") as? [String: Int] ?? [:]
        if let data = d.data(forKey: "vocab"), let list = try? JSONDecoder().decode([VocabWord].self, from: data) { vocab = list }
    }

    // MARK: 통계
    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var todayChars: Int { daily[Self.dayKey(Date())] ?? 0 }

    /// 오늘(아직 안 쳤으면 어제)부터 이어진 연속 연습 일수
    var streakDays: Int {
        let cal = Calendar.current
        var day = Date()
        if (daily[Self.dayKey(day)] ?? 0) == 0 { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while (daily[Self.dayKey(day)] ?? 0) > 0 {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }

    var lines: [ScriptLine] { current.lines }
    var wpm: Int { activeSeconds > 3 ? Int((Double(correct) / 5) / (activeSeconds / 60)) : 0 }
    var accuracy: Int { keys == 0 ? 100 : Int((Double(correct) / Double(keys) * 100).rounded()) }
    var progressPercent: Int {
        let total = lines.reduce(0) { $0 + $1.en.count }
        guard total > 0 else { return 0 }
        return typed.reduce(0) { $0 + $1.count } * 100 / total
    }
    var isFinished: Bool {
        cur == lines.count - 1 && typed.last.map { $0.count >= lines[cur].en.count } == true
    }

    // MARK: 입력
    nonisolated static func same(_ a: Character, _ b: Character, ignoreCase: Bool) -> Bool {
        a == b || (ignoreCase && a.lowercased() == b.lowercased())
    }

    func input(_ ch: Character) {
        guard let a = ch.asciiValue, a >= 32, a < 127, !lines.isEmpty else { return }
        let target = Array(lines[cur].en)
        var t = typed[cur]
        guard t.count < target.count else { return }

        let now = Date()
        if let last = lastKey, now.timeIntervalSince(last) < 5 { activeSeconds += now.timeIntervalSince(last) }
        lastKey = now

        keys += 1
        daily[Self.dayKey(now), default: 0] += 1
        if Store.same(ch, target[t.count], ignoreCase: ignoreCase) { correct += 1 }
        t.append(ch)
        typed[cur] = t
        if t.count >= target.count, cur < lines.count - 1 { cur += 1 }
        scheduleSave()
    }

    func backspace() {
        guard !lines.isEmpty else { return }
        if !typed[cur].isEmpty {
            typed[cur].removeLast()
        } else if cur > 0 {
            cur -= 1
            if !typed[cur].isEmpty { typed[cur].removeLast() }
        }
        scheduleSave()
    }

    func advance() {
        guard !lines.isEmpty else { return }
        if typed[cur].count >= lines[cur].en.count, cur < lines.count - 1 { cur += 1; scheduleSave() }
    }

    /// 마지막으로 보던 화면의 맨 위 문장(화면을 다시 열 때 복원)
    var viewLine: Int?
    func noteView(_ i: Int) {
        guard viewLine != i else { return }
        viewLine = i
        scheduleSave()
    }

    func goTo(_ i: Int) {
        guard lines.indices.contains(i) else { return }
        cur = i
        scheduleSave()
    }

    /// 문장의 `index`번째 글자 앞에서 이어 치도록 커서를 옮긴다.
    /// 앞으로 건너뛴 글자는 친 것으로 채우되(통계에는 넣지 않음), 뒤로 가면 그 지점부터 다시 친다.
    func place(line i: Int, at index: Int) {
        guard lines.indices.contains(i) else { return }
        let target = Array(lines[i].en)
        let k = min(max(index, 0), target.count)
        let have = typed[i].count
        if k < have { typed[i] = String(typed[i].prefix(k)) }
        else if k > have { typed[i] += String(target[have..<k]) }
        cur = i
        scheduleSave()
    }

    func reset() {
        typed = Array(repeating: "", count: lines.count)
        cur = 0; correct = 0; keys = 0; activeSeconds = 0; viewLine = nil
        saveNow()
    }

    // MARK: 스크립트 관리
    /// 목록에서 열었을 때: 최근 연 순서를 기록하고 그 스크립트를 불러온다.
    func select(_ id: String) {
        touch(id)
        guard let s = scripts.first(where: { $0.id == id }), s.id != current.id else { return }
        saveNow()
        current = s
        defaults.set(s.id, forKey: "currentScript")
        loadProgress()
    }

    /// 실패하면 오류 문구를 돌려준다.
    func addScript(url: String, title: String, english: String, korean: String) -> String? {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let yt = ScriptParser.youtubeID(from: trimmedURL)
        if !trimmedURL.isEmpty && yt == nil { return "유튜브 주소를 인식하지 못했습니다." }
        let ls = ScriptParser.lines(en: english, ko: korean)
        if ls.isEmpty { return "영어 스크립트를 붙여넣어 주세요." }
        let name = title.trimmingCharacters(in: .whitespaces)
        let s = Script(id: "c\(Int(Date().timeIntervalSince1970))", title: name.isEmpty ? (yt.map { "유튜브 \($0)" } ?? "내 스크립트") : name,
                       channel: "내 스크립트", youtubeID: yt, lines: ls)
        customs.append(s)
        scripts = customs
        persistCustoms()
        touch(s.id)
        if let yt { Task { _ = await ThumbnailCache.image(for: yt) } } // 오프라인에서도 보이도록 미리 저장
        return nil
    }

    /// 기본 제공 목록을 내 목록에 추가한다(이미 있으면 그대로 둔다).
    func addCatalog(_ s: Script) {
        if !scripts.contains(where: { $0.id == s.id }) {
            customs.append(s)
            scripts = customs
            persistCustoms()
        }
        touch(s.id)
    }

    func deleteCurrent() { delete(current) }

    func delete(_ s: Script) {
        guard s.id != base.id else { return }
        defaults.removeObject(forKey: "progress_" + s.id)
        customs.removeAll { $0.id == s.id }
        scripts = customs
        persistCustoms()
        if current.id == s.id {
            current = base
            defaults.set(base.id, forKey: "currentScript")
            loadProgress()
        }
        libraryTick += 1
    }

    // MARK: 공유로 받은 유튜브 링크 → 자동 수집·저장
    func importShared(_ rawURL: String) {
        guard let yt = ScriptParser.youtubeID(from: rawURL) else { return }
        if let existing = scripts.first(where: { $0.youtubeID == yt }) {
            touch(existing.id)
            showBanner("이미 저장된 영상입니다: \(existing.title)")
            return
        }
        if jobs.contains(where: { $0.videoID == yt && !$0.failed }) { return }
        jobs.removeAll { $0.videoID == yt } // 이전 실패 기록 정리
        let job = ImportJob(videoID: yt, status: "자막 가져오는 중…")
        jobs.append(job)

        Task {
            do {
                let r = try await TranscriptFetcher().fetch(videoID: yt)
                let lsRaw = r.segments
                    .map { ScriptLine(t: $0.t, en: ScriptParser.clean($0.text), ko: $0.ko) }
                    .filter { !$0.en.isEmpty }
                let ls = ScriptParser.splitIntoSentences(lsRaw)
                guard !ls.isEmpty else { throw TranscriptFetcher.FetchError(message: "이 영상에서 스크립트를 찾지 못했습니다.") }
                let s = Script(id: "c\(Int(Date().timeIntervalSince1970 * 1000))",
                               title: r.title.isEmpty ? "유튜브 \(yt)" : r.title,
                               channel: r.author.isEmpty ? "내 스크립트" : r.author,
                               youtubeID: yt, lines: ls)
                customs.append(s)
                scripts = customs
                persistCustoms()
                touch(s.id)
                Task { _ = await ThumbnailCache.image(for: yt) }
                jobs.removeAll { $0.id == job.id }
                showBanner("저장했습니다: \(s.title)")
                if needsKorean(s) { requestTranslation(for: s) } // 한글 자막이 이미 있으면 번역하지 않는다
            } catch {
                if let i = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[i].status = error.localizedDescription
                    jobs[i].failed = true
                }
            }
        }
    }

    func dismissJob(_ id: UUID) { jobs.removeAll { $0.id == id } }

    func showBanner(_ text: String) {
        banner = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if banner == text { banner = nil }
        }
    }

    // MARK: 자동 번역(iOS 18 이상, 기기 내 번역)
    /// 한글이 절반 넘게 비어 있으면 번역이 필요하다.
    func needsKorean(_ s: Script) -> Bool {
        s.id != base.id && s.lines.filter { $0.ko.isEmpty }.count * 2 > s.lines.count
    }

    func requestTranslation(for s: Script) {
        guard #available(iOS 18.0, *), !translating.contains(s.id) else { return }
        translating.insert(s.id)
        Task {
            // 언어 팩이 없는데 화면 없이 번역을 시도하면 응답 없이 멈춘다. 먼저 설치 여부를 확인한다.
            let status = await LanguageAvailability().status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "ko"))
            switch status {
            case .installed:
                if #available(iOS 26.0, *), let out = await translateDirect(s) {
                    translating.remove(s.id)
                    applyKorean(s.id, out)
                    return
                }
                enqueueTranslation(s)
            case .supported:
                // 아직 내려받지 않음: 번역 화면을 통해 시스템의 언어 다운로드 안내를 띄운다.
                showBanner("영어→한국어 번역 언어를 내려받으면 번역이 시작됩니다")
                enqueueTranslation(s)
            default:
                translating.remove(s.id)
                showBanner("이 기기에서는 영어→한국어 번역을 지원하지 않습니다")
            }
        }
    }

    private func enqueueTranslation(_ s: Script) {
        translationQueue.append(TranslationRequest(scriptID: s.id, texts: s.lines.map(\.en)))
        pumpTranslation()
    }

    @available(iOS 26.0, *)
    private func translateDirect(_ s: Script) async -> [String]? {
        let session = TranslationSession(installedSource: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ko"))
        do {
            let requests = s.lines.enumerated().map { TranslationSession.Request(sourceText: $1.en, clientIdentifier: "\($0)") }
            let responses = try await session.translations(from: requests)
            var out = Array(repeating: "", count: s.lines.count)
            for r in responses { if let id = r.clientIdentifier, let i = Int(id), out.indices.contains(i) { out[i] = r.targetText } }
            return out.contains(where: { !$0.isEmpty }) ? out : nil
        } catch {
            return nil
        }
    }

    private func applyKorean(_ scriptID: String, _ result: [String]) {
        guard let i = customs.firstIndex(where: { $0.id == scriptID }) else { return }
        for k in customs[i].lines.indices where k < result.count { customs[i].lines[k].ko = result[k] }
        scripts = customs
        persistCustoms()
        if current.id == scriptID { current = customs[i] } // 진행 중인 입력은 그대로 두고 번역만 갱신
        libraryTick += 1
        showBanner("한글 번역을 채웠습니다")
    }

    private func pumpTranslation() {
        guard translationRequest == nil, !translationQueue.isEmpty else { return }
        translationRequest = translationQueue.removeFirst()
    }

    func finishTranslation(_ scriptID: String, result: [String]?) {
        translating.remove(scriptID)
        translationRequest = nil
        if let result { applyKorean(scriptID, result) }
        else { showBanner("한글 번역을 만들지 못했습니다. 설정에서 영어→한국어 번역 언어를 받아 주세요.") }
        pumpTranslation()
    }

    // MARK: 단어장
    /// 모르는 단어를 길게 눌렀을 때: 문장과 함께 단어장에 저장하고, 한글 뜻을 찾아 채운다.
    func addWord(_ raw: String, lineIndex i: Int) -> VocabAddResult {
        let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        let id = word.lowercased()
        guard id.count >= 2, lines.indices.contains(i) else { return .invalid }
        if vocab.contains(where: { $0.id == id }) { return .exists }
        let l = lines[i]
        vocab.insert(VocabWord(id: id, word: word, meaning: nil, sentence: l.en, sentenceKo: l.ko,
                               scriptTitle: current.title, youtubeID: current.youtubeID, time: l.t, added: Date()), at: 0)
        persistVocab()
        Task { await fillMeaning(id) }
        return .added
    }

    func removeWord(_ id: String) {
        vocab.removeAll { $0.id == id }
        persistVocab()
    }

    var savedWordIDs: Set<String> { Set(vocab.map(\.id)) }

    func fillMeaning(_ id: String) async {
        guard #available(iOS 26.0, *), let i = vocab.firstIndex(where: { $0.id == id }) else { return }
        let session = TranslationSession(installedSource: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ko"))
        guard let r = try? await session.translate(vocab[i].word),
              let k = vocab.firstIndex(where: { $0.id == id }) else { return }
        let meaning = r.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meaning.isEmpty, meaning.lowercased() != id else { return }
        vocab[k].meaning = meaning
        persistVocab()
    }

    private func persistVocab() {
        if let data = try? JSONEncoder().encode(vocab) { defaults.set(data, forKey: "vocab") }
    }

    // MARK: 목록
    private func touch(_ id: String) {
        var d = defaults.dictionary(forKey: "lastOpened") as? [String: Double] ?? [:]
        d[id] = Date().timeIntervalSince1970
        defaults.set(d, forKey: "lastOpened")
        libraryTick += 1
    }

    /// 최근에 연 순서(처음엔 추가한 순서)
    var library: [Script] {
        _ = libraryTick
        let last = defaults.dictionary(forKey: "lastOpened") as? [String: Double] ?? [:]
        return scripts.enumerated().sorted { a, b in
            let la = last[a.element.id] ?? 0, lb = last[b.element.id] ?? 0
            return la != lb ? la > lb : a.offset < b.offset
        }.map(\.element)
    }

    func summary(for s: Script) -> (percent: Int, started: Bool) {
        if s.id == current.id { return (progressPercent, typed.contains { !$0.isEmpty }) }
        guard let data = defaults.data(forKey: "progress_" + s.id),
              let p = try? JSONDecoder().decode(Progress.self, from: data), p.typed.count == s.lines.count else { return (0, false) }
        let total = s.lines.reduce(0) { $0 + $1.en.count }
        let done = p.typed.reduce(0) { $0 + $1.count }
        return (total > 0 ? done * 100 / total : 0, done > 0)
    }

    // MARK: 저장
    private func persistCustoms() {
        if let data = try? JSONEncoder().encode(customs) { defaults.set(data, forKey: "customScripts") }
    }

    private func loadProgress() {
        let n = current.lines.count
        if let data = defaults.data(forKey: "progress_" + current.id),
           let p = try? JSONDecoder().decode(Progress.self, from: data), p.typed.count == n {
            typed = p.typed; cur = min(max(p.cur, 0), max(n - 1, 0))
            correct = p.correct; keys = p.keys; activeSeconds = p.activeSeconds
            viewLine = p.view.flatMap { (0..<n).contains($0) ? $0 : nil }
        } else {
            typed = Array(repeating: "", count: n)
            cur = 0; correct = 0; keys = 0; activeSeconds = 0
            viewLine = nil
        }
        lastKey = nil
        var rows: [ScriptRow] = []
        var lastMinute = -1
        for (i, l) in current.lines.enumerated() {
            if let t = l.t, t / 60 != lastMinute { lastMinute = t / 60; rows.append(.minute(lastMinute)) }
            rows.append(.line(i))
        }
        self.rows = rows
    }

    private func scheduleSave() {
        saveItem?.cancel()
        let item = DispatchWorkItem { [weak self] in Task { @MainActor in self?.saveNow() } }
        saveItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }

    func saveNow() {
        saveItem?.cancel()
        if daily.count > 120 { daily = Dictionary(uniqueKeysWithValues: daily.sorted { $0.key > $1.key }.prefix(90).map { ($0.key, $0.value) }) }
        defaults.set(daily, forKey: "dailyChars")
        let p = Progress(typed: typed, cur: cur, correct: correct, keys: keys, activeSeconds: activeSeconds, view: viewLine)
        if let data = try? JSONEncoder().encode(p) { defaults.set(data, forKey: "progress_" + current.id) }
    }
}
