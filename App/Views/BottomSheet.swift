import SwiftUI

/// 画面の下から引き上げる3段階のシート。取っ手と見出しをドラッグするか、取っ手をタップして高さを変える。
/// iOS 標準の .sheet だと中の NavigationLink で画面を進められないため、画面の上に重ねる形で作る。
struct BottomSheet<Header: View, Content: View>: View {
    enum Detent: CaseIterable {
        /// 見出しだけ
        case collapsed
        /// 画面の半分ほど
        case medium
        /// ほぼ全画面
        case large
    }

    @Binding var detent: Detent
    /// いちばん下のときの高さ（取っ手＋見出し）。見出しの中身に合わせて使う側が決める
    var collapsedHeight: CGFloat = 140
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    @GestureState private var dragOffset: CGFloat = 0

    /// 半分のときの、使える高さに対する割合
    private static var mediumFraction: CGFloat { 0.48 }
    /// いちばん上のとき、上に残す 3D の高さ
    private static var largeTopMargin: CGFloat { 72 }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let resting = height(of: detent, in: total)
            let shown = min(max(resting - dragOffset, collapsedHeight), height(of: .large, in: total))

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    // タップで開閉するのは取っ手だけ。見出し全体にすると、中のボタンを押したのを横取りする
                    Capsule()
                        .fill(.secondary)
                        .frame(width: 40, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(.rect)
                        .onTapGesture { detent = detent == .collapsed ? .medium : .collapsed }
                        .accessibilityLabel("情報のシート")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(detent == .collapsed ? "タップで情報を広げます" : "タップで情報をたたみます")
                    header
                }
                .padding(.top, 2)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in state = value.translation.height }
                        .onEnded { value in
                            detent = nearest(to: resting - value.predictedEndTranslation.height, in: total)
                        }
                )

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: shown, alignment: .top)
            .clipped()
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                    .fill(.regularMaterial)
                    .ignoresSafeArea(edges: .bottom)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: -2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.spring(duration: 0.3), value: detent)
        }
    }

    private func height(of detent: Detent, in total: CGFloat) -> CGFloat {
        switch detent {
        case .collapsed: collapsedHeight
        case .medium: max(collapsedHeight, total * Self.mediumFraction)
        case .large: max(collapsedHeight, total - Self.largeTopMargin)
        }
    }

    /// 指を離した位置（勢いを含む）に一番近い段階
    private func nearest(to target: CGFloat, in total: CGFloat) -> Detent {
        Detent.allCases.min { abs(height(of: $0, in: total) - target) < abs(height(of: $1, in: total) - target) } ?? .collapsed
    }
}
