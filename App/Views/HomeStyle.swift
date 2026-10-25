import SwiftUI
import StarCore

/// ホーム画面の余白・色。数字はここだけに置く
enum HomeStyle {
    static let listDivider = Color(red: 0.48, green: 0.54, blue: 0.65).opacity(0.28)
    static let listSilver = Color(red: 0.85, green: 0.88, blue: 0.93)
    static let margin: CGFloat = 16
    static let sectionSpacing: CGFloat = 22
    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 16
    /// 夜空の上に重ねるカードの面と縁（背景の星が透けすぎない濃さ）
    static let cardFill = Color(red: 0.10, green: 0.12, blue: 0.22).opacity(0.88)
    static let cardStroke = Color.white.opacity(0.09)
    /// 見出しの天体名に使う淡い月の色
    static let moonlight = Color(red: 0.98, green: 0.87, blue: 0.60)
    /// 夜空のグラデーション（上: 藍、下: ほぼ黒の紺）
    static let skyTop = Color(red: 0.07, green: 0.09, blue: 0.20)
    static let skyBottom = Color(red: 0.01, green: 0.02, blue: 0.05)
    /// 地図の上に置く丸いボタンの面（地図の色に埋もれない濃さ）
    static let mapButtonFill = Color.black.opacity(0.6)
}

