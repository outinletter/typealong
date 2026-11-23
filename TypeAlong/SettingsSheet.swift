import SwiftUI

/// 환경 설정 팝업: 표시·글자 설정을 한곳에 모았다.
struct SettingsSheet: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss

    private var koreanBinding: Binding<Bool> {
        Binding(get: { store.showKorean }, set: { on in
            store.showKorean = on
        })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("표시") {
                    Toggle(isOn: koreanBinding) {
                        HStack(spacing: 8) {
                            Label("한글 번역 표시", systemImage: "captions.bubble")
                        }
                    }
                    Toggle(isOn: $store.ignoreCase) {
                        Label("대소문자 무시", systemImage: "textformat")
                    }
                }
                Section("영상") {
                    Picker("영상 크기", selection: $store.videoMode) {
                        Text("작게").tag(Store.VideoMode.compact)
                        Text("크게").tag(Store.VideoMode.large)
                        Text("숨김").tag(Store.VideoMode.hidden)
                    }
                    .pickerStyle(.segmented)
                }
                Section("글자") {
                    HStack {
                        Label("글자 크기", systemImage: "textformat.size")
                        Spacer()
                        Button { store.fontSize = max(12, store.fontSize - 2) } label: { Image(systemName: "minus.circle.fill") }
                        Text("\(Int(store.fontSize))").font(.body.monospacedDigit()).frame(minWidth: 28)
                        Button { store.fontSize = min(34, store.fontSize + 2) } label: { Image(systemName: "plus.circle.fill") }
                    }
                    .buttonStyle(.borderless)
                    .font(.title3)
                    Picker("글꼴", selection: $store.fontStyle) {
                        ForEach(Store.FontStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.system(size: store.fontSize, design: store.fontStyle.design))
                        .foregroundStyle(Color.taKo)
                }
                Section("정보") {
                    Link(destination: URL(string: "https://outinletter.github.io/privacy-policy/typealong.html")!) {
                        Label("개인정보 처리방침", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://outinletter.github.io/privacy-policy/typealong.html")!) {
                        Label("지원·문의", systemImage: "envelope")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { EmptyView() }
            .navigationTitle("환경 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() }.bold() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .tint(Color.taMain)
    }
}
