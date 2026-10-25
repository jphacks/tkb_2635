import StarCore
import SwiftUI

enum CurrentObservationRoute: Hashable, Identifiable {
    case currentLocation
    case demo(String)

    var demoRegionID: String? {
        if case .demo(let id) = self { return id }
        return nil
    }

    var id: String { demoRegionID.map { "demo-\($0)" } ?? "current-location" }
}

/// 現在地を確定し、既存の都市モデルをその位置の目線から見る。
struct CurrentObservationView: View {
    var demoRegionID: String? = nil
    @Environment(AppModel.self) private var model
    @Environment(LocationModel.self) private var location
    @Environment(\.scenePhase) private var scenePhase
    @State private var observation = CurrentObservationModel()
    @State private var camera = SkyCamera()
    @State private var isActive = false
    @State private var leftAppWhileObserving = false
    @State private var showsAR = false
    @State private var motionMonitor = DeviceMotionMonitor()

    var body: some View {
        Group {
            if let context = observation.context {
                observationScene(context)
            } else {
                status
            }
        }
        .background(Color(red: 0.02, green: 0.03, blue: 0.10))
        .navigationTitle(observation.isSample ? (observation.region?.sampleLabel ?? "デモ現在地") : "現在地から見る")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $showsAR, onDismiss: { motionMonitor.stop() }) {
            if let context = observation.context {
                SkyARView(context: context, monitor: motionMonitor, observationDate: model.date,
                          locationLabel: observation.isSample
                            ? "デモ現在地：\(observation.region?.sampleLabel ?? "")" : "取得した現在地",
                          isDemo: observation.isSample) { showsAR = false }
                    .onAppear { motionMonitor.start() }
                    .onDisappear { motionMonitor.stop() }
            } else {
                Button("3D表示へ戻る") { showsAR = false }
            }
        }
        .task {
            isActive = true
            guard observation.regions.isEmpty else { return }
            observation.configure()
            if let demoRegionID, let region = observation.regions.first(where: { $0.id == demoRegionID }) {
                showSample(region)
            } else if demoRegionID != nil {
                observation.fail("指定されたデモ地点のデータがありません。")
            } else if !observation.regions.isEmpty {
                requestLocation()
            }
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
            if phase == .background, isActive, !observation.isSample,
               case .ready = observation.phase {
                leftAppWhileObserving = true
            } else if phase == .active, leftAppWhileObserving {
                leftAppWhileObserving = false
                // バックグラウンドで移動した位置を「現在地」として表示し続けない。
                // 位置情報の許可ダイアログによる一時的な inactive は移動と見なさない。
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
                ForEach(observation.regions) { region in
                    Button("\(region.sampleLabel)で試す") { showSample(region) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("current-observation-sample-\(region.id)")
                }
            case .ready:
                EmptyView()
            }
            if !observation.regions.isEmpty {
                Text("試作範囲：" + observation.regions.map { "\($0.name)・約\(Int($0.selectionRadius))m" }.joined(separator: "／")
                     + "\n地上の屋外で、現在地の目線から空を見回せます。")
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
            if isActive && !showsAR {
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
                Button {
                    showsAR = true
                } label: {
                    Label("ARで空を見る", systemImage: "camera.viewfinder")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("current-observation-open-ar")
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(observation.isSample ? "デモ現在地：\(observation.region?.sampleLabel ?? "")" : "取得した現在地・地上")
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

    private func showSample(_ region: ObservationRegion) {
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
