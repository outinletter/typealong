import SwiftUI

/// 연습 화면: 영상·통계·스크립트
struct PracticeView: View {
    @ObservedObject var store: Store
    @ObservedObject private var net = NetworkMonitor.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = PlayerController()
    @StateObject private var typing = TypingController()
    @State private var toast: String?
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var videoStarted = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.taBGTop, Color.taBG], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                headerBar
                media.padding(.top, 6).layoutPriority(1)
                ProgressBar(value: Double(store.progressPercent) / 100)
                ScriptView(store: store,
                           onTapLine: { store.goTo($0); typing.show() },
                           onTapChar: { store.place(line: $0, at: $1); typing.show() },
                           onWord: { i, word in
                               switch store.addWord(word, lineIndex: i) {
                               case .added: flash("단어장에 추가: \(word)")
                               case .exists:
                                   store.removeWord(word.trimmingCharacters(in: CharacterSet(charactersIn: "'")).lowercased())
                                   flash("단어장에서 뺐어요: \(word)")
                               case .invalid: break
                               }
                           },
                           onSeek: { sec in
                               if videoStarted { player.seek(sec) }
                               else {
                                   videoStarted = true
                                   DispatchQueue.main.asyncAfter(deadline: .now() + 2) { player.seek(sec) }
                               }
                           })
            }
            TypingInput(controller: typing,
                        onChar: { store.input($0) },
                        onBackspace: { store.backspace() },
                        onReturn: { store.advance() })
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .tint(Color.taMain)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if store.showKorean, store.needsKorean(store.current) { store.requestTranslation(for: store.current) }
        }
        .onDisappear { store.saveNow() }
        .onChange(of: store.banner) { _, b in if let b { flash(b) } }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(white: 0.15))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassCapsule(tint: Color.taMain)
                    .padding(.top, 54)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { store.saveNow() } }
        .confirmationDialog("진행 상황을 모두 지우고 처음부터 시작할까요?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("처음부터", role: .destructive) { store.reset() }
        }
        .confirmationDialog("이 스크립트와 진행 상황을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) { store.deleteCurrent(); dismiss() }
        }
    }

    // MARK: 맨 위: 슬림 바(‹ 제목 설정) + 통계 한 줄
    private var headerBar: some View {
        HStack(spacing: 8) {
            backButton
            titleLabel
            hideVideoButton
            moreMenu
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var statsCaption: some View {
        Text("WPM \(store.wpm)  ·  정확도 \(store.accuracy)%  ·  진행 \(store.progressPercent)%")
            .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.taDim)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private func flash(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if toast == text { withAnimation { toast = nil } }
        }
    }

    @ViewBuilder
    private var media: some View {
        if store.videoMode != .hidden, let id = store.current.youtubeID, net.online {
            VStack(spacing: 0) {
                Color.black
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.width * 9 / 16)
                    .overlay { videoArea(id) }
                    .clipped()
                statsCaption
            }
        } else {
            VStack(spacing: 4) {
                statsCaption
                if !net.online, store.videoMode != .hidden, store.current.youtubeID != nil {
                    Label("오프라인 – 영상 없이 연습 중", systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(Color.taKo)
                }
            }
        }
    }

    // MARK: 뒤로·제목·설정
    private var titleLabel: some View {
        Text(store.current.title)
            .font(.subheadline.bold())
            .foregroundStyle(Color.taText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                .frame(width: 44, height: 36)
                .foregroundStyle(Color.taText)
                .glassCard(cornerRadius: 12, interactive: true)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .accessibilityLabel("목록으로")
    }

    /// 영상 감추기·보이기
    private var hideVideoButton: some View {
        Button { store.videoMode = store.videoMode == .hidden ? .compact : .hidden } label: {
            Image(systemName: store.videoMode == .hidden ? "play.rectangle" : "rectangle.slash")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 36)
                .foregroundStyle(Color.taText)
                .glassCard(cornerRadius: 12, interactive: true)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .opacity(store.current.youtubeID == nil ? 0.35 : 1)
        .disabled(store.current.youtubeID == nil)
        .accessibilityLabel(store.videoMode == .hidden ? "영상 보이기" : "영상 감추기")
    }

    /// 한글 번역 켜기/끄기. 길게 누르면 처음부터 다시·삭제 메뉴.
    private var moreMenu: some View {
        Button {
            store.showKorean.toggle()
            if store.showKorean, store.needsKorean(store.current) { store.requestTranslation(for: store.current) }
        } label: {
            Image(systemName: store.showKorean ? "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 36)
                .foregroundStyle(store.showKorean ? Color.taMain : Color.taText)
                .glassCard(cornerRadius: 12, interactive: true)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .contextMenu {
            Button { confirmReset = true } label: { Label("처음부터 다시", systemImage: "arrow.counterclockwise") }
            if store.current.id != store.base.id {
                Button(role: .destructive) { confirmDelete = true } label: { Label("이 영상 삭제", systemImage: "trash") }
            }
        }
        .accessibilityLabel(store.showKorean ? "한글 번역 끄기" : "한글 번역 켜기")
    }

    /// 처음에는 썸네일만 보여 주고, 탭하면 재생한다.
    @ViewBuilder
    private func videoArea(_ id: String) -> some View {
        if videoStarted {
            VideoView(videoID: id, controller: player)
        } else {
            Button { videoStarted = true } label: {
                ZStack {
                    ThumbView(youtubeID: id)
                    Color.black.opacity(0.25)
                    Image(systemName: "play.fill").font(.system(size: 22))
                        .foregroundStyle(Color(white: 0.1))
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.9), in: Circle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("영상 재생")
        }
    }
}

struct StatText: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(Color.taText)
            Text(label).font(.caption2).foregroundStyle(Color.taDim)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 영상 옆에 쌓는 통계(숫자 위, 이름 아래)
struct StatStack: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(Color.taText)
            Text(label).font(.caption2).foregroundStyle(Color.taDim)
        }
        .accessibilityElement(children: .combine)
    }
}

struct IconButton: View {
    var symbol: String? = nil
    var text: String? = nil
    var busy = false
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if busy { ProgressView().tint(Color.taMain) } // 작업 중
                else if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .bold)) }
                else if let text { Text(text).font(.system(size: 15, weight: .bold, design: .rounded)) }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(on ? Color.taMain : Color.taText)
            .glassCard(cornerRadius: 12, tint: on ? Color.taMain.opacity(0.22) : nil, interactive: true)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Color.taMain : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .focusable(false) // 하드웨어 키보드 Space가 버튼을 누르지 않게
        .focusEffectDisabled()
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.taPanel)
                Rectangle().fill(Color.taMain).frame(width: g.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
    }
}
