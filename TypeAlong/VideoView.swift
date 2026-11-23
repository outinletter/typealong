import SwiftUI
import WebKit

@MainActor
final class PlayerController: ObservableObject {
    weak var web: WKWebView?
    var ready = false
    private var queuedTime: Double?
    private(set) var videoID = ""

    static let settingsKey = "TypeAlongYouTubeSettings"
    static let rateKey = "TypeAlongPlaybackRate"

    func seek(_ seconds: Int) {
        guard let web else { return }
        guard ready else { queuedTime = Double(seconds); return }
        run("TypeAlongYouTube.load", ["action": "seek", "videoId": videoID, "start": Double(max(0, seconds)), "play": true, "rate": rate], in: web)
    }

    func pause() { web?.evaluateJavaScript("TypeAlongYouTube.suspend()") }

    func didLoad(videoID: String) {
        self.videoID = videoID
        ready = true
        run("TypeAlongYouTube.load", ["action": "load", "videoId": videoID, "start": queuedTime ?? savedTime(videoID), "play": true, "rate": rate], in: web)
        queuedTime = nil
        restoreSettings()
    }

    static func posKey(_ id: String) -> String { "videoPos_" + id }
    func savedTime(_ id: String) -> Double {
        let t = UserDefaults.standard.double(forKey: Self.posKey(id))
        return t > 3 ? max(0, t - 2) : 0   // 조금 앞에서 이어서
    }
    func saveTime(_ t: Double) {
        guard t > 0, !videoID.isEmpty else { return }
        UserDefaults.standard.set(t, forKey: Self.posKey(videoID))
    }

    func restoreSettings() {
        guard ready, let web else { return }
        let s = UserDefaults.standard.dictionary(forKey: Self.settingsKey) ?? [:]
        run("TypeAlongYouTube.restoreSettings", s, in: web)
    }

    private var rate: Double { UserDefaults.standard.dictionary(forKey: Self.settingsKey)?["rate"] as? Double ?? 1 }

    private func run(_ fn: String, _ payload: [String: Any], in web: WKWebView?) {
        guard let web, let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("\(fn)(\(json))")
    }
}

/// WordAhead의 유튜브 플레이어를 복제: 번들의 youtube-player.html(IFrame API)을 WKWebView로 재생한다.
/// baseURL이 있어야 유튜브가 임베드를 허용한다(없으면 오류 153).
struct VideoView: UIViewRepresentable {
    let videoID: String
    let controller: PlayerController

    func makeCoordinator() -> Coordinator { Coordinator(controller, videoID: videoID) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "youtubeState")
        config.userContentController.add(context.coordinator, name: "youtubeSettings")
        config.userContentController.addUserScript(Self.frameScript())
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        controller.web = web
        if let url = Bundle.main.url(forResource: "youtube-player", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8),
           let base = URL(string: "https://com.addvalue.typealong/") {
            web.loadHTMLString(html, baseURL: base)
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.controller.pause()
        view.stopLoading()
        for n in ["youtubeState", "youtubeSettings"] { view.configuration.userContentController.removeScriptMessageHandler(forName: n) }
        coordinator.controller.ready = false
        coordinator.controller.web = nil
    }

    /// 모든 프레임에서 실행: 화면이 꺼져도 재생이 이어지게 하고, 사용자가 고른 재생 속도를 유지한다.
    static func frameScript() -> WKUserScript {
        let saved = UserDefaults.standard.double(forKey: PlayerController.rateKey)
        let source = """
        (function(){
          try{
            Object.defineProperty(document,'hidden',{get:function(){return false},configurable:true});
            Object.defineProperty(document,'visibilityState',{get:function(){return 'visible'},configurable:true});
            ['visibilitychange','webkitvisibilitychange','pagehide','freeze'].forEach(function(n){
              window.addEventListener(n,function(e){e.stopImmediatePropagation()},true);
              document.addEventListener(n,function(e){e.stopImmediatePropagation()},true);
            });
          }catch(e){}
          var desired=\(saved > 0 ? String(saved) : "null"),lastTouch=0,internal=false;
          ['touchstart','touchend','pointerdown','pointerup','mousedown','click'].forEach(function(n){window.addEventListener(n,function(){lastTouch=Date.now()},true)});
          function video(){return document.querySelector('video')}
          function apply(){var v=video();if(v&&desired&&Math.abs(v.playbackRate-desired)>0.001){internal=true;v.playbackRate=desired;setTimeout(function(){internal=false},50)}}
          document.addEventListener('ratechange',function(e){
            var v=e.target;if(!(v instanceof HTMLVideoElement)||internal)return;
            if(Date.now()-lastTouch<3000){desired=v.playbackRate;try{window.webkit.messageHandlers.youtubeState.postMessage({rate:desired})}catch(x){}}
            else if(desired){apply()}
          },true);
          ['loadedmetadata','play','playing','seeked'].forEach(function(n){document.addEventListener(n,apply,true)});
          setInterval(function(){if(Date.now()-lastTouch>3000)apply()},400);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let controller: PlayerController
        let videoID: String
        init(_ c: PlayerController, videoID: String) { controller = c; self.videoID = videoID }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { controller.didLoad(videoID: videoID) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { controller.ready = false; webView.reload() }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if message.name == "youtubeSettings" {
                UserDefaults.standard.set(body, forKey: PlayerController.settingsKey)
            } else if body["videoId"] as? String == videoID, let t = body["time"] as? Double, t.isFinite {
                controller.saveTime(t)
            } else if body["videoId"] == nil, let rate = body["rate"] as? Double, rate > 0 {
                UserDefaults.standard.set(rate, forKey: PlayerController.rateKey)
                ucc.removeAllUserScripts()
                ucc.addUserScript(VideoView.frameScript())
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url, ["https", "http"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url); decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}
