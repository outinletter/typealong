import SwiftUI
import Network
import Translation

/// 앱의 첫 화면: 저장한 영상 목록 → 탭하면 연습 화면으로
struct ContentView: View {
    @StateObject private var store = Store()
    @State private var showAdd = false
    @State private var practiceOpen = false
    @State private var vocabOpen = false
    @State private var category: CatalogCategory?
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            LibraryView(store: store,
                        onOpen: { store.select($0); practiceOpen = true },
                        onAdd: { showAdd = true },
                        onVocab: { vocabOpen = true },
                        onCategory: { category = $0 },
                        onSettings: { showSettings = true })
                .navigationDestination(isPresented: $practiceOpen) { PracticeView(store: store) }
                .navigationDestination(isPresented: $vocabOpen) { VocabView(store: store) }
                .navigationDestination(item: $category) { c in
                    CategoryView(store: store, category: c, onOpen: { store.select($0); practiceOpen = true })
                }
        }
        .preferredColorScheme(.dark)
        .tint(Color.taMain)
        .sheet(isPresented: $showAdd) { AddScriptView(store: store) }
        .sheet(isPresented: $showSettings) { SettingsSheet(store: store) }
        .onOpenURL { url in
            // 유튜브 공유 → typealong://add?url=... 로 들어온 주소를 바로 가져오기 화면에 채운다.
            guard url.scheme == "typealong",
                  let shared = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "url" })?.value,
                  ScriptParser.youtubeID(from: shared) != nil else { return }
            practiceOpen = false
            store.importShared(shared)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { store.saveNow() } }
        .background {
            if #available(iOS 18.0, *) { ShareTranslationHost(store: store) }
        }
    }
}

/// 공유로 저장한 영상의 영어 → 한글 번역을 순서대로 처리한다.
@available(iOS 18.0, *)
struct ShareTranslationHost: View {
    @ObservedObject var store: Store
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(config) { session in
                guard let req = await MainActor.run(body: { store.translationRequest }) else { return }
                do {
                    let requests = req.texts.enumerated().map {
                        TranslationSession.Request(sourceText: $1, clientIdentifier: "\($0)")
                    }
                    let responses = try await session.translations(from: requests)
                    var out = Array(repeating: "", count: req.texts.count)
                    for r in responses {
                        if let id = r.clientIdentifier, let i = Int(id), out.indices.contains(i) { out[i] = r.targetText }
                    }
                    await MainActor.run { store.finishTranslation(req.scriptID, result: out) }
                } catch {
                    await MainActor.run { store.finishTranslation(req.scriptID, result: nil) }
                }
            }
            .onChange(of: store.translationRequest) { _, req in
                guard req != nil else { return }
                if config == nil {
                    config = .init(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ko"))
                } else {
                    config?.invalidate()
                }
            }
    }
}

struct LibraryView: View {
    @ObservedObject var store: Store
    @ObservedObject private var net = NetworkMonitor.shared
    let onOpen: (String) -> Void
    let onAdd: () -> Void
    let onVocab: () -> Void
    let onCategory: (CatalogCategory) -> Void
    let onSettings: () -> Void
    @AppStorage("tipDismissed") private var tipDismissed = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.taBGTop, Color.taBG], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            List {
                Section {
                    if store.library.isEmpty && store.jobs.isEmpty {
                        EmptyLibraryCard(onAdd: onAdd)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14))
                    }
                    SummaryCard(today: store.todayChars, streak: store.streakDays, words: store.vocab.count)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14))
                    CategoryRow(onPick: onCategory)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14))
                    ForEach(store.jobs) { job in
                        ImportRow(job: job, onClose: { store.dismissJob(job.id) }, onRetry: { store.importShared("https://youtu.be/\(job.videoID)") })
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                    }
                    ForEach(store.library) { s in
                        Button { onOpen(s.id) } label: {
                            LibraryRow(script: s, summary: store.summary(for: s), translating: store.translating.contains(s.id))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                        .swipeActions(edge: .trailing) {
                            if s.id != store.base.id {
                                Button(role: .destructive) { store.delete(s) } label: { Label("삭제", systemImage: "trash") }
                            }
                        }
                    }
                } header: {
                    if !net.online {
                        Label("오프라인 – 저장한 스크립트로 연습할 수 있어요 (영상은 재생되지 않아요)", systemImage: "wifi.slash")
                            .font(.footnote).foregroundStyle(Color.taKo)
                            .textCase(nil)
                    }
                }
                if !tipDismissed {
                    TipCard(onClose: { tipDismissed = true })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 14, trailing: 14))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .overlay(alignment: .bottom) {
            if let banner = store.banner {
                Text(banner)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(white: 0.15))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassCapsule(tint: Color.taMain)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.banner)
        .navigationTitle("TypeAlong")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onVocab) {
                    Label("단어장 \(store.vocab.count)", systemImage: "books.vertical")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(Color.taText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onSettings) {
                    Image(systemName: "gearshape").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Color.taText)
                .accessibilityLabel("환경 설정")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onAdd) {
                    Label("영상 추가", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .foregroundStyle(Color(white: 0.15))
            }
        }
    }
}

