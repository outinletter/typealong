import SwiftUI

/// 기본 제공 연습 목록(카테고리별). 영상 없이 텍스트만 연습한다. 영어는 키보드로 칠 수 있는 ASCII만 쓴다.
struct CatalogCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let note: String
    let scripts: [Script]
}

enum Catalog {
    private static func make(_ id: String, _ title: String, _ channel: String, _ pairs: [(String, String)]) -> Script {
        Script(id: "cat_" + id, title: title, channel: channel, youtubeID: nil,
               lines: pairs.map { ScriptLine(t: nil, en: $0.0, ko: $0.1) })
    }

    static let categories: [CatalogCategory] = [quotes, speeches]

    static func script(id: String) -> Script? {
        categories.flatMap(\.scripts).first { $0.id == id }
    }

    // MARK: 영어 명언
    static let quotes = CatalogCategory(id: "quotes", title: "영어 명언", symbol: "quote.bubble", note: "짧은 명언으로 가볍게", scripts: [
        make("quotes_life", "Quotes: Life & Courage", "영어 명언", [
            ("The only thing we have to fear is fear itself. - Franklin D. Roosevelt", "우리가 두려워할 것은 두려움 그 자체뿐이다."),
            ("The journey of a thousand miles begins with a single step. - Lao Tzu", "천 리 길도 한 걸음부터 시작된다."),
            ("Do what you can, with what you have, where you are. - Theodore Roosevelt", "있는 곳에서, 가진 것으로, 할 수 있는 것을 하라."),
            ("Well done is better than well said. - Benjamin Franklin", "잘 말하는 것보다 잘 해내는 것이 낫다."),
            ("Knowing yourself is the beginning of all wisdom. - Aristotle", "자신을 아는 것이 모든 지혜의 시작이다."),
            ("I think, therefore I am. - Rene Descartes", "나는 생각한다, 고로 존재한다."),
            ("What we think, we become. - Buddha", "우리는 생각하는 대로 된다."),
        ]),
        make("quotes_wisdom", "Quotes: Mind & Learning", "영어 명언", [
            ("An investment in knowledge pays the best interest. - Benjamin Franklin", "지식에 대한 투자가 가장 높은 이자를 낸다."),
            ("The only true wisdom is in knowing you know nothing. - Socrates", "유일한 진짜 지혜는 자신이 아무것도 모른다는 것을 아는 것이다."),
            ("Happiness depends upon ourselves. - Aristotle", "행복은 우리 자신에게 달려 있다."),
            ("It does not matter how slowly you go as long as you do not stop. - Confucius", "멈추지만 않는다면 얼마나 느리게 가는지는 중요하지 않다."),
            ("The mind is everything. What you think you become. - Buddha", "마음이 전부다. 생각하는 대로 된다."),
            ("Quality is not an act, it is a habit. - Aristotle", "탁월함은 행동이 아니라 습관이다."),
        ]),
    ])

