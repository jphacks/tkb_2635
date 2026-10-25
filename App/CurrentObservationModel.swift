import Foundation
import Observation
import StarCore

@MainActor
@Observable
final class CurrentObservationModel {
    enum Phase {
        case locating, preparing, ready, failed(String)
    }

    private(set) var phase: Phase = .locating
    private(set) var context: SpotContext?
    private(set) var region: ObservationRegion?
    private(set) var accuracy: Double?
    private(set) var isSample = false
    private(set) var regions: [ObservationRegion] = []
    @ObservationIgnored private var calculation: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()

    func configure() {
        do {
            regions = try ObservationRegion.loadBundled()
            if regions.isEmpty { fail("現在地の観測に対応した地域データがありません。") }
        } catch {
            fail("観測地域のデータを読み込めませんでした。")
        }
    }

    func locate() {
        calculation?.cancel()
        revision = UUID()
        context = nil
        region = nil
        accuracy = nil
        isSample = false
        phase = .locating
    }

    func prepare(fix: ObservationLocationFix, scenes: [CityScene], sample: Bool = false) {
        do {
            try fix.validate()
            guard let region = regions.first(where: { $0.contains(latitude: fix.latitude, longitude: fix.longitude) }) else {
                throw ObservationLocationError.outsideRegion
            }
            guard let scene = scenes.first(where: { $0.id == region.sceneId }) else {
                throw ObservationLocationError.missingScene
            }
            calculation?.cancel()
            let revision = UUID()
            self.revision = revision
            context = nil
            self.region = region
            isSample = sample
            accuracy = sample ? nil : fix.horizontalAccuracy
            phase = .preparing
            // 空の遮り方は座標を確定したときだけ計算する。時刻変更・見回しでは再計算しない。
            calculation = Task {
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try region.context(at: fix, scene: scene) }
                }.value
                guard !Task.isCancelled, self.revision == revision else { return }
                switch result {
                case .success(let context):
                    self.context = context
                    self.phase = .ready
                case .failure(let error):
                    self.fail(error.localizedDescription)
                }
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func fail(_ message: String) {
        calculation?.cancel()
        revision = UUID()
        context = nil
        phase = .failed(message)
    }

    func cancel() {
        calculation?.cancel()
        revision = UUID()
    }
}