/// 저장한 영상이 없을 때 처음 사용법을 보여 주는 카드
struct EmptyLibraryCard: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.plus").font(.system(size: 34)).foregroundStyle(Color.taMain)
            Text("연습할 영상을 추가해 보세요").font(.headline).foregroundStyle(Color.taText)
            Text("영상 링크를 붙여넣거나, 다른 앱의 공유 화면에서 TypeAlong을 고르면 자막이 연습 목록에 저장됩니다. 영어 스크립트를 직접 붙여넣어도 됩니다.")
                .font(.footnote).foregroundStyle(Color.taKo).multilineTextAlignment(.center)
            Button(action: onAdd) {
                Label("영상 추가", systemImage: "plus").font(.subheadline.bold()).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color(white: 0.15))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassCard(cornerRadius: 16)
    }
}

/// 오늘 친 글자 · 연속 일수 · 단어장 단어 수
struct SummaryCard: View {
    let today: Int
    let streak: Int
    let words: Int

    var body: some View {
        HStack(spacing: 0) {
            item(value: today.formatted(), label: "오늘 친 글자", symbol: "keyboard")
            item(value: "\(streak)", label: "연속 일수", symbol: "flame")
            item(value: "\(words)", label: "단어장", symbol: "books.vertical")
        }
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 16)
    }

    private func item(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Color.taMain)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Color.taText)
            Text(label).font(.caption2).foregroundStyle(Color.taKo)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 처음 쓰는 사람을 위한 사용법 안내(닫을 수 있음)
struct TipCard: View {
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb").foregroundStyle(Color.taMain).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                tip("유튜브에서 공유 → TypeAlong을 고르면 자막이 자동으로 저장됩니다.")
                tip("저장한 영상은 인터넷 없이도 연습할 수 있어요. (영상 재생만 인터넷 필요)")
                tip("연습 중 모르는 단어를 길게 누르면 단어장에 저장됩니다.")
                tip("카드를 왼쪽으로 밀면 삭제됩니다.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Color.taKo)
                .accessibilityLabel("안내 닫기")
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }

    private func tip(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Color.taKo)
    }
}

struct LibraryRow: View {
    let script: Script
    let summary: (percent: Int, started: Bool)
    var translating = false

    var body: some View {
        HStack(spacing: 12) {
            ThumbView(youtubeID: script.youtubeID)
                .frame(width: 124, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(script.title)
                    .font(.subheadline.bold()).foregroundStyle(Color.taText)
                    .lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text("\(script.channel) · \(script.lines.count)문장")
                        .font(.caption).foregroundStyle(Color.taKo).lineLimit(1)
                    if translating {
                        ProgressView().controlSize(.mini)
                        Text("번역 중").font(.caption2).foregroundStyle(Color.taMain)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ProgressBar(value: Double(summary.percent) / 100)
                        .clipShape(Capsule())
                    Text(summary.started ? "\(summary.percent)%" : "시작 전")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Color.taMain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(height: 92)
        .glassCard(cornerRadius: 14)
        .contentShape(Rectangle())
    }
}

/// 공유로 받은 영상을 수집하는 중(또는 실패)임을 보여 주는 행
struct ImportRow: View {
    let job: Store.ImportJob
    let onClose: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if job.failed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.taBad)
            } else {
                ProgressView()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(job.failed ? "가져오지 못했습니다" : "영상 저장 중").font(.subheadline.bold()).foregroundStyle(Color.taText)
                Text(job.status).font(.caption).foregroundStyle(Color.taKo).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if job.failed {
                Button("다시", action: onRetry).buttonStyle(.bordered).controlSize(.small)
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Color.taKo)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }
}

/// 유튜브 썸네일. 한 번 받으면 기기에 저장해 오프라인에서도 보인다.
struct ThumbView: View {
    let youtubeID: String?
    @ObservedObject private var net = NetworkMonitor.shared
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.taBG
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: youtubeID == nil ? "text.alignleft" : "play.rectangle")
                    .font(.title2).foregroundStyle(Color.taDim)
            }
        }
        .clipped()
        .task(id: net.online) {
            guard let youtubeID, image == nil else { return }
            image = await ThumbnailCache.image(for: youtubeID)
        }
    }
}

enum ThumbnailCache {
    private static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func image(for id: String) async -> UIImage? {
        let file = dir.appendingPathComponent(id + ".jpg")
        if let d = try? Data(contentsOf: file), let img = UIImage(data: d) { return img }
        guard let url = URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else { return nil }
        try? data.write(to: file)
        return img
    }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.online = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "typealong.network"))
    }
}
