import StarCore
import SwiftUI

/// 選択済みの天体を、日時と名前の右上に浮かべる。天体の選び直しは既存の画面を使う。
struct HomeConditionsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editingDate = false
    @State private var draftDate = Date()
    @State private var width: CGFloat = 358

    /// 題字「ASTERA」を出すか。ホームのシートの中では出さない
    var showsTitle = true

    private var selectedTarget: CabinTarget? { model.selectedCabinTarget }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsTitle {
                Text("ASTERA")
                    .font(.system(size: 42, weight: .regular, design: .serif)).tracking(3)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
            }
            Group {
                if typeSize.isAccessibilitySize || width < 280 {
                    VStack(alignment: .leading, spacing: 16) {
                        portrait.frame(maxWidth: .infinity, alignment: .trailing)
                        observationDetails
                    }
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        observationDetails.frame(maxWidth: .infinity, alignment: .leading)
                        portrait
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if let target = selectedTarget, let credit = target.imageCredit {
                    Text(credit).foregroundStyle(.secondary)
                }
                if let note = selectedTarget?.note {
                    Text(note).foregroundStyle(.secondary)
                }
                if let message = model.forecastOutOfRangeMessage {
                    ForecastOutOfRangeNote(message: message)
                }
                Text("スコアは観測条件の目安で、観測できる確率ではありません。")
                    .foregroundStyle(.secondary)
            }.font(.caption)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .sheet(isPresented: $editingDate) { dateEditor }
    }

    private var observationDetails: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("観測する日時").font(.subheadline).foregroundStyle(.secondary)
                Button {
                    draftDate = model.date
                    editingDate = true
                } label: {
                    HStack(spacing: 8) {
                        Text(model.date.formatted(Self.dateFormat))
                            .font(.system(.title3, design: .serif)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("観測する日時を変更")
                .accessibilityValue(model.date.formatted(Self.accessibleDateFormat) + "、日本時間")
                .accessibilityHint("日付と時刻の編集画面を開きます")
                Text(model.date.formatted(Self.yearFormat) + "・日本時間")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("観測する天体").font(.subheadline).foregroundStyle(.secondary)
                Text(selectedTarget?.name ?? model.target.name)
                    .font(.system(.title, design: .serif)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private var portrait: some View {
        let side = min(220, max(124, width * 0.48))
        return Group {
            if let target = selectedTarget {
                // 選択画面と同じ画像・模式図を再利用。背景・枠・クリップは付けない。
                CabinPortrait(target: target)
                    .shadow(color: .white.opacity(0.12), radius: 16)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var dateEditor: some View {
        NavigationStack {
            ScrollView {
                DatePicker("観測する日時", selection: $draftDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding()
                Text("日本時間で選択します。変更は「適用」を押すと反映されます。")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }
            .navigationTitle("観測する日時")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { editingDate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        model.date = draftDate
                        editingDate = false
                    }.bold()
                }
            }
            .background { NightSkyBackground() }
        }
        .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private static let dateFormat = Date.FormatStyle(locale: Locale(identifier: "ja_JP"), timeZone: tokyo)
        .month(.defaultDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    private static let yearFormat = Date.FormatStyle(locale: Locale(identifier: "ja_JP"), timeZone: tokyo).year()
    private static let accessibleDateFormat = Date.FormatStyle(locale: Locale(identifier: "ja_JP"), timeZone: tokyo)
        .year().month().day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
}

/// 選んだ日時が天気予報の範囲外のときの注意書き
struct ForecastOutOfRangeNote: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "calendar.badge.exclamationmark")
            .foregroundStyle(.orange)
    }
}

struct MoonSummary: View {
    @AppStorage(DirectionNotation.storageKey) private var directionNotation = DirectionNotation.default
    let moon: MoonInfo

    var body: some View {
        HStack {
            Image(systemName: "moon.fill")
                .foregroundStyle(HomeStyle.moonlight)
            Text("\(moon.phaseName)（輝面 \(Int(moon.illuminatedFraction * 100))%）")
            Spacer()
            Text(moon.position.altitude > 0
                 ? "\(directionNotation.text(moon.position.azimuth)) 高度\(Int(moon.position.altitude))°"
                 : "地平線の下")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

extension AppModel {
    /// 画面に出す天体。星座を選んだときは星座（判定は代表星で行う）
    var selectedCabinTarget: CabinTarget? {
        let targets = CabinTarget.catalog
        if let id = selectedCabinTargetID,
           let selected = targets.first(where: { $0.id == id && $0.observation == target }) {
            return selected
        }
        // 他画面で観測対象が変わった場合は、古い表示用IDを使わず現在の対象を表示する。
        return targets.first { !$0.isConstellation && $0.observation == target }
    }
}
