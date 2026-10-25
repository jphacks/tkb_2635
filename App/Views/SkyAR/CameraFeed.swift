@preconcurrency import AVFoundation
import Observation
import StarCore
import SwiftUI

/// 背面カメラの映像。許可を聞き、映像を流し、画角を調べる。
@MainActor
@Observable
final class CameraFeed {
    enum State { case idle, running, denied, unavailable }

    private(set) var state = State.idle
    /// 縦向きの画面での縦方向の画角 [度]。取れなければ標準の値
    private(set) var verticalFieldOfView = CameraProjector.defaultVerticalFieldOfView
    @ObservationIgnored let runner = SessionRunner()

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return state = .denied }
        default:
            return state = .denied
        }
        guard let fieldOfView = runner.configure() else { return state = .unavailable }
        verticalFieldOfView = fieldOfView
        runner.start()
        state = .running
    }

    func stop() {
        runner.stop()
        if state == .running { state = .idle }
    }
}

/// カメラの開始・停止は時間がかかるので、専用のキューで行う
final class SessionRunner: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "astera.camera")

    /// カメラをつなぐ。つなげたら縦方向の画角 [度]（センサーの長辺）を返す
    func configure() -> Double? {
        guard session.inputs.isEmpty else { return nil }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)
        return Double(device.activeFormat.videoFieldOfView)
    }

    func start() {
        queue.async { [session] in if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }
}

/// カメラ映像を画面いっぱいに映す（SwiftUI にはカメラ映像の部品が無いので、この 1 か所だけ UIKit の部品を橋渡しする）
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            // アプリは縦向きだけ。カメラ映像を縦向きにそろえる
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
