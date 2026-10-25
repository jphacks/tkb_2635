import CoreMotion
import Observation
import StarCore

/// スマホの向きを読み続け、空へ向けたら知らせる。詳細画面が見えている間だけ動かす。
@MainActor
@Observable
final class DeviceMotionMonitor {
    /// 最新の姿勢。AR の画面だけがこれを読む（詳細画面は読まないので、向きが変わっても作り直されない）
    private(set) var attitude: DeviceAttitude?
    /// 空へ向けたとき（`SkyARTrigger` の判定）。AR を開く側が決める
    @ObservationIgnored var onLookUp: (() -> Void)?

    @ObservationIgnored private let manager = CMMotionManager()
    /// 画面を開いたときに上を向けていても、すぐには開かない
    @ObservationIgnored private var trigger = SkyARTrigger(isArmed: false)
    private static let updateInterval = 1.0 / 30

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        // 真北が取れないとき（位置情報が使えないとき）は磁北で代える。東京では真北と約 8° ずれる
        let frame: CMAttitudeReferenceFrame = CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical)
            ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        manager.deviceMotionUpdateInterval = Self.updateInterval
        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let m = motion?.attitude.rotationMatrix else { return }
            MainActor.assumeIsolated { self?.receive(m) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        attitude = nil
        trigger = SkyARTrigger(isArmed: false)
    }

    private func receive(_ m: CMRotationMatrix) {
        let next = DeviceAttitude(m11: m.m11, m12: m.m12, m13: m.m13,
                                  m21: m.m21, m22: m.m22, m23: m.m23,
                                  m31: m.m31, m32: m.m32, m33: m.m33)
        attitude = next
        if trigger.shouldEnter(lookElevation: next.lookElevation) { onLookUp?() }
    }
}
