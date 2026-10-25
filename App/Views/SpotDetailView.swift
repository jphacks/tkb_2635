import StarCore
import SwiftUI

/// 地点の詳細。3D を画面いっぱいに出し、上に時刻スライダー、下に引き上げるシート（iOS 標準）を重ねる。
struct SpotDetailView: View {
    @Environment(AppModel.self) private var model
    let context: SpotContext
    /// 比較画面へ進んで隠れている間は 3D を外す。3D を3つ同時に描くと、描画用のメモリが足りなくなる。
    @State private var isOnScreen = false
    /// 3D の向き。全開のあいだ 3D を外しても、戻したとき同じ向きで出す
    @State private var camera = SkyCamera()
    /// 情報のシートを出しているか。この画面が見えている間だけ出す
    @State private var isSheetShown = false
    @State private var sheetDetent: PresentationDetent = .height(Self.collapsedHeight)
    /// 比較ボタンを押したとき、シートを閉じ終えてから進む先
    @State private var pendingComparison: ComparisonRoute?
    @State private var comparison: ComparisonRoute?

    /// シートをいちばん下にしたときの高さ（地点名。比較ボタンがあるときは、その分高くする）。
    /// 判定はシートの中に出すので、たたんだときは見出しだけにして 3D を広く見せる
    private static let collapsedHeight: CGFloat = 62
    private static let collapsedHeightWithCompare: CGFloat = 90
    /// 半分まで引き上げたときの、画面の高さに対する割合
    private static let mediumDetent = PresentationDetent.fraction(0.48)
    /// 3D を作り直したあと、描き直させるまでの待ち時間（街の読み込みが終わる前後で2回）
    private static let redrawDelays: [Duration] = [.milliseconds(500), .milliseconds(1500)]
    /// 描き直させるために向きを変える量（ラジアン。目には見えない）
    private static let redrawNudge: Float = 0.0001
    /// いちばん上まで引き上げたとき。上に 3D を少し残す
    private static let largeDetent = PresentationDetent.fraction(0.9)

    var body: some View {
        @Bindable var model = model
        let prediction = Recommender.evaluate(context, target: model.target, date: model.date,
                                              weather: model.weather(for: context.spot),
                                              forecastCoverage: model.forecastCoverage(for: context.spot))

        ZStack {
            Group {
                // シートを全開にしている間は 3D がほぼ隠れるので外し、シートのスクロールと描画を取り合わないようにする
                if isOnScreen && sheetDetent != Self.largeDetent {
                    Sky3DView(context: context, prediction: prediction, date: model.date,
                              sharedCamera: $camera, showsLegend: false)
                } else {
                    Color(red: 0.02, green: 0.03, blue: 0.10)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            VStack {
                TimeSlider(date: $model.date, compact: true)
                    .disabled(camera.mode == .entering)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                if let message = model.forecastCoverage(for: context.spot).message {
                    ForecastOutOfRangeNote(message: message)
                        .padding(.horizontal, 16)
                }
                // 判定は下のシートに出す。出典は利用の条件なので、3D の説明を消しても残す
                if context.scene.map(CityModelRenderer.hasModel) == true {
                    Text(SkyRenderer.credit)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 16)
                }
                if context.scene?.observerViewEnabled == true {
                    SkyViewControls(camera: $camera,
                                    target: HorizontalCoord(altitude: prediction.altitude, azimuth: prediction.azimuth),
                                    showsObstructionGuide: !prediction.geometricVisibility && !prediction.blockedByDirectionMask && prediction.altitude > 0,
                                    entryIsBuilding: context.spot.hostBuildingId != nil)
                        .padding(10)
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        .padding(.horizontal, 12)
                }
                Spacer()
            }
        }
        .navigationTitle(context.spot.name)
        .navigationBarTitleDisplayMode(.inline)
        // シートは iOS 標準のものを使う。自作のシートは 3D の上で動かすと実機で引っかかった
        .sheet(isPresented: $isSheetShown, onDismiss: openPendingComparison) {
            sheet(prediction: prediction)
        }
        .navigationDestination(item: $comparison) { route in
            if let partner = model.context(id: route.secondId) {
                CompareView(first: context, second: partner)
            }
        }
        .onAppear {
            isOnScreen = true
            isSheetShown = true
        }
        .onChange(of: sheetDetent) { old, _ in
            guard old == Self.largeDetent else { return }
            // 3D を作り直した直後は、何か動くまで真っ暗なことがある。見えないほど少しだけ向きを変えて描かせる
            Task {
                for delay in Self.redrawDelays {
                    try? await Task.sleep(for: delay)
                    camera.yaw += Self.redrawNudge
                }
            }
        }
        .onDisappear {
            isOnScreen = false
            isSheetShown = false
        }
    }

    private func sheet(prediction: Prediction) -> some View {
        let partner = model.contexts.comparisonPartner(of: context)
        let collapsed = PresentationDetent.height(partner == nil ? Self.collapsedHeight : Self.collapsedHeightWithCompare)
        return VStack(spacing: 0) {
            SpotSheetHeader(spot: context.spot, targetName: model.target.name, partner: partner) { route in
                // シートを出したままでは、その下の画面を進められない。閉じ終えてから進む
                pendingComparison = route
                isSheetShown = false
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 10)
            SpotInfoList(context: context, prediction: prediction)
        }
        .environment(model)
        .presentationDetents([collapsed, Self.mediumDetent, Self.largeDetent], selection: $sheetDetent)
        // 半分までなら、シートの裏の 3D・時刻スライダー・戻るボタンも触れる
        .presentationBackgroundInteraction(.enabled(upThrough: Self.mediumDetent))
        .presentationBackground(Color(.systemGroupedBackground))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .onAppear {
            // 比較ボタンの有無で見出しの高さが変わるので、たたんだ高さもそれに合わせる
            if sheetDetent != Self.mediumDetent && sheetDetent != Self.largeDetent { sheetDetent = collapsed }
        }
    }

    private func openPendingComparison() {
        comparison = pendingComparison
        pendingComparison = nil
    }
}

/// シートをいちばん下にしたときにも見える、地点名と比較画面へのボタン。
/// 判定はシートの中（SpotInfoList の「判定」）に出し、たたんだときは 3D を広く見せる。
struct SpotSheetHeader: View {
    let spot: Spot
    let targetName: String
    /// spots.json の comparisonSpotId に書かれた比較相手。nil ならボタンを出さない。
    let partner: SpotContext?
    /// 比較ボタンを押したとき。シートの中からは画面を進められないので、進むのは呼び出し側に任せる
    let onCompare: (ComparisonRoute) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(spot.name)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let partner {
                Button {
                    onCompare(ComparisonRoute(firstId: spot.id, secondId: partner.id))
                } label: {
                    Label("\(partner.spot.name)と比べる", systemImage: "rectangle.split.2x1")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("同じ時刻の\(targetName)が、目の高さでどう変わるかを並べて見られます")
            }
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value)).monospacedDigit()
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: value)
        }
    }
}
