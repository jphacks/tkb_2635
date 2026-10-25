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
    /// 起動直後は RealityView が空のまま出ることがあるので、画面が落ち着いてから作る
    @State private var ready = false
    var body: some View {
        if target.isConstellation {
            Canvas { context, size in
                let points = target.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                for edge in target.edges {
                    var line = Path()
                    for (index, vertex) in edge.enumerated() {
                        if index == 0 { line.move(to: points[vertex]) }
                        else { line.addLine(to: points[vertex]) }
                    }
                    context.stroke(line, with: .color(.cyan.opacity(0.75)), lineWidth: 1.5)
                }
                for point in points {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 8,y: point.y - 8,width: 16,height: 16)),
                                 with: .color(.cyan.opacity(0.15)))
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 3,y: point.y - 3,width: 6,height: 6)),
                                 with: .color(.white))
                }
            }
        } else if ready {
            RealityView { content in
                let sphere = ModelEntity(
                    mesh: .generateSphere(radius: target.kind == "STAR" ? 0.28 : 0.65),
                    materials: [SimpleMaterial(color: target.id == "planet-mars" ? .orange : .lightGray,
                                               isMetallic: false)])
                sphere.position = SIMD3(0, 0, -3)
                let light = DirectionalLight()
                light.light.intensity = 1800
                light.look(at: SIMD3<Float>(0, 0, -3), from: SIMD3<Float>(-2, 3, 0), relativeTo: nil)
                content.add(sphere)
                content.add(light)
            }
            .allowsHitTesting(false)
        } else {
            Color.clear.task {
                try? await Task.sleep(for: .milliseconds(300))
                ready = true
            }
        }
    }
}

struct CabinWindowFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 90)
            .stroke(LinearGradient(colors: [.gray, .black, .gray.opacity(0.8)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 24)
            .overlay(RoundedRectangle(cornerRadius: 80).stroke(.cyan.opacity(0.5), lineWidth: 2).padding(11))
            .overlay(alignment: .top) {
                Text("OBSERVATION WINDOW").font(.caption2.monospaced()).tracking(3)
                    .foregroundStyle(.cyan.opacity(0.7)).padding(.top, 18)
            }
            .padding(.horizontal, 16)
            .shadow(color: .black, radius: 18)
    }
}

/// 奥行きを持つ星の粒を RealityKit で配置する。確認中も同じ宇宙を表示する。
struct CabinUniverse: View {
    var body: some View {
        RealityView { content in
            let root = Entity()
            let material = UnlitMaterial(color: .white)
            for index in 0..<360 {
                let angle = Float(index) * 2.399963
                let depth = Float(index % 23) * 0.4
                let radius = 1.0 + Float(index % 31) * 0.15
                let star = ModelEntity(mesh: .generateSphere(radius: index % 13 == 0 ? 0.012 : 0.004),
                                       materials: [material])
                star.position = SIMD3(cos(angle) * radius, sin(angle) * radius, -3 - depth)
                root.addChild(star)
            }
            content.add(root)
        }
        .background(Color(red: 0.008, green: 0.014, blue: 0.04))
        .overlay {
            RadialGradient(colors: [.indigo.opacity(0.2), .clear, .black.opacity(0.5)],
                           center: .topTrailing, startRadius: 10, endRadius: 600)
        }
    }
}


