import SwiftUI
import Translation

/// 영상 주소와 스크립트·가사를 붙여넣어 연습 자료를 추가하는 화면.
struct AddScriptView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var title = ""
    @State private var english = ""
    @State private var korean = ""
    @State private var error = ""
    @State private var fetching = false
    @State private var status = ""
    @State private var translating = false
    @State private var translateTexts: [String] = []
    @State private var translateToken = 0

    var body: some View {
        NavigationStack {
            Form {
                if !error.isEmpty {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.taBad) }
                }
                Section {
                    HStack {
                        TextField("", text: $url)
                            .accessibilityLabel("영상 주소")
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        pasteClear($url)
                    }
                    Button {
                        store.importShared(url) // 목록 화면에서 저장 진행 상황을 보여 준다
                        dismiss()
                    } label: {
                        HStack {
                            Text("자막 자동 가져오기")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color(white: 0.12)) // 연한 노랑 버튼 위에서 또렷하게 보이도록 어두운 글자
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.taMain)
                    .disabled(fetching || ScriptParser.youtubeID(from: url) == nil)
                    if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(Color.taKo) }
                } header: {
                    Text("유튜브 주소 (선택)")
                } footer: {
                    Text("영상 페이지를 열어 \"스크립트 표시\"에 나온 영어 자막을 읽어 옵니다. 자막이 없는 영상은 가져올 수 없습니다.")
                }
                Section("제목 (선택)") {
                    TextField("", text: $title)
                        .accessibilityLabel("제목")
                }
                Section {
                    editor($english)
                    HStack { Spacer(); pasteClear($english) }
                } header: {
                    Text("영어 스크립트 · 가사")
                } footer: {
                    Text("한 줄이 한 문장입니다. 유튜브 \"스크립트 표시\"를 복사해 붙여넣으면 시간도 함께 인식합니다.")
                }
                Section {
                    editor($korean)
                    HStack {
                        pasteClear($korean)
                        Spacer()
                        if #available(iOS 18.0, *) {
                            Button {
                                startTranslation()
                            } label: {
                                HStack {
                                    if translating { ProgressView().controlSize(.small) }
                                    Label(translating ? "번역 중..." : "영어를 한글로 번역", systemImage: "character.bubble").font(.footnote)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(translating || english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                } header: {
                    Text("한글 번역 (선택)")
                } footer: {
                    Text("영어와 같은 줄 수로 붙여넣으면 줄마다 짝지어 표시합니다.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.taBG)
            .navigationTitle("영상 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .bold()
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color.taMain)
        .background {
            if #available(iOS 18.0, *) {
                TranslationHost(texts: translateTexts, token: translateToken) { result in
                    translating = false
                    if let result { korean = result.joined(separator: "\n"); status = "한글 번역을 채웠습니다. (기계번역)" }
                    else { error = "번역하지 못했습니다. 설정에서 언어 다운로드를 확인해 주세요." }
                }
            }
        }
    }

    /// 주소만 있으면 자막을 자동으로 가져와 저장하고, 스크립트를 붙여넣었으면 그대로 저장한다.
    private func save() {
        let hasEnglish = !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasEnglish, ScriptParser.youtubeID(from: url) != nil {
            store.importShared(url)
            dismiss()
            return
        }
        if let e = store.addScript(url: url, title: title, english: english, korean: korean) { error = e }
        else { dismiss() }
    }

    private func fetchTranscript() async {
        guard let id = ScriptParser.youtubeID(from: url) else { return }
        fetching = true; error = ""; status = ""
        defer { fetching = false }
        do {
            let r = try await TranscriptFetcher().fetch(videoID: id)
            english = r.segments.map { "\(formatTime($0.t))\n\($0.text)" }.joined(separator: "\n")
            // 한글 자막이 모든 문장에 있을 때만 같이 채운다(줄 수가 어긋나지 않도록)
            korean = r.segments.allSatisfy({ !$0.ko.isEmpty }) ? r.segments.map(\.ko).joined(separator: "\n") : ""
            if title.trimmingCharacters(in: .whitespaces).isEmpty { title = r.title }
            status = "\(r.segments.count)개 구간을 가져왔습니다. (자동 생성 자막일 수 있어 오타가 있을 수 있어요)"
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startTranslation() {
        error = ""
        translateTexts = ScriptParser.lines(en: english, ko: "").map(\.en)
        guard !translateTexts.isEmpty else { return }
        translating = true
        translateToken += 1
    }

    private func editor(_ text: Binding<String>) -> some View {
        TextEditor(text: text)
            .frame(minHeight: 130)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    /// 붙여넣기(클립보드) 기호와 지우기(x) 기호
    private func pasteClear(_ text: Binding<String>) -> some View {
        HStack(spacing: 18) {
            Button {
                if let s = UIPasteboard.general.string { text.wrappedValue = s }
            } label: {
                Image(systemName: "doc.on.clipboard").font(.system(size: 18))
            }
            .accessibilityLabel("붙여넣기")
            Button {
                text.wrappedValue = ""
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18))
            }
            .foregroundStyle(text.wrappedValue.isEmpty ? Color.taDim.opacity(0.5) : Color.taKo)
            .disabled(text.wrappedValue.isEmpty)
            .accessibilityLabel("지우기")
        }
        .buttonStyle(.borderless)
    }
}

/// 영어 → 한글 기기 내 번역(iOS 18 이상). 처음에는 언어 팩 다운로드 안내가 나올 수 있다.
@available(iOS 18.0, *)
struct TranslationHost: View {
    let texts: [String]
    let token: Int
    let onDone: ([String]?) -> Void
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(config) { session in
                do {
                    let requests = texts.enumerated().map {
                        TranslationSession.Request(sourceText: $1, clientIdentifier: "\($0)")
                    }
                    let responses = try await session.translations(from: requests)
                    var out = Array(repeating: "", count: texts.count)
                    for r in responses {
                        if let id = r.clientIdentifier, let i = Int(id), out.indices.contains(i) { out[i] = r.targetText }
                    }
                    onDone(out)
                } catch {
                    onDone(nil)
                }
            }
            .onChange(of: token) { _, _ in
                if config == nil {
                    config = .init(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ko"))
                } else {
                    config?.invalidate()
                }
            }
    }
}
