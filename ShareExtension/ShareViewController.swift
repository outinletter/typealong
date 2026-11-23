import UIKit
import UniformTypeIdentifiers

/// 유튜브 앱의 공유 시트에서 "TypeAlong"을 고르면 주소를 앱으로 넘기고 앱을 연다.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await handle() }
    }

    private func handle() async {
        guard let youtube = await findYouTubeURL() else {
            return finish(message: "유튜브 주소를 찾지 못했습니다.")
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let encoded = youtube.addingPercentEncoding(withAllowedCharacters: allowed) ?? youtube
        guard let url = URL(string: "typealong://add?url=\(encoded)"), openHostApp(url) else {
            // 앱을 직접 열지 못하면 주소를 복사해 두고 안내한다.
            UIPasteboard.general.string = youtube
            return finish(message: "주소를 복사했습니다. TypeAlong을 열어 \"영상 추가\"에 붙여넣어 주세요.")
        }
        finish(message: nil)
    }

    /// 공유된 항목에서 유튜브 주소를 찾는다(URL 또는 글 속의 주소).
    private func findYouTubeURL() async -> String? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                    guard let value = try? await provider.loadItem(forTypeIdentifier: type) else { continue }
                    let text = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
                    if let found = Self.firstYouTubeURL(in: text) { return found }
                }
            }
        }
        return nil
    }

    private static func firstYouTubeURL(in text: String) -> String? {
        let pattern = "https?://(?:www\\.|m\\.)?(?:youtube\\.com|youtu\\.be)/[^\\s]+"
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[r])
    }

    /// 공유 확장에서는 앱을 직접 열 수 없어, 응답자 체인에서 UIApplication을 찾아 연다.
    private func openHostApp(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let app = current as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func finish(message: String?) {
        guard let message else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        let alert = UIAlertController(title: "TypeAlong", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }
}
