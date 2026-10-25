import StarCore
import SwiftUI

/// ホーム画面。23 区の 3D（または 2D の地図）を画面いっぱいに出し、上に日時・天体の操作、
/// 下に地点の一覧のシート（iOS 標準）を重ねる。形は地点の詳細（SpotDetailView）と同じ。
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location
    /// 天体を選ぶ画面へ戻る
    let onBack: () -> Void

    /// 一覧の行とピンの両方から、同じ詳細画面へ遷移するための経路
    @State private var path = NavigationPath()
    @State private var mode = HomeMapMode.city3D
    /// 3D の向き。3D を外している間も覚えておき、戻したとき同じ向きで出す
    @State private var camera = WideCityCamera()
    /// 詳細へ進んで隠れている間は 3D を外す（詳細の 3D と同時に描くと、描画用のメモリが足りなくなる）
    @State private var isOnScreen = false
    /// 一覧のシートを出しているか。この画面が見えている間だけ出す
    @State private var isSheetShown = false
    @State private var sheetDetent = HomeSheet.collapsedDetent
    /// シートを閉じ終えてから進む先。シートを出したままでは、その下の画面を進められない
    @State private var pendingExit: HomeExit?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                // シートを全開にしている間は 3D がほぼ隠れるので外し、シートのスクロールと描画を取り合わないようにする
                HomeBackground(mode: mode, camera: $camera,
                               isActive: isOnScreen && sheetDetent != HomeSheet.largeDetent,
                               bottomInset: HomeSheet.coveredHeight) { leave(to: .spot($0)) }
                HomeOverlay(mode: $mode)
            }
            .navigationTitle("Astera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $isSheetShown, onDismiss: performPendingExit) {
                HomeSheet(detent: $sheetDetent) { leave(to: .spot($0)) }
                    .environment(model)
                    .environment(location)
            }
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
            .onAppear {
                isOnScreen = true
                isSheetShown = true
            }
            .onDisappear {
                isOnScreen = false
                isSheetShown = false
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("天体を選び直す", systemImage: "chevron.left") { leave(to: .back) }
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

    /// シートを閉じてから進む。閉じ終わり（onDismiss）で performPendingExit が呼ばれる
    private func leave(to exit: HomeExit) {
        pendingExit = exit
        if isSheetShown {
            isSheetShown = false
        } else {
            performPendingExit()
        }
    }

    private func performPendingExit() {
        guard let exit = pendingExit else { return }
        pendingExit = nil
        switch exit {
        case .spot(let id): path.append(id)
        case .back: onBack()
        }
    }
}

/// ホームのシートを閉じたあとに進む先
private enum HomeExit {
    /// 地点の詳細
    case spot(String)
    /// 天体を選ぶ画面
    case back
}

/// ホームの上に重ねる、日時・天体・表示の切り替え（詳細画面の時刻スライダーと同じ大きさ）
struct HomeOverlay: View {
    @Environment(AppModel.self) private var model
    @Binding var mode: HomeMapMode

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HomeHeadline()
                Spacer(minLength: 8)
                Picker("表示", selection: $mode) {
                    ForEach(HomeMapMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            TimeSlider(date: $model.date, compact: true)
            Group {
                if let message = model.forecastOutOfRangeMessage {
                    ForecastOutOfRangeNote(message: message)
                }
                if let error = model.weatherLoadError {
                    Label(error, systemImage: "cloud.slash")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}