    // MARK: 유명한 연설 (공개 영역 발췌)
    static let speeches = CatalogCategory(id: "speeches", title: "유명한 연설", symbol: "mic", note: "역사적인 연설의 한 대목", scripts: [
        make("speech_gettysburg", "Gettysburg Address - Abraham Lincoln", "유명한 연설 (1863)", [
            ("Four score and seven years ago our fathers brought forth on this continent, a new nation, conceived in Liberty, and dedicated to the proposition that all men are created equal.", "87년 전, 우리의 선조들은 자유 속에서 잉태되고 모든 사람은 평등하게 창조되었다는 명제에 바쳐진 새로운 나라를 이 대륙에 세웠습니다."),
            ("Now we are engaged in a great civil war, testing whether that nation, or any nation so conceived and so dedicated, can long endure.", "이제 우리는 큰 내전을 치르며, 그렇게 잉태되고 바쳐진 나라가 오래 존속할 수 있는지 시험받고 있습니다."),
            ("We are met on a great battle-field of that war.", "우리는 그 전쟁의 거대한 전장에 모였습니다."),
            ("It is altogether fitting and proper that we should do this.", "우리가 이렇게 하는 것은 참으로 마땅하고 옳은 일입니다."),
            ("But, in a larger sense, we can not dedicate, we can not consecrate, we can not hallow this ground.", "그러나 더 넓은 의미에서 우리는 이 땅을 봉헌할 수도, 신성하게 할 수도, 거룩하게 할 수도 없습니다."),
            ("The brave men, living and dead, who struggled here, have consecrated it, far above our poor power to add or detract.", "여기서 싸운 용감한 이들이, 살아 있든 죽었든, 이미 이 땅을 신성하게 했으며 우리의 보잘것없는 힘으로 더하거나 덜 수 없습니다."),
            ("The world will little note, nor long remember what we say here, but it can never forget what they did here.", "세상은 우리가 여기서 하는 말을 주목하거나 오래 기억하지 않겠지만, 그들이 여기서 한 일은 결코 잊지 못할 것입니다."),
            ("It is for us the living, rather, to be dedicated here to the unfinished work which they who fought here have thus far so nobly advanced.", "오히려 살아 있는 우리가 여기서 싸운 이들이 지금까지 그토록 고귀하게 이끌어 온 미완의 과업에 헌신해야 합니다."),
            ("That government of the people, by the people, for the people, shall not perish from the earth.", "국민의, 국민에 의한, 국민을 위한 정부가 이 땅에서 사라지지 않도록 해야 합니다."),
        ]),
        make("speech_fdr", "First Inaugural Address - Franklin D. Roosevelt", "유명한 연설 (1933)", [
            ("This great Nation will endure as it has endured, will revive and will prosper.", "이 위대한 나라는 지금까지 그래왔듯 견뎌 내고, 되살아나고, 번영할 것입니다."),
            ("So, first of all, let me assert my firm belief that the only thing we have to fear is fear itself.", "그러니 무엇보다 먼저, 우리가 두려워할 것은 오직 두려움 그 자체뿐이라는 저의 굳은 믿음을 말씀드립니다."),
            ("It is nameless, unreasoning, unjustified terror which paralyzes needed efforts to convert retreat into advance.", "그것은 이름도 없고 이유도 없고 근거도 없는 공포로, 후퇴를 전진으로 바꾸는 데 필요한 노력을 마비시킵니다."),
        ]),
        make("speech_declaration", "Declaration of Independence (Preamble)", "유명한 연설 (1776)", [
            ("We hold these truths to be self-evident, that all men are created equal, that they are endowed by their Creator with certain unalienable Rights.", "우리는 다음을 자명한 진리로 받아들입니다. 모든 사람은 평등하게 창조되었으며, 창조주로부터 양도할 수 없는 권리를 부여받았습니다."),
            ("That among these are Life, Liberty and the pursuit of Happiness.", "그 권리 중에는 생명과 자유, 그리고 행복의 추구가 있습니다."),
            ("That to secure these rights, Governments are instituted among Men, deriving their just powers from the consent of the governed.", "이 권리를 보장하기 위해 사람들 사이에 정부가 세워졌고, 정부의 정당한 권력은 피치자의 동의에서 나옵니다."),
        ]),
    ])
}

/// 첫 화면의 기본 목록 카드(영어 명언·유명한 연설)
struct CategoryRow: View {
    let onPick: (CatalogCategory) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Catalog.categories) { c in
                Button { onPick(c) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: c.symbol).font(.title3).foregroundStyle(Color.taMain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).font(.subheadline.bold()).foregroundStyle(Color.taText)
                            Text(c.note).font(.caption2).foregroundStyle(Color.taKo).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 14, interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 한 카테고리의 연습 목록. 누르면 내 목록에 추가하고 연습 화면으로 간다.
struct CategoryView: View {
    @ObservedObject var store: Store
    let category: CatalogCategory
    let onOpen: (String) -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.taBGTop, Color.taBG], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            List {
                ForEach(category.scripts) { s in
                    Button {
                        store.addCatalog(s)
                        onOpen(s.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.title).font(.subheadline.bold()).foregroundStyle(Color.taText)
                            Text("\(s.channel) · \(s.lines.count)문장").font(.caption).foregroundStyle(Color.taKo)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassCard(cornerRadius: 14, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
