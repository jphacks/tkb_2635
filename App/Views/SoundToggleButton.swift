import SwiftUI

/// 音（効果音と BGM）の ON/OFF を切り替えるボタン。選んだ状態はアプリを閉じても覚えておく
struct SoundToggleButton: View {
    @AppStorage(SoundPlayer.enabledKey) private var isEnabled = true

    var body: some View {
        Button(isEnabled ? "音をオフにする" : "音をオンにする",
               systemImage: isEnabled ? "speaker.wave.2" : "speaker.slash") {
            isEnabled.toggle()
            SoundPlayer.shared.updateMusic()
        }
    }
}
