import AVFoundation
import StarCore

/// 効果音を鳴らす。音量と続けて鳴らせる間隔は StarCore の SoundEffect で決める。
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    /// 効果音の ON/OFF を覚えておく設定の名前（@AppStorage と共通）
    static let enabledKey = "soundEffectsEnabled"

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private var throttle = SoundThrottle()

    private init() {
        // ambient にすると、マナーモード（消音スイッチ）のときは鳴らさず、ほかのアプリの音楽も止めない
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for effect in SoundEffect.allCases {
            guard let url = Bundle.main.url(forResource: effect.fileName, withExtension: "caf"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.volume = effect.volume
            // 押した瞬間に鳴るよう、先に読み込んでおく
            player.prepareToPlay()
            players[effect] = player
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func play(_ effect: SoundEffect) {
        guard isEnabled, let player = players[effect], throttle.allows(effect) else { return }
        player.currentTime = 0
        player.play()
    }
}
