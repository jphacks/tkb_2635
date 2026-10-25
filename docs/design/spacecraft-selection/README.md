# 8-11 宇宙船の窓から天体を選択
起動時にRealityKitの星空と窓枠を表示し、横スライドで天体を選ぶ。中央対象を押すと半透明の確認画面を重ね、確定で既存の観測場所一覧へ進む。戻るでは選択位置を保持し、観測対象を変更しない。
## 実装と制約
- 確定したときだけAppModel.targetを更新する。
- SpotListView.swiftとTargetPicker.swiftの既存ファイル内に実装。新たなプロジェクト参照は不要。
- 月・惑星は暫定の3D球。実写テクスチャや土星の環は未対応。
- 星座は選択用模式図。オリオン座はベテルギウス、カシオペヤ座はシェダルで観測判定することを確認画面に明示する。星座全体の可視性は未判定。
- 観測場所は既存の東京都内の地点。地球全域の検索ではない。
## 検証待ち
Windows環境にSwift・Xcode・iOSシミュレータがないため、ビルド・テスト・描画・操作確認・スクリーンショットは未実施。ドラフトPRで検証を待つ。
- swift test --package-path Packages/StarCore
- xcodebuild -scheme StarSpot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
- スワイプと矢印による中央対象の切り替え
- 確認画面の背景透過、戻るで位置保持、確定で推薦結果の変更
- 小画面・大きな文字・VoiceOverへの対応状況
- 複数RealityViewの描画負荷・メモリを実機で確認
