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


    
/// 選択位置と確認状態を別々に保持し、戻る操作で位置を変えない。
struct SpotListView: View {
    @Environment(AppModel.self) private var model
    @State private var centered: String? = "moon"
    @State private var pending: CabinTarget?
    @State private var findingPlaces = false
    private let targets = CabinTarget.catalog

    var body: some View {
        ZStack {
            if !findingPlaces {
                CabinUniverse().ignoresSafeArea().allowsHitTesting(false)
            }
            if findingPlaces {
                VStack(spacing: 0) {
                    Button {
                        findingPlaces = false
                    } label: {
                        Label("天体を選び直す", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                    SpotResultsView()
                }
            } else {
                selection
            }
            if let target = pending {
                confirmation(target)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var selection: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let windowHeight = min(geometry.size.height * 0.53, 460)
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("ASTERA / OBSERVATION DECK")
                        .font(.caption.monospaced()).tracking(3).foregroundStyle(.cyan)
                    Text("窓の向こうの、星を選ぶ").font(.title2.bold())
                    Text("左右にスライドして、中央の天体をタップ")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                ZStack {
                    RoundedRectangle(cornerRadius: 90)
                        .fill(.black.opacity(0.12))
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
                                    VStack(spacing: 20) {
                                        CabinPortrait(target: target)
                                            .frame(width: width * 0.54, height: windowHeight * 0.55)
                                        Text(target.name).font(.title.bold())
                                        Text(target.kind).font(.caption).tracking(3).foregroundStyle(.cyan)
                                    }
                                    .frame(width: width, height: windowHeight)
                                    .scaleEffect(centered == target.id ? 1 : 0.76)
                                    .opacity(centered == target.id ? 1 : 0.4)
                                    .animation(.easeInOut(duration: 0.25), value: centered)
                                }
                                .buttonStyle(.plain)
                                .id(target.id)
                                .accessibilityLabel(target.name + "、" + target.kind)
                                .accessibilityHint("中央に合わせて、もう一度押すと選択を確認します")
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $centered, anchor: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 90))
                    CabinWindowFrame()
                        .allowsHitTesting(false)
                }
                .frame(height: windowHeight)
                HStack(spacing: 30) {
                    moveButton(-1, symbol: "chevron.left", label: "前の天体")
                    Text("ALIGN • SELECT • EXPLORE")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    moveButton(1, symbol: "chevron.right", label: "次の天体")
                }
                Text("天体を選んだら、地球の観測場所へ。")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .accessibilityHidden(pending != nil)
        .allowsHitTesting(pending == nil)
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
        .disabled(!targets.indices.contains(next))
        .accessibilityLabel(label)
    }

    private func confirmation(_ target: CabinTarget) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Text("選択の確認").font(.caption.monospaced()).foregroundStyle(.cyan)
                    CabinPortrait(target: target).frame(height: 180)
                    Text(target.name).font(.largeTitle.bold())
                    Text("この天体を選択しますか？").font(.headline)
                    if let note = target.note {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
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
                        Text("確定").bold().frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(.borderedProminent).tint(.cyan)
                    Button("戻る") { pending = nil }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34))
                .overlay(RoundedRectangle(cornerRadius: 34).stroke(.cyan.opacity(0.3)))
                .padding(24)
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}



