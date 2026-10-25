import StarCore
import SwiftUI
import RealityKit

/// 見たい天体を選ぶ。一覧と比較画面で同じ選択肢を使う。
struct TargetPicker: View {
    @Binding var target: ObservationTarget

    var body: some View {
        Picker("見たい天体", selection: $target) {
            Text("月").tag(ObservationTarget.moon)
            Section("惑星") {
                ForEach(PlanetCatalog.planets) { planet in
                    Text(planet.name).tag(ObservationTarget.planet(planet))
                }
            }
            Section("恒星") {
                ForEach(StarCatalog.stars) { star in
                    Text(star.name).tag(ObservationTarget.star(star))
                }
            }
        }
    }
}

struct CabinTarget: Identifiable {
    let id: String
    let name: String
    let kind: String
    let observation: ObservationTarget
    var points: [CGPoint] = []
    var edges: [[Int]] = []
    var note: String?
    var isConstellation: Bool { !points.isEmpty }

    static var catalog: [CabinTarget] {
        var items = [CabinTarget(id: "moon", name: "月", kind: "MOON", observation: .moon)]
        items += PlanetCatalog.planets.map {
            CabinTarget(id: "planet-" + $0.id, name: $0.name, kind: "PLANET", observation: .planet($0))
        }
        if let star = StarCatalog.star(id: "betelgeuse") {
            items.append(CabinTarget(
                id: "orion", name: "オリオン座", kind: "CONSTELLATION", observation: .star(star),
                points: [CGPoint(x: 0.23, y: 0.12), CGPoint(x: 0.73, y: 0.19),
                         CGPoint(x: 0.42, y: 0.46), CGPoint(x: 0.50, y: 0.49),
                         CGPoint(x: 0.58, y: 0.52), CGPoint(x: 0.27, y: 0.88), CGPoint(x: 0.78, y: 0.85)],
                edges: [[0,1,4,6,5,2,0],[2,3,4]],
                note: "星座の形は選択用の模式図です。観測場所は代表星「ベテルギウス」で判定します。星座全体が見えることを保証する判定ではありません。"))
        }
        if let star = StarCatalog.star(id: "schedar") {
            items.append(CabinTarget(
                id: "cassiopeia", name: "カシオペヤ座", kind: "CONSTELLATION", observation: .star(star),
                points: [CGPoint(x: 0.08,y: 0.25), CGPoint(x: 0.28,y: 0.75), CGPoint(x: 0.50,y: 0.40),
                         CGPoint(x: 0.72,y: 0.70), CGPoint(x: 0.92,y: 0.20)],
                edges: [[0,1,2,3,4]],
                note: "星座の形は選択用の模式図です。観測場所は代表星「シェダル」で判定します。星座全体の可視性は未判定です。"))
        }
        items += StarCatalog.stars.map {
            CabinTarget(id: "star-" + $0.id, name: $0.name, kind: "STAR", observation: .star($0))
        }
        return items
    }
}


