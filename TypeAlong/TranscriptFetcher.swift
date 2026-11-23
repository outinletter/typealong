import SwiftUI
import WebKit

/// 유튜브 영상 페이지를 보이지 않는 웹뷰로 열고, 사람이 하듯 "스크립트 표시"를 눌러
/// 화면에 나온 스크립트를 읽어 온다. (내부 API는 사용하지 않는다.)
/// 긴 스크립트 하나를 실행하지 않고 짧은 명령을 여러 번 나눠 실행한다(긴 호출은 페이지가 바뀌면 끊김).
@MainActor
final class TranscriptFetcher: NSObject, WKNavigationDelegate {
    struct Segment { let t: Int; let text: String; var ko: String = "" }
    struct Result { let title: String; let author: String; let segments: [Segment] }
    struct FetchError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var navigation: CheckedContinuation<Void, Error>?

    /// 1순위: WordAhead와 같은 방식(기기에서 직접 유튜브 player 엔드포인트 호출). 실패하면 2순위: 화면 읽기.
    func fetch(videoID: String) async throws -> Result {
        var apiMessage = ""
        do { return try await fetchViaAPI(videoID) }
        catch { apiMessage = error.localizedDescription }
        do { return try await fetchViaPage(videoID) }
        catch {
            throw FetchError(message: "\(error.localizedDescription)\n(직접 요청: \(apiMessage))")
        }
    }

    // MARK: 1순위 - player 엔드포인트
    // 유튜브의 비공개 엔드포인트에 의존하므로 접근 제한·서비스 변경·지역에 따라 실패할 수 있다.
    private func fetchViaAPI(_ id: String) async throws -> Result {
        guard id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
            throw FetchError(message: "올바른 영상 주소가 아닙니다.")
        }
        func request(_ url: URL, body: Data? = nil) async throws -> Data {
            var req = URLRequest(url: url, timeoutInterval: 15)
            if let body {
                req.httpMethod = "POST"
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                throw FetchError(message: "유튜브가 자막 요청을 거절했습니다.")
            }
            return data
        }

