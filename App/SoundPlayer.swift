import AVFoundation
import StarCore

/// 効果音と BGM を鳴らす。音量と続けて鳴らせる間隔は StarCore の SoundEffect・BackgroundMusic で決める。
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    /// 音（効果音と BGM）の ON/OFF を覚えておく設定の名前（@AppStorage と共通）
    static let enabledKey = "soundEffectsEnabled"

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var throttle = SoundThrottle()
    /// 起動の演出が終わったか。終わる前にアプリが前面に来ても、BGM を先に流さない
    private var hasStartedUp = false

    private init() {
        // ambient にすると、マナーモード（消音スイッチ）のときは鳴らさず、ほかのアプリの音楽も止めない
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for effect in SoundEffect.allCases {
            guard let url = Bundle.main.url(forResource: effect.fileName, withExtension: "caf"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.volume = effect.playbackVolume
            // 押した瞬間に鳴るよう、先に読み込んでおく
            player.prepareToPlay()
            players[effect] = player
        }
        if let url = Bundle.main.url(forResource: BackgroundMusic.fileName, withExtension: BackgroundMusic.fileExtension),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            musicPlayer = player
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

    /// 起動したとき。起動の効果音のあとに、BGM をゆっくり流し始める
    func startUp() async {
        play(.launch)
        try? await Task.sleep(for: .seconds(BackgroundMusic.startDelay))
        hasStartedUp = true
        updateMusic()
    }

    /// ON/OFF の設定に合わせて BGM を流す・止める。アプリに戻ったときにも呼ぶ
    func updateMusic() {
        guard hasStartedUp, let musicPlayer else { return }
        if isEnabled {
            guard !musicPlayer.isPlaying else { return }
            musicPlayer.play()
            musicPlayer.setVolume(BackgroundMusic.volume, fadeDuration: BackgroundMusic.fadeInDuration)
        } else if musicPlayer.isPlaying {
            musicPlayer.setVolume(0, fadeDuration: BackgroundMusic.fadeOutDuration)
            Task {
                try? await Task.sleep(for: .seconds(BackgroundMusic.fadeOutDuration))
                // 小さくしている間にまたオンにされたら止めない
                if !isEnabled { musicPlayer.pause() }
            }
        }
    }
}
