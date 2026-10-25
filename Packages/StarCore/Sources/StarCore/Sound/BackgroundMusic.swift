import Foundation

/// アプリ全体で流す BGM。音のファイルは App/Resources/Sounds/ にある。
public enum BackgroundMusic {
    /// 拡張子を除いたファイル名（全体bgm.mp3 を AAC に変換したもの）
    public static let fileName = "bgm_main"
    public static let fileExtension = "m4a"
    /// 再生する音量 [0, 1]。元の音源が大きめなので、効果音より奥で静かに流れる大きさにする
    public static let volume: Float = 0.2
    /// 起動の効果音と重ならないよう、少し待ってから流し始める [秒]
    public static let startDelay: TimeInterval = 1.2
    /// 流し始め・止めるときに、ゆっくり大きく・小さくする時間 [秒]
    public static let fadeInDuration: TimeInterval = 3
    public static let fadeOutDuration: TimeInterval = 0.8
}
