import AppKit

// Sorter 앱 아이콘 1024x1024 마스터 생성.
// 모티프: 하나의 소스 노드 → 여러 인터페이스로 라우팅 분기.

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// 1) 배경: 둥근 사각형 + 대각선 그라데이션 (블루 → 인디고)
// 가장자리 120px 패딩: 다른 macOS 앱 아이콘과 독에서 시각적 크기를 맞춘다.
let pad: CGFloat = 55
let cornerRadius: CGFloat = (size - pad * 2) * 0.2237
let bgRect = NSRect(x: pad, y: pad, width: size - pad * 2, height: size - pad * 2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

// 드롭 섀도우: clip 전에 그려야 투명 영역으로 빠져나온다.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 20,
              color: NSColor(white: 0, alpha: 0.28).cgColor)
NSColor(calibratedRed: 0.22, green: 0.32, blue: 0.78, alpha: 1.0).setFill()
bgPath.fill()
ctx.restoreGState()

bgPath.addClip()

let top = NSColor(calibratedRed: 0.36, green: 0.56, blue: 0.95, alpha: 1.0)     // #5B8FF2
let bottom = NSColor(calibratedRed: 0.22, green: 0.32, blue: 0.78, alpha: 1.0)  // #3852C7
let gradient = NSGradient(starting: top, ending: bottom)!
gradient.draw(in: bgRect, angle: -90)

// 좌상단 은은한 하이라이트
if let glow = NSGradient(colors: [NSColor(white: 1.0, alpha: 0.18), NSColor(white: 1.0, alpha: 0.0)]) {
    glow.draw(from: p(0.22, 0.82), to: p(0.6, 0.5), options: [])
}

// 2) 라우팅 그래프 (패딩 영역 기준으로 그린다)
let white = NSColor.white
let draw = size - pad * 2  // 실제 그리기 영역 크기
func p(_ rx: CGFloat, _ ry: CGFloat) -> NSPoint {
    NSPoint(x: pad + draw * rx, y: pad + draw * ry)
}
let source = p(0.30, 0.50)
let dests = [
    p(0.74, 0.745),
    p(0.76, 0.50),
    p(0.74, 0.255),
]

// 분기 선 (노드 뒤에 그림)
white.withAlphaComponent(0.95).setStroke()
for d in dests {
    let path = NSBezierPath()
    path.lineWidth = draw * 0.045
    path.lineCapStyle = .round
    path.move(to: source)
    // 부드러운 곡선
    let c1 = NSPoint(x: (source.x + d.x) * 0.55, y: source.y)
    let c2 = NSPoint(x: (source.x + d.x) * 0.5, y: d.y)
    path.curve(to: d, controlPoint1: c1, controlPoint2: c2)
    path.stroke()
}

// 노드 그리기 헬퍼
func dot(_ center: NSPoint, radius: CGFloat, fill: NSColor, ring: CGFloat = 0) {
    let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    let p = NSBezierPath(ovalIn: rect)
    fill.setFill()
    p.fill()
    if ring > 0 {
        // 안쪽에 배경색 원을 그려 링 효과
        let inner = radius - ring
        let irect = NSRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)
        bottom.setFill()
        NSBezierPath(ovalIn: irect).fill()
    }
}

// 목적지 노드: 흰 링(속 빈 느낌)
for d in dests {
    dot(d, radius: draw * 0.062, fill: white, ring: draw * 0.024)
}
// 소스 노드: 꽉 찬 흰 원
dot(source, radius: draw * 0.085, fill: white)

image.unlockFocus()

// PNG 저장
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("png encode failed")
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
