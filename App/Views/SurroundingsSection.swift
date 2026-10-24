import StarCore
import SwiftUI

/// 周辺の建物用途（商業地・住宅地など）の参考表示
struct SurroundingsSection: View {
    let context: SpotContext

    var body: some View {
        let summary = Surroundings.summarize(context)

        Section {
            Text(summary.headline)
            if summary.isInsufficient {
                Text(summary.buildingCount.map { "半径 \(Int(Surroundings.radius)) m 内の建物が \($0) 棟で、傾向を出すには少なすぎます。" }
                     ?? "この地点には建物データがありません。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.shares, id: \.group) { share in
                    LabeledContent(share.group.label, value: "\(share.percent)%（\(share.count)棟）")
                }
            }
        } header: {
            Text("周辺の建物用途")
        } footer: {
            Text("PLATEAU の建物用途から半径 \(Int(Surroundings.radius)) m を集計した参考情報です。スコアには影響しません。")
        }
    }
}
