import StarCore
import SwiftUI

enum CurrentObservationRoute: Hashable { case currentLocation }

/// 現在地を確定し、既存の都市モデルをその位置の目線から見る。
struct CurrentObservationView: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location
    @Environment(\.scenePhase) private var scenePhase
    @State private var observation = CurrentObservationModel()
    @State private var camera = SkyCamera()
    @State private var isActive = false

    var body: some View {
        Group {
            if let context = observation.context {
                observationScene(context)
            } else {
                status
            }
        }
        .background(Color(red: 0.02, green: 0.03, blue: 0.10))
        .navigationTitle(observation.isSample ? "渋谷駅のサンプル" : "現在地から見る")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            isActive = true
            observation.configure()
            if !observation.regions.isEmpty { requestLocation() }
        }
        .onChange(of: location.observationFix) { _, fix in
            guard isActive, case .locating = observation.phase, let fix else { return }
            observation.prepare(fix: fix, scenes: scenes)
        }
        .onChange(of: location.authorization) { _, _ in
            if location.isDenied, case .locating = observation.phase {
                observation.fail("位置情報が許可されていません。設定アプリからAsteraの位置情報を許可してください。")
            }
        }
        .onChange(of: location.errorMessage) { _, error in
            if let error, case .locating = observation.phase { observation.fail(error) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isActive, !observation.isSample,
               case .ready = observation.phase {
                // バックグラウンドで移動した位置を「現在地」として表示し続けない。
                observation.fail("移動している可能性があります。現在地を再取得してください。")
            }
        }
        .task(id: location.isLocating) {
            guard location.isLocating else { return }
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard case .locating = observation.phase else { return }
            location.finishObservationRequest()
            observation.fail("現在地を取得できませんでした。空の開けた屋外でもう一度お試しください。")
        }
        .onDisappear {
            isActive = false
            observation.cancel()
            location.finishObservationRequest()
        }
    }

    private var scenes: [CityScene] { model.contexts.compactMap(\.scene) }

    private var status: some View {
        VStack(spacing: 22) {
            Image(systemName: "location.viewfinder")
                .font(.system(size: 44)).foregroundStyle(.cyan)
            switch observation.phase {
            case .locating:
                ProgressView("現在地を取得中").tint(.white)
            case .preparing:
                ProgressView("現在地からの空を準備中").tint(.white)
            case .failed(let message):
                Text(message).multilineTextAlignment(.center)
                Button("現在地を再取得", systemImage: "location.fill", action: requestLocation)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("current-observation-retry")
                if !observation.regions.isEmpty {
                    Button("渋谷駅のサンプルで試す", action: showSample)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("current-observation-sample")
                }
            case .ready:
                EmptyView()
            }
            if let region = observation.regions.first {
                Text("試作範囲：\(region.name)・中心から約\(Int(region.selectionRadius))m\n地上の屋外で、現在地の目線から空を見回せます。")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func observationScene(_ context: SpotContext) -> some View {
        @Bindable var model = model
        let prediction = Recommender.evaluate(context, target: model.target, date: model.date,
                                              weather: model.weather(for: context.spot),
                                              forecastCoverage: model.forecastCoverage(for: context.spot))
        return ZStack(alignment: .top) {
            if isActive {
                Sky3DView(context: context, prediction: prediction, date: model.date,
                          sharedCamera: $camera, showsLegend: false)
                    .ignoresSafeArea(edges: .bottom)
            }
            VStack(spacing: 12) {
                TimeSlider(date: $model.date, compact: true)
                HStack {
                    Label(observation.isSample ? "サンプル位置の目線" : "現在地の目線", systemImage: "person.fill.viewfinder")
                        .font(.caption.bold())
                    Spacer()
                    if let accuracy = observation.accuracy {
                        Text("位置の誤差 約\(Int(accuracy.rounded()))m").font(.caption)
                    }
                }
                HStack {
                    Text(visibilityText(prediction)).font(.subheadline.bold())
                    Spacer()
                    Button("天体の方向へ", systemImage: "scope") { faceTarget(prediction) }
                        .font(.caption.bold()).buttonStyle(.bordered)
                }
                Text("ドラッグで見回す・ピンチで拡大")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(observation.isSample ? "サンプル：渋谷駅東側" : "取得した現在地・地上")
                        .font(.caption.bold())
                    Spacer()
                    Button("現在地を再取得", systemImage: "location.fill", action: requestLocation)
                        .font(.caption).buttonStyle(.bordered)
                }
                Text("目線の高さ \(ObservationRegion.eyeHeight.formatted())m・立入条件と周辺照明は未確認")
                    .font(.caption2).foregroundStyle(.secondary)
                if let region = observation.region {
                    Text("周辺約\(Int(region.buildingRadius))mの建物と地形による試作です。遠方の建物・樹木・現況の違いは反映できません。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .onAppear {
            camera.mode = .observer
            faceTarget(prediction)
        }
    }

    private func visibilityText(_ prediction: Prediction) -> String {
        if prediction.skyTooBright { return "空が明るく、見えにくい時間帯" }
        if prediction.altitude <= 0 { return "\(model.target.name)は地平線の下" }
        return prediction.geometricVisibility ? "\(model.target.name)の方向は開けている見込み" : "\(model.target.name)は遮られる見込み"
    }

    private func requestLocation() {
        observation.locate()
        guard !location.isDenied else {
            observation.fail("位置情報が許可されていません。設定アプリからAsteraの位置情報を許可してください。")
            return
        }
        location.start(precise: true)
    }

    private func showSample() {
        guard let region = observation.regions.first else { return }
        location.finishObservationRequest()
        observation.prepare(fix: ObservationLocationFix(
            latitude: region.sampleLatitude, longitude: region.sampleLongitude,
            horizontalAccuracy: 0, timestamp: Date()), scenes: scenes, sample: true)
    }

    private func faceTarget(_ prediction: Prediction) {
        camera.observer = ObserverViewpoint(
            target: HorizontalCoord(altitude: prediction.altitude, azimuth: prediction.azimuth),
            fieldOfView: camera.observer.fieldOfView)
    }
}