struct CabinPortrait: View {
    let target: CabinTarget
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let side = min(size.width, size.height)
            var drawing = context
            drawing.translateBy(x: size.width / 2, y: size.height / 2)
            drawing.scaleBy(x: side / 1000, y: side / 1000)
            if target.isConstellation { CabinArt.constellation(target, in: drawing) }
            else { CabinArt.planet(target, in: drawing) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 選択用の描画。天体の位相・実際の表面地図とは区別した、解像度に依存しない模式表現。
enum CabinArt {
    /// 月の画像はアセットカタログではなく Sky フォルダのファイルなので、バンドルから読む
    static let moonDisk: UIImage = Bundle.main.url(forResource: "moon_disk", withExtension: "png")
        .flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage()
    static func random(_ i: Int) -> CGFloat {
        let v = sin(Double(i) * 127.1 + 311.7) * 43758.5453
        return CGFloat(v - floor(v))
    }
    static func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
    }
    static func path(_ points: [CGPoint], close: Bool = false) -> Path {
        var p = Path()
        for (i, point) in points.enumerated() {
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        if close { p.closeSubpath() }
        return p
    }
    static func planet(_ target: CabinTarget, in context: GraphicsContext) {
        let id = target.id
        let saturn = id == "planet-saturn"
        let star = target.kind == "STAR"
        let radius: CGFloat = saturn ? 225 : 435
        let palettes: [String: [Color]] = [
            "moon": [Color(white: 0.60), Color(white: 0.82), Color(white: 0.69)],
            "planet-mercury": [Color(white: 0.37), Color(white: 0.63), Color(white: 0.49)],
            "planet-venus": [Color(red: 0.78, green: 0.51, blue: 0.22), Color(red: 1, green: 0.88, blue: 0.65)],
            "planet-mars": [Color(red: 0.66, green: 0.22, blue: 0.10), Color(red: 0.91, green: 0.50, blue: 0.26)],
            "planet-jupiter": [Color(red: 0.62, green: 0.36, blue: 0.22), Color(red: 0.92, green: 0.83, blue: 0.66),
                Color(red: 0.80, green: 0.62, blue: 0.42), Color(red: 0.96, green: 0.90, blue: 0.79)],
            "planet-saturn": [Color(red: 0.68, green: 0.54, blue: 0.32), Color(red: 0.93, green: 0.83, blue: 0.59),
                Color(red: 0.86, green: 0.72, blue: 0.49)]
        ]
        let warm = ["star-betelgeuse", "star-antares", "star-aldebaran", "star-arcturus"].contains(id)
        let colors = palettes[id] ?? (warm ? [.orange, .yellow, .white] : [.blue, .cyan, .white])
        if star {
            context.fill(oval(-490, -490, 980, 980), with: .radialGradient(
                Gradient(colors: [colors[0].opacity(0.38), .clear]), center: .zero, startRadius: 300, endRadius: 490))
            var disk = context
            disk.clip(to:oval(-435,-435,870,870))
            disk.fill(oval(-435,-435,870,870),with:.radialGradient(
                Gradient(colors:[.white,colors[1],colors[0]]),
                center:CGPoint(x:-120,y:-120),startRadius:0,endRadius:650))
            for index in 0..<1600 {
                let x = (random(index*3)*2-1)*435, y = (random(index*3+1)*2-1)*435
                let r = 2 + random(index*3+2)*7
                disk.fill(oval(x-r,y-r,r*2,r*2),with:.color(colors[0].opacity(0.18)))
            }
            return
        }
        if saturn { rings(front: false, in: context) }
        var surface = context
        surface.clip(to: oval(-radius, -radius, radius * 2, radius * 2))
        surface.fill(oval(-radius, -radius, radius * 2, radius * 2), with: .color(colors[0]))
        if id == "moon" {
            // 既存のNASA SVS月面画像を再利用。透明な外周を持たない円盤の範囲で表示する。
            surface.draw(Image(uiImage: moonDisk).interpolation(.high),
                         in: CGRect(x:-radius,y:-radius,width:radius*2,height:radius*2))
            surface.fill(oval(-radius,-radius,radius*2,radius*2), with:.radialGradient(
                Gradient(colors:[.white.opacity(0.06),.clear,.black.opacity(0.3)]),
                center:CGPoint(x:-radius*0.4,y:-radius*0.4),startRadius:0,endRadius:radius*1.65))
            return
        }
        // 緯度の帯と細かい渦。球の輪郭で切り、最後に法線を意識した明暗を重ねる。
        for index in 0..<(id == "planet-mercury" || id == "planet-mars" ? 0 : 240) {
            let y = -radius + CGFloat(index) * radius / 120
            let wave = (id == "planet-jupiter" || saturn || id == "planet-venus") ? radius * 0.025 : radius * 0.009
            var band = Path()
            band.move(to: CGPoint(x: -radius, y: y))
            band.addCurve(to: CGPoint(x: radius, y: y + 3), control1: CGPoint(x: -radius * 0.3, y: y + wave),
                          control2: CGPoint(x: radius * 0.4, y: y - wave))
            let colorIndex = Int((sin(CGFloat(index) * 0.18) + 1) * 1.45) % colors.count
            var clouds = surface
            clouds.addFilter(.blur(radius: id == "planet-venus" ? 6 : 1.6))
            clouds.stroke(band, with: .color(colors[colorIndex].opacity(star ? 0.55 : 0.50)), lineWidth: 6)
        }
        for index in 0..<1100 {
            let x = (random(index * 3) * 2 - 1) * radius
            let y = (random(index * 3 + 1) * 2 - 1) * radius
            let size = star ? 3 + random(index + 9) * 9 : 1 + random(index + 9) * 4
            surface.fill(oval(x, y, size, size), with: .color(colors[index % colors.count].opacity(0.28)))
        }
        if id == "planet-mercury" { craters(in: surface, radius: radius, count: 400) }
        if id == "planet-mars" {
            var terrain = Path()
            terrain.move(to:CGPoint(x:-330,y:40))
            terrain.addCurve(to:CGPoint(x:0,y:90),control1:CGPoint(x:-200,y:-250),control2:CGPoint(x:-70,y:-50))
            terrain.addCurve(to:CGPoint(x:220,y:60),control1:CGPoint(x:80,y:160),control2:CGPoint(x:200,y:-80))
            terrain.addCurve(to:CGPoint(x:-330,y:40),control1:CGPoint(x:80,y:260),control2:CGPoint(x:-260,y:180))
            var dust = surface
            dust.addFilter(.blur(radius:12))
            dust.fill(terrain,with:.color(Color(red:0.27,green:0.19,blue:0.15).opacity(0.52)))
            craters(in: surface, radius: radius, count: 70)
            surface.fill(oval(-190,-475,380,105), with:.color(.white.opacity(0.85)))
        }
        if id == "planet-jupiter" {
            surface.fill(oval(90,90,185,95), with:.color(Color(red:0.63,green:0.24,blue:0.14)))
            surface.stroke(oval(80,82,205,110), with:.color(.orange.opacity(0.45)), lineWidth:7)
            surface.stroke(oval(120,109,115,52), with:.color(.white.opacity(0.35)), lineWidth:4)
        }
        surface.fill(oval(-radius,-radius,radius*2,radius*2), with:.radialGradient(
            Gradient(colors:[.white.opacity(star ? 0.6 : 0.24),.clear,.black.opacity(star ? 0.2 : 0.78)]),
            center:CGPoint(x:-radius*0.4,y:-radius*0.4),startRadius:0,endRadius:radius*1.65))
        surface.stroke(oval(-radius+1,-radius+1,radius*2-2,radius*2-2),
                       with:.color((star ? colors[1] : .white).opacity(0.25)),lineWidth:2)
        if saturn { rings(front: true, in: context) }
    }
    static func craters(in context: GraphicsContext, radius: CGFloat, count: Int) {
        for i in 0..<count {
            let angle = random(i*5) * .pi * 2
            let distance = sqrt(random(i*5+1)) * radius
            let r = 2 + pow(random(i*5+2),3) * 31
            let x = cos(angle)*distance, y = sin(angle)*distance
            context.fill(oval(x-r,y-r,r*2,r*2),with:.color(.black.opacity(0.28)))
            context.stroke(oval(x-r+1,y-r+2,r*2,r*2),with:.color(.white.opacity(0.35)),lineWidth:1.5)
            context.fill(oval(x-r*0.6,y-r*0.5,r*1.2,r),with:.color(.black.opacity(0.17)))
        }
    }
    static func rings(front: Bool, in context: GraphicsContext) {
        var ring = context
        ring.rotate(by:.degrees(-24))
        ring.scaleBy(x:1,y:0.38)
        ring.clip(to:Path(CGRect(x:-470,y:front ? 0 : -470,width:940,height:470)))
        for index in 0..<110 {
            let r = 275 + CGFloat(index)*1.65
            if (index > 74 && index < 80) || index == 26 { continue }
            let brightness = Double(0.5 + random(index)*0.35)
            let color = Color(red:brightness,green:brightness*0.88,blue:brightness*0.66)
            ring.stroke(oval(-r,-r,r*2,r*2),with:.color(color.opacity(front ? 0.94 : 0.64)),lineWidth:1.8)
        }
    }
    static func illustration(_ id: String) -> [[CGPoint]] {
        let paths: [[(CGFloat,CGFloat)]] = id == "orion" ? [
            [(0.44,0.02),(0.53,0.02),(0.57,0.08),(0.53,0.15),(0.45,0.15),(0.41,0.08),(0.44,0.02)],
            [(0.24,0.20),(0.40,0.17),(0.58,0.17),(0.73,0.25),(0.64,0.46),(0.36,0.46),(0.24,0.20)],
            [(0.36,0.46),(0.30,0.63),(0.69,0.63),(0.64,0.46)],
            [(0.37,0.63),(0.33,0.82),(0.19,0.98),(0.29,0.99),(0.49,0.70),(0.68,0.97),(0.81,0.97),(0.62,0.63)],
            [(0.24,0.20),(0.12,0.13),(0.11,-0.05),(0.06,-0.05),(0.02,0.20),(0.20,0.34)],
            [(0.73,0.25),(0.86,0.32),(0.87,0.53),(0.96,0.53),(1.01,0.22),(0.89,0.16)],
            [(0.05,-0.05),(0.02,-0.19),(0.12,-0.19),(0.11,-0.05)]
        ] : [
            [(0.36,0.27),(0.35,0.12),(0.42,0.18),(0.49,0.07),(0.55,0.19),(0.63,0.13),(0.62,0.28),(0.36,0.27)],
            [(0.41,0.29),(0.39,0.39),(0.47,0.47),(0.56,0.42),(0.59,0.29)],
            [(0.45,0.45),(0.29,0.53),(0.16,0.66),(0.08,0.26)],
            [(0.54,0.44),(0.68,0.53),(0.84,0.57),(0.92,0.20)],
            [(0.37,0.51),(0.34,0.73),(0.25,0.99),(0.73,0.99),(0.59,0.72),(0.59,0.49)],
            [(0.20,0.35),(0.20,0.83),(0.80,0.83),(0.80,0.34)],
            [(0.20,0.83),(0.15,1.09)],[(0.80,0.83),(0.85,1.09)]
        ]
        return paths.map { $0.map { CGPoint(x:$0.0,y:id == "orion" ? $0.1 : 0.12+$0.1*0.65) } }
    }
    static func constellation(_ target: CabinTarget, in context: GraphicsContext) {
        let art = illustration(target.id), all = target.points + art.flatMap { $0 }
        let minX = all.map(\.x).min() ?? 0, maxX = all.map(\.x).max() ?? 1
        let minY = all.map(\.y).min() ?? 0, maxY = all.map(\.y).max() ?? 1
        let center = CGPoint(x:(minX+maxX)/2,y:(minY+maxY)/2)
        let extent = all.map { hypot($0.x-center.x,$0.y-center.y) }.max() ?? 1
        // 光のにじみまで含め、円の縁との余白を確保。透明画像の寸法は使用しない。
        let scale = 430 / max(extent,0.01)
        func project(_ p: CGPoint) -> CGPoint { CGPoint(x:(p.x-center.x)*scale,y:(p.y-center.y)*scale) }
        for stroke in art {
            let outline = path(stroke.map(project))
            context.fill(outline,with:.color(.yellow.opacity(0.05)))
            context.stroke(outline,with:.color(Color(red:0.76,green:0.73,blue:0.58).opacity(0.35)),lineWidth:2)
        }
        let points = target.points.map(project)
        var lines = context
        lines.addFilter(.shadow(color:.cyan.opacity(0.5),radius:4))
        for edge in target.edges {
            lines.stroke(path(edge.map { points[$0] }),with:.color(.cyan.opacity(0.8)),lineWidth:2)
        }
        for (i,p) in points.enumerated() {
            let color: Color = target.id == "orion" && i == 0 ? .orange : .cyan
            context.fill(oval(p.x-23,p.y-23,46,46),with:.radialGradient(
                Gradient(colors:[color.opacity(0.65),.clear]),center:p,startRadius:0,endRadius:23))
            context.stroke(path([CGPoint(x:p.x-12,y:p.y),CGPoint(x:p.x+12,y:p.y)]),
                           with:.color(.white.opacity(0.7)),lineWidth:1)
            context.stroke(path([CGPoint(x:p.x,y:p.y-12),CGPoint(x:p.x,y:p.y+12)]),
                           with:.color(.white.opacity(0.7)),lineWidth:1)
            context.fill(oval(p.x-3.5,p.y-3.5,7,7),with:.color(.white))
        }
    }
}

