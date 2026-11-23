import AppKit

let W = 1320, H = 2868
let imgDir = "/Volumes/Data/Project/TypeAlong/Marketing/raw/"
let outDir = "/Volumes/Data/Project/TypeAlong/Marketing/screenshots/"

func render(_ file: String, _ title: String, _ sub: String, _ out: String) {
    guard let src = NSImage(contentsOfFile: imgDir + file), let rep0 = src.representations.first else { print("no image", file); return }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let full = NSRect(x: 0, y: 0, width: W, height: H)
    NSGradient(colors: [NSColor(srgbRed: 0.25, green: 0.30, blue: 0.49, alpha: 1), NSColor(srgbRed: 0.11, green: 0.14, blue: 0.24, alpha: 1)])!.draw(in: full, angle: -90)

    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byWordWrapping
    let titleAttr: [NSAttributedString.Key: Any] = [.font: NSFont(name: "AppleSDGothicNeo-Bold", size: 96)!, .foregroundColor: NSColor.white, .paragraphStyle: para]
    let subAttr: [NSAttributedString.Key: Any] = [.font: NSFont(name: "AppleSDGothicNeo-Medium", size: 50)!,
        .foregroundColor: NSColor(srgbRed: 0.95, green: 0.88, blue: 0.64, alpha: 1), .paragraphStyle: para]
    (title as NSString).draw(in: NSRect(x: 60, y: H - 290, width: W - 120, height: 130), withAttributes: titleAttr)
    (sub as NSString).draw(in: NSRect(x: 60, y: H - 390, width: W - 120, height: 80), withAttributes: subAttr)

    // 휴대폰: 상태 표시줄 영역(위 110px)을 잘라내고 둥근 모서리로 표시
    let sw = Double(rep0.pixelsWide), sh = Double(rep0.pixelsHigh)
    let cropTop = (sh * 0.055).rounded()
    let cropH = sh - cropTop
    let pw = 1060.0, ph = pw * cropH / sw
    let px = (Double(W) - pw) / 2, py = 120.0
    let bezel = 16.0
    let outer = NSRect(x: px - bezel, y: py - bezel, width: pw + 2 * bezel, height: ph + 2 * bezel)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.45); shadow.shadowBlurRadius = 60; shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.set()
    NSColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: outer, xRadius: 130, yRadius: 130).fill()
    NSGraphicsContext.restoreGraphicsState()
    let screen = NSRect(x: px, y: py, width: pw, height: ph)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: 114, yRadius: 114).addClip()
    src.draw(in: screen, from: NSRect(x: 0, y: 0, width: sw, height: cropH), operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: outDir + out))
    print("wrote", out)
}

render("01.png", "틀린 글자는 바로 표시", "WPM과 정확도를 실시간으로 확인해요", "01_practice.png")
render("02.png", "영어 문장 아래 한글 번역", "뜻을 보며 따라 치세요", "02_translation.png")
render("03.png", "모르는 단어는 길게 눌러 저장", "한 번에 단어장에 모아 둬요", "03_word_save.png")
render("04.png", "링크만 붙여넣으면 끝", "자막을 가져와 연습 영상으로 저장해요", "04_add.png")
