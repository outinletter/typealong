import SwiftUI
import AVFoundation

/// 단어장: 연습 중 길게 눌러 저장한 단어 목록
struct VocabView: View {
    @ObservedObject var store: Store
    @StateObject private var speaker = Speaker()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.taBGTop, Color.taBG], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if store.vocab.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical").font(.system(size: 40)).foregroundStyle(Color.taDim)
                    Text("아직 저장한 단어가 없어요").font(.headline).foregroundStyle(Color.taText)
                    Text("연습 화면에서 모르는 단어를 길게 누르면\n단어장에 자동으로 저장됩니다.")
                        .font(.footnote).foregroundStyle(Color.taKo).multilineTextAlignment(.center)
                }
            } else {
                List {
                    ForEach(store.vocab) { v in
                        VocabRow(word: v, onSpeak: { speaker.say(v.word) })
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                            .contextMenu {
                                Button { Task { await store.fillMeaning(v.id) } } label: { Label("뜻 다시 찾기", systemImage: "arrow.clockwise") }
                                Button(role: .destructive) { store.removeWord(v.id) } label: { Label("삭제", systemImage: "trash") }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.removeWord(v.id) } label: { Label("삭제", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("단어장 \(store.vocab.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct VocabRow: View {
    let word: VocabWord
    let onSpeak: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.word).font(.title3.bold()).foregroundStyle(Color.taMain)
                Text(word.meaning ?? "뜻을 찾는 중이거나 찾지 못했어요")
                    .font(.subheadline).foregroundStyle(word.meaning == nil ? Color.taDim : Color.taText)
                Text(word.sentence).font(.footnote).foregroundStyle(Color.taKo).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onSpeak) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 16))
                    .frame(width: 40, height: 40)
                    .background(Color.taBG, in: Circle())
                    .foregroundStyle(Color.taText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("발음 듣기")
        }
        .padding(12)
        .background(Color.taPanel, in: RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor
final class Speaker: ObservableObject {
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }
}