/// 同じ幅の2つの選択肢。背景だけを移動させ、件数が変わっても位置を保つ。
struct SpotListTabs: View {
    private let motion = MotionSetting()
    @Binding var selection: SpotListGroup
    let entries: [SpotListEntry]
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SpotListGroup.allCases, id: \.self) { group in
                let selected = selection == group
                let count = entries.filter { group.contains($0.prediction.tier) }.count
                Button {
                    withAnimation(motion.isReduced ? nil : .easeInOut(duration: 0.28)) { selection = group }
                } label: {
                    HStack(spacing: 9) {
                        Text(group == .recommended ? "おすすめ" : "要確認")
                        Text("\(count)").monospacedDigit()
                    }
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : HomeStyle.listSilver.opacity(0.6))
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if selected {
                            Capsule()
                                .fill(.white.opacity(0.10))
                                .overlay(Capsule().strokeBorder(
                                    LinearGradient(colors: [HomeStyle.listSilver, .white.opacity(0.25)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                                .shadow(color: .white.opacity(0.12), radius: 8)
                                .matchedGeometryEffect(id: "selected", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group == .recommended ? "おすすめ" : "要確認")、\(count)か所")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(.black.opacity(0.22), in: Capsule())
        .overlay(Capsule().strokeBorder(HomeStyle.listDivider, lineWidth: 1))
    }
}

struct SpotListTools: View {
    @Binding var order: SpotListOrder
    @Binding var category: SpotCategory?
    let locationAvailable: Bool

    var body: some View {
        HStack(spacing: 16) {
            Menu {
                Picker("並べ替え", selection: $order) {
                    Text("近い順").tag(SpotListOrder.nearest)
                    Text("観測スコア順").tag(SpotListOrder.score)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(order == .score ? "観測スコア順" : locationAvailable ? "近い順" : "距離未取得")
                    Image(systemName: "chevron.down").font(.caption)
                }.frame(minHeight: 44)
            }
            .accessibilityLabel("並べ替え")
            Rectangle().fill(HomeStyle.listDivider).frame(height: 1)
            Menu {
                Picker("地点の種類", selection: $category) {
                    Text("すべての種類").tag(SpotCategory?.none)
                    ForEach(SpotCategory.allCases, id: \.self) { value in
                        Text(value.label).tag(Optional(value))
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(category == nil ? HomeStyle.listSilver : .white)
                    .overlay(alignment: .topTrailing) {
                        if category != nil { Circle().fill(.white).frame(width: 5, height: 5) }
                    }
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("絞り込み、\(category?.label ?? "すべての種類")")
        }
        .font(.subheadline)
        .foregroundStyle(HomeStyle.listSilver)
        .buttonStyle(.plain)
    }
}

extension View {
    /// 夜空に浮かぶ半透明のカード
    func homeCard(padding: CGFloat = HomeStyle.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeStyle.cardFill, in: .rect(cornerRadius: HomeStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: HomeStyle.cardRadius).stroke(HomeStyle.cardStroke))
    }
}

/// 藍から黒へのグラデーションに、薄い星を散らした背景
struct NightSkyBackground: View {
    private static let starCount = 90
    /// 毎回同じ並びになるように固定の種から星を置く
    private static let seed: UInt64 = 2635

    var body: some View {
        LinearGradient(colors: [HomeStyle.skyTop, HomeStyle.skyBottom], startPoint: .top, endPoint: .bottom)
            .overlay {
                Canvas { context, size in
                    var generator = SeededGenerator(seed: Self.seed)
                    for _ in 0..<Self.starCount {
                        let x = Double.random(in: 0...1, using: &generator) * size.width
                        // 星は画面の上 6 割に多く置く（地平線に向かって減る）
                        let y = pow(Double.random(in: 0...1, using: &generator), 1.6) * size.height * 0.6
                        let radius = Double.random(in: 0.4...1.2, using: &generator)
                        let opacity = Double.random(in: 0.15...0.55, using: &generator)
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                                     with: .color(.white.opacity(opacity)))
                    }
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// 件数はフィルター後の実データ。推薦されない地点も元の状態ラベルで残す。
struct SpotResultsList: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location
    @State private var group: SpotListGroup = .recommended
    @State private var order: SpotListOrder = .nearest
    @State private var category: SpotCategory?
    let predictions: [Prediction]
    /// 行を押したときに、その地点の ID を渡す（シートの中からは画面を進められないので、進むのは呼び出し側に任せる）
    let onSelect: (String) -> Void

    var body: some View {
        let entries = SpotListPresentation.entries(contexts: model.contexts, predictions: predictions,
                                                   distance: { location.distanceKm(to: $0) })
        let filtered = SpotListPresentation.filtered(entries, category: category)
        let rows = SpotListPresentation.rows(filtered, group: group, order: order)
        VStack(alignment: .leading, spacing: 14) {
            SpotListTabs(selection: $group, entries: filtered)
            SpotListTools(order: $order, category: $category, locationAvailable: location.coordinate != nil)
            if let category {
                HStack {
                    Text("\(category.label)で絞り込み中").foregroundStyle(.secondary)
                    Spacer()
                    Button("解除") { self.category = nil }
                }.font(.caption)
            }
            if order == .nearest && location.coordinate == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("現在地が未取得のため、判定・スコア順で表示しています。")
                    if location.isDenied {
                        Text("距離を表示するには、設定で位置情報を許可してください。")
                    } else {
                        Button("現在地を取得") { location.start() }.frame(minHeight: 44)
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if group == .review {
                Text("要確認には、見えない見込み・利用不可の地点も含みます。各地点の状態を確認してください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group == .recommended ? "おすすめの地点はありません" : "該当する地点はありません")
                        .font(.headline)
                    Text("日時・天体・絞り込み条件を変更すると、結果が変わります。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if group == .recommended {
                        Button("要確認の地点を見る") { group = .review }.frame(minHeight: 44)
                    }
                }.padding(.vertical, 20)
            }
            LazyVStack(spacing: 0) {
                ForEach(rows) { entry in
                    Button { onSelect(entry.id) } label: {
                        SpotRow(spot: entry.spot, prediction: entry.prediction, distanceKm: entry.distanceKm)
                    }.buttonStyle(.plain)
                    Rectangle().fill(HomeStyle.listDivider).frame(height: 1).accessibilityHidden(true)
                }
            }
            Text("写真：地理院タイル等による周辺航空写真（夜間色に加工）。施設の外観写真ではありません。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// 種を固定した乱数（SplitMix64）。背景の星の位置を毎回そろえるために使う
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

