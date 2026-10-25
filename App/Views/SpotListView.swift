import StarCore
import SwiftUI
import RealityKit

/// ホーム画面。条件カード → 地図 → 段階ごとの一覧を、夜空の背景の上に縦に並べる
struct SpotResultsView: View {
    @Environment(AppModel.self) private var model
    /// 一覧の行とマップのピンの両方から、同じ詳細画面へ遷移するための経路
    @State private var path = NavigationPath()

    var body: some View {
        let predictions = model.predictions

        NavigationStack(path: $path) {
            // List だと地図のピンチ・ドラッグが行のスクロールとぶつかるので、ScrollView で並べる
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HomeStyle.sectionSpacing) {
                    HomeConditionsCard()

                    if let error = model.weatherLoadError {
                        Label(error, systemImage: "cloud.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HomeMapSection(contexts: model.contexts, predictions: predictions) { id in
                        path.append(id)
                    }

                    ForEach(RecommendationTier.allTiers, id: \.self) { tier in
                        let rows = predictions.filter { $0.tier == tier }
                        if !rows.isEmpty {
                            tierSection(tier, rows: rows)
                        }
                    }

                    if let error = model.loadError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, HomeStyle.margin)
                .padding(.bottom, HomeStyle.sectionSpacing)
            }
            .background { NightSkyBackground() }
            .navigationTitle("Astera")
            .navigationDestination(for: String.self) { id in
                if let context = model.context(id: id) {
                    SpotDetailView(context: context)
                }
            }
            .navigationDestination(for: ComparisonRoute.self) { route in
                if let first = model.context(id: route.firstId), let second = model.context(id: route.secondId) {
                    CompareView(first: first, second: second)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SoundToggleButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isLoadingWeather {
                        ProgressView()
                    } else {
                        Button("天気を更新", systemImage: "arrow.clockwise") {
                            Task { await model.refreshWeather() }
                        }
                    }
                }
            }
            .refreshable { await model.refreshWeather() }
        }
    }

    private func tierSection(_ tier: RecommendationTier, rows: [Prediction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TierHeader(tier: tier, count: rows.count)
            ForEach(rows) { prediction in
                if let context = model.context(id: prediction.spotId) {
                    NavigationLink(value: prediction.spotId) {
                        SpotRow(spot: context.spot, prediction: prediction)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 選択位置は確認画面から戻っても維持する。確定したときだけ観測対象を変える。
struct SpotListView: View {
    @Environment(AppModel.self) private var model
    @State private var centered: String? = "moon"
    @State private var pending: CabinTarget?
    @State private var findingPlaces = false
    private let targets = CabinTarget.catalog

    var body: some View {
        ZStack {
            if !findingPlaces { CabinUniverse().ignoresSafeArea().allowsHitTesting(false) }
            if findingPlaces {
                VStack(spacing: 0) {
                    Button { findingPlaces = false } label: {
                        Label("天体を選び直す", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                    SpotResultsView()
                }
            } else {
                selection.opacity(pending == nil ? 1 : 0)
            }
            if let target = pending {
                confirmation(target).transition(.opacity).zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var selection: some View {
        GeometryReader { geometry in
            let diameter = max(160, min(geometry.size.width * 0.82, geometry.size.height * 0.5))
            ScrollView {
                VStack(spacing: 18) {
                    Text("ASTERA / OBSERVATION DECK")
                        .font(.caption.monospaced()).tracking(3).foregroundStyle(.cyan)
                    Text("宇宙から、星を選ぶ").font(.title2.bold())
                    Text("左右にスライドして、中央の天体をタップ")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(targets) { target in
                                Button {
                                    if centered == target.id {
                                        SoundPlayer.shared.play(.bodySelect)
                                        pending = target
                                    }
                                    else { withAnimation { centered = target.id } }
                                } label: {
                                    CabinPortrait(target: target)
                                        .frame(width: diameter, height: diameter)
                                        .scaleEffect(centered == target.id ? 1 : 0.62)
                                        .opacity(centered == target.id ? 1 : 0.45)
                                }
                                .buttonStyle(.plain).id(target.id)
                                .accessibilityLabel(target.name + "、" + target.kind)
                                .accessibilityHint("中央に合わせて、もう一度押すと選択を確認します")
                            }
                        }.scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, max(0, (geometry.size.width - diameter) / 2), for: .scrollContent)
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $centered, anchor: .center)
                    .frame(height: diameter)
                    VStack(spacing: 6) {
                        Text(targets.first { $0.id == centered }?.name ?? "天体を選択")
                            .font(.title.bold()).multilineTextAlignment(.center)
                        Text(targets.first { $0.id == centered }?.kind ?? "")
                            .font(.caption.monospaced()).tracking(3).foregroundStyle(.cyan)
                        if let credit = targets.first(where: { $0.id == centered })?.imageCredit {
                            Text(credit).font(.caption2).foregroundStyle(.secondary)
                        }
                    }.accessibilityAddTraits(.updatesFrequently)
                    HStack(spacing: 30) {
                        moveButton(-1, symbol: "chevron.left", label: "前の天体")
                        Text("ALIGN • SELECT • EXPLORE")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        moveButton(1, symbol: "chevron.right", label: "次の天体")
                    }
                    Text("天体を選んだら、地球の観測場所へ。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
        .accessibilityHidden(pending != nil).allowsHitTesting(pending == nil)
    }

    private func moveButton(_ direction: Int, symbol: String, label: String) -> some View {
        let index = targets.firstIndex { $0.id == centered } ?? 0
        let next = index + direction
        return Button {
            guard targets.indices.contains(next) else { return }
            withAnimation { centered = targets[next].id }
        } label: {
            Image(systemName: symbol).frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(!targets.indices.contains(next)).accessibilityLabel(label)
    }

    private func confirmation(_ target: CabinTarget) -> some View {
        GeometryReader { geometry in
            let diameter = max(160, min(geometry.size.width - 32, geometry.size.height * 0.52))
            ScrollView {
                VStack(spacing: 18) {
                    Text("選択の確認").font(.caption.monospaced()).foregroundStyle(.cyan)
                    CabinPortrait(target: target).frame(width: diameter, height: diameter)
                    VStack(spacing: 16) {
                        Text(target.name).font(.title.bold())
                        if let credit = target.imageCredit {
                            Text(credit).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("この天体を選択しますか？").font(.headline)
                        if let note = target.note {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            model.target = target.observation
                            pending = nil
                            findingPlaces = true
                            // 推薦の条件を満たす地点が実際にあるときだけ、発見の音を鳴らす
                            if model.predictions.contains(where: { SoundEffect.announcesSpotFound(previous: nil, current: $0.tier) }) {
                                SoundPlayer.shared.play(.spotFound)
                            }
                        } label: {
                            Text("確定").bold().frame(maxWidth: .infinity).padding(12)
                        }
                        .buttonStyle(.borderedProminent).tint(.cyan)
                        Button("戻る") { pending = nil }
                            .buttonStyle(.bordered).controlSize(.large)
                    }
                    .multilineTextAlignment(.center).padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                    .padding(.horizontal, 20)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            }
        }.accessibilityAddTraits(.isModal)
    }
}

/// 星空の背景。Canvas なので、起動した最初の画面から星が出る。確認中も同じ宇宙を表示する。
struct CabinUniverse: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<320 {
                let x = CabinArt.random(index * 4) * size.width
                let y = CabinArt.random(index * 4 + 1) * size.height
                let bright = CabinArt.random(index * 4 + 2)
                let radius = 0.5 + pow(bright, 4) * 1.8
                let tint = CabinArt.random(index * 4 + 3)
                let color = tint < 0.2 ? Color(red: 0.75, green: 0.85, blue: 1)
                    : tint > 0.85 ? Color(red: 1, green: 0.9, blue: 0.75) : .white
                if radius > 2.0 {
                    context.fill(Path(ellipseIn: CGRect(x: x - radius * 2, y: y - radius * 2,
                                                        width: radius * 4, height: radius * 4)),
                                 with: .color(color.opacity(0.12)))
                }
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(color.opacity(0.45 + bright * 0.55)))
            }
        }
        .background(Color(red: 0.008, green: 0.014, blue: 0.04))
        .overlay {
            RadialGradient(colors: [.indigo.opacity(0.2), .clear, .black.opacity(0.5)],
                           center: .topTrailing, startRadius: 10, endRadius: 600)
        }
    }
}