        let html = String(decoding: try await request(URL(string: "https://www.youtube.com/watch?v=\(id)")!), as: UTF8.self)
        let keyRegex = try NSRegularExpression(pattern: "\"INNERTUBE_API_KEY\":\\s*\"([A-Za-z0-9_-]+)\"")
        guard let m = keyRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else {
            throw FetchError(message: "유튜브에서 자막 접근을 허용하지 않았습니다.")
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "ANDROID", "clientVersion": "20.10.38"]],
            "videoId": id,
        ])
        let data = try await request(URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(html[r])")!, body: body)
        let player = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (player["playabilityStatus"] as? [String: Any])?["status"] as? String == "OK" else {
            throw FetchError(message: "비공개·연령 제한 또는 접근할 수 없는 영상입니다.")
        }
        let renderer = (player["captions"] as? [String: Any])?["playerCaptionsTracklistRenderer"] as? [String: Any]
        let tracks = (renderer?["captionTracks"] as? [[String: Any]] ?? []).filter {
            ($0["languageCode"] as? String ?? "").hasPrefix("en")
        }
        func isYouTube(_ u: URL) -> Bool { u.scheme == "https" && ["youtube.com", "www.youtube.com"].contains(u.host ?? "") }
        func needsAuth(_ u: URL) -> Bool {
            (URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []).contains { $0.name == "exp" && $0.value == "xpe" }
        }
        func json3URL(_ base: URL, tlang: String? = nil) -> URL? {
            guard var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
            var items = (c.queryItems ?? []).filter { $0.name != "fmt" && $0.name != "tlang" }
            items.append(URLQueryItem(name: "fmt", value: "json3"))
            if let tlang { items.append(URLQueryItem(name: "tlang", value: tlang)) }
            c.queryItems = items
            return c.url
        }
        /// json3 자막을 (시작 초, 글자) 목록으로 읽는다.
        func loadEvents(_ url: URL) async throws -> [(start: Double, text: String)] {
            let json = (try JSONSerialization.jsonObject(with: try await request(url)) as? [String: Any]) ?? [:]
            return (json["events"] as? [[String: Any]] ?? []).compactMap { event in
                let text = (event["segs"] as? [[String: Any]] ?? []).compactMap { $0["utf8"] as? String }.joined()
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : ((event["tStartMs"] as? Double ?? 0) / 1000, text)
            }
        }

        guard let track = tracks.first(where: { $0["kind"] as? String == "asr" }) ?? tracks.first,
              let address = track["baseUrl"] as? String, let enURL = URL(string: address), isYouTube(enURL) else {
            throw FetchError(message: "이 영상에는 수집 가능한 영어 자막이 없습니다.")
        }
        guard !needsAuth(enURL) else {
            throw FetchError(message: "유튜브에서 추가 인증을 요구해 직접 수집할 수 없습니다.")
        }
        guard let enJSON = json3URL(enURL) else { throw FetchError(message: "자막 주소를 만들지 못했습니다.") }
        let enEvents = try await loadEvents(enJSON)

        // 이벤트(짧은 조각)를 문장 길이로 합친다. ">>"는 화자가 바뀐다는 표시: 글자는 지우고 거기서 줄을 나눈다.
        var segments: [Segment] = []
        var buffer = "", bufferStart = 0
        func flush() {
            let t = buffer.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { segments.append(Segment(t: bufferStart, text: t)) }
            buffer = ""
        }
        for event in enEvents {
            let pieces = event.text.replacingOccurrences(of: "&gt;", with: ">").components(separatedBy: ">>")
            for (i, piece) in pieces.enumerated() {
                if i > 0 { flush() }
                let part = piece.trimmingCharacters(in: .whitespaces)
                if part.isEmpty { continue }
                if buffer.isEmpty { bufferStart = Int(event.start) }
                buffer += (buffer.isEmpty ? "" : " ") + part
                let ends = buffer.last.map { ".?!".contains($0) } ?? false
                if (ends && buffer.count > 25) || buffer.count > 110 { flush() }
            }
        }
        flush()
        guard !segments.isEmpty else { throw FetchError(message: "영어 자막 본문이 비어 있습니다.") }

        // 한글 자막이 있으면 같이 가져온다: 올린 사람의 한글 자막 → 없으면 유튜브 자동 번역 자막.
        var koEvents: [(start: Double, text: String)] = []
        let koTracks = (renderer?["captionTracks"] as? [[String: Any]] ?? []).filter { ($0["languageCode"] as? String ?? "").hasPrefix("ko") }
        if let koTrack = koTracks.first(where: { $0["kind"] as? String != "asr" }) ?? koTracks.first,
           let a = koTrack["baseUrl"] as? String, let u = URL(string: a), isYouTube(u), !needsAuth(u),
           let url = json3URL(u), let ev = try? await loadEvents(url), !ev.isEmpty {
            koEvents = ev
        } else if (renderer?["translationLanguages"] as? [[String: Any]] ?? []).contains(where: { $0["languageCode"] as? String == "ko" }),
                  let url = json3URL(enURL, tlang: "ko"), let ev = try? await loadEvents(url), !ev.isEmpty {
            koEvents = ev
        }
        if !koEvents.isEmpty {
            for i in segments.indices {
                let lower = Double(segments[i].t)
                let upper = i + 1 < segments.count ? Double(segments[i + 1].t) : .infinity
                segments[i].ko = koEvents.filter { $0.start >= lower && $0.start < upper }.map(\.text).joined(separator: " ")
                    .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: ">>", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        let details = player["videoDetails"] as? [String: Any] ?? [:]
        return Result(title: details["title"] as? String ?? "", author: details["author"] as? String ?? "", segments: segments)
    }

    // MARK: 2순위 - 영상 페이지의 "스크립트 표시" 화면 읽기
    private func fetchViaPage(_ videoID: String) async throws -> Result {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        web.navigationDelegate = self

        // 실제로 화면에 보이는 상태여야 유튜브가 스크립트 패널을 그린다(아이폰은 화면 밖 웹뷰의 그리기를 멈춘다).
        // 앱 화면 맨 뒤에 거의 투명하게 둔다.
        var found: UIWindow?
        for _ in 0..<25 { // 공유로 앱이 막 켜진 경우 창이 준비될 때까지 최대 5초 기다린다
            found = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: \.isKeyWindow)
            if found != nil { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let window = found else { throw FetchError(message: "화면을 준비하지 못했습니다.") }
        window.insertSubview(web, at: 0)
        defer { web.removeFromSuperview() }

        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else {
            throw FetchError(message: "유튜브 주소가 올바르지 않습니다.")
        }
        try await load(url, in: web)

        try? await Task.sleep(for: .milliseconds(1500)) // 유튜브가 화면을 그릴 시간
        _ = try? await web.evaluateJavaScript("window.scrollTo(0, 500)")

        // 1) 설명란 펼치기(없으면 넘어감)  2) "스크립트 표시" 누르기  3) 구간이 나타날 때까지 기다림
        _ = await poll(web, Self.expandJS, seconds: 12) { ($0 as? Bool) == true }
        try? await Task.sleep(for: .milliseconds(700))

        var count = 0
        for attempt in 0..<2 {
            let clicked = await poll(web, Self.buttonJS, seconds: 12) { ($0 as? Bool) == true }
            if clicked == nil {
                throw FetchError(message: "스크립트 표시 버튼을 찾지 못했습니다. 이 영상은 스크립트가 없을 수 있습니다.\n\(await pageInfo(web))")
            }
            let n = await poll(web, Self.countJS, seconds: 12) { (($0 as? Int) ?? 0) > 0 }
            count = (n as? Int) ?? 0
            if count > 0 { break }
            if attempt == 1 { throw FetchError(message: "스크립트를 불러오지 못했습니다.\n\(await pageInfo(web))") }
        }
        try? await Task.sleep(for: .milliseconds(800)) // 나머지 구간이 그려질 시간

        guard let json = (try? await web.evaluateJavaScript(Self.extractJS)) as? String,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError(message: "스크립트를 읽지 못했습니다.\n\(await pageInfo(web))")
        }
        let raw = obj["segs"] as? [[String: Any]] ?? []
        let segments = raw.compactMap { d -> Segment? in
            guard let t = (d["t"] as? NSNumber)?.intValue, let text = d["text"] as? String, !text.isEmpty else { return nil }
            return Segment(t: t, text: text)
        }
        if segments.isEmpty { throw FetchError(message: "이 영상에서 스크립트를 찾지 못했습니다.") }
        return Result(title: obj["title"] as? String ?? "", author: obj["author"] as? String ?? "", segments: segments)
    }

    // MARK: 짧은 명령을 반복 실행
    /// `check`가 참이 될 때까지 0.4초 간격으로 실행한다. 시간 안에 안 되면 nil.
    private func poll(_ web: WKWebView, _ js: String, seconds: Double, until check: (Any?) -> Bool) async -> Any? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let v = try? await web.evaluateJavaScript(js), check(v) { return v }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return nil
    }

    private func pageInfo(_ web: WKWebView) async -> String {
        let js = """
        (function(){
          var labels = [];
          document.querySelectorAll('button').forEach(function (b) {
            var t = (b.getAttribute('aria-label') || b.innerText || '').trim();
            if (/스크립트|transcript|더보기|more/i.test(t)) labels.push(t.slice(0, 20));
          });
          return document.URL.slice(0, 70) + ' | ' + document.title.slice(0, 30) + ' | ' + labels.slice(0, 8).join(',')
            + ' | exp=' + !!document.querySelector('#description-inline-expander')
            + ' segs=' + document.querySelectorAll('transcript-segment-view-model, ytd-transcript-segment-renderer').length
            + ' vis=' + document.visibilityState;
        })()
        """
        let info = (try? await web.evaluateJavaScript(js)) as? String
        return "페이지: \(info ?? "알 수 없음")"
    }

    // MARK: 페이지 로딩
    private func load(_ url: URL, in web: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            navigation = c
            web.load(URLRequest(url: url))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.finishNavigation(FetchError(message: "페이지를 여는 데 시간이 너무 오래 걸립니다."))
            }
        }
    }

    private func finishNavigation(_ error: Error?) {
        guard let c = navigation else { return }
        navigation = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishNavigation(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishNavigation(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishNavigation(error) }

    // MARK: 페이지 안에서 실행할 짧은 스크립트
    private static let expandJS = #"""
    (function () {
      var e = document.querySelector("#description-inline-expander #expand, tp-yt-paper-button#expand");
      if (e) { e.click(); return true; }
      return false;
    })()
    """#

    private static let buttonJS = #"""
    (function () {
      var bs = document.querySelectorAll("button");
      for (var i = 0; i < bs.length; i++) {
        var t = (bs[i].getAttribute("aria-label") || bs[i].innerText || "").trim();
        if (/^(스크립트 표시|show transcript)$/i.test(t)) { bs[i].click(); return true; }
      }
      return false;
    })()
    """#

    private static let countJS = #"""
    document.querySelectorAll("transcript-segment-view-model, ytd-transcript-segment-renderer").length
    """#

    private static let extractJS = #"""
    (function () {
      var out = [];
      var nodes = document.querySelectorAll("transcript-segment-view-model, ytd-transcript-segment-renderer");
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        var tsEl = n.querySelector(".ytwTranscriptSegmentViewModelTimestamp, .segment-timestamp");
        var txEl = n.querySelector('[role="text"], .ytAttributedStringHost, .segment-text');
        var tsText, text;
        if (tsEl && txEl) {
          tsText = tsEl.textContent.trim();
          text = txEl.textContent.replace(/\s+/g, " ").trim();
        } else {
          var lines = n.innerText.split("\n").map(function (x) { return x.trim(); }).filter(Boolean);
          if (lines.length < 2) continue;
          tsText = lines[0];
          text = lines[lines.length - 1];
        }
        var p = tsText.split(":").map(Number);
        if (p.some(isNaN) || !text) continue;
        out.push({ t: p.reduce(function (a, x) { return a * 60 + x; }, 0), text: text });
      }
      var pr = window.ytInitialPlayerResponse;
      return JSON.stringify({
        title: (pr && pr.videoDetails && pr.videoDetails.title) || document.title.replace(/ - YouTube$/, ""),
        author: (pr && pr.videoDetails && pr.videoDetails.author) || "",
        segs: out
      });
    })()
    """#
}
