import SwiftUI

/// 効果音の ON/OFF を切り替えるボタン。選んだ状態はアプリを閉じても覚えておく
struct SoundToggleButton: View {
    @AppStorage(SoundPlayer.enabledKey) private var isEnabled = true

    var body: some View {
        Button(isEnabled ? "効果音をオフにする" : "効果音をオンにする",
               systemImage: isEnabled ? "speaker.wave.2" : "speaker.slash") {
            isEnabled.toggle()
        }
    }
}
