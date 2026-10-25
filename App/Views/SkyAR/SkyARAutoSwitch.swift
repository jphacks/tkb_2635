import StarCore
import SwiftUI

extension View {
    /// 詳細画面でスマホを空へ向けたら、AR に自動で切り替える。戻るのは AR 画面の「戻る」ボタン。
    /// 下のシートは出したままでは全画面の AR を出せないので、いったん閉じ、AR を閉じたら出し直す。
    func skyARAutoSwitch(context: SpotContext, isSheetShown: Binding<Bool>) -> some View {
        modifier(SkyARAutoSwitch(context: context, isSheetShown: isSheetShown))
    }
}

private struct SkyARAutoSwitch: ViewModifier {
    let context: SpotContext
    @Binding var isSheetShown: Bool

    @State private var monitor = DeviceMotionMonitor()
    @State private var isARShown = false
    @State private var isOpening = false
    /// シートが閉じ終わるまでの待ち時間（閉じている最中は、別の画面を出せない）
    private static let sheetCloseDelay = Duration.milliseconds(600)

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isARShown, onDismiss: { isSheetShown = true }) {
                SkyARView(context: context, monitor: monitor) { isARShown = false }
            }
            .onAppear {
                monitor.onLookUp = { open() }
                monitor.start()
            }
            .onDisappear {
                monitor.stop()
            }
    }

    private func open() {
        guard !isARShown, !isOpening else { return }
        isOpening = true
        isSheetShown = false
        Task {
            try? await Task.sleep(for: Self.sheetCloseDelay)
            isARShown = true
            isOpening = false
        }
    }
}
