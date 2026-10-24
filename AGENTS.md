# AGENTS.md

このリポジトリで作業する人（チームメンバーと AI エージェント）向けの決まりごと。
アプリの概要・起動方法は [README.md](README.md) を見る。

## ブランチ

| ブランチ | 役割 | 直接 push |
|---|---|---|
| `main` | 提出・デモに使う安定版 | しない |
| `develop` | 開発の統合先。PR はここへ出す | しない |
| `feature/*` `fix/*` `docs/*` | 1つの作業ごとの作業ブランチ | してよい |

### 作業の流れ

1. 最新の `develop` から作業ブランチを切る
   ```bash
   git switch develop
   git pull
   git switch -c feature/時刻スライダー
   ```
2. 小さめの単位でコミットし、作業ブランチを push する
3. **`develop` 宛て**に PR を出す（GitHub の既定の宛先が `main` のままのことがあるので、宛先を確かめる）
   ```bash
   gh pr create --base develop
   ```
4. ほかのメンバー 1 人以上に見てもらってからマージする。マージ後は作業ブランチを消す
5. `develop` が動く状態になったら、まとめて `develop` → `main` の PR を出す（提出前・デモ前など）

### ブランチ名

- `feature/〇〇`: 機能の追加（例: `feature/compare-view`）
- `fix/〇〇`: 不具合の修正
- `docs/〇〇`: README・ドキュメントだけの変更
- `data/〇〇`: 地点・建物データの追加や修正

## PR の決まり

- 1つの PR には 1つの目的だけを入れる。大きくなりそうなら分ける
- PR の説明には「何を変えたか」「どう確かめたか」「確かめていないこと」を書く（テンプレートあり）
- 画面を変えたら、シミュレータのスクリーンショットを貼る
- マージ前に次が通ることを確かめる
  ```bash
  cd Packages/StarCore && swift test
  xcodebuild -scheme StarSpot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```
- 衝突したら、作業ブランチに `develop` を取り込んで直す（`git merge develop`）

## コミットメッセージ

日本語で、何をしたかを1行で書く。例: `月相の表示を一覧に追加`、`都庁展望室の営業時間を修正`

## コードの決まり

- 画面は SwiftUI だけで書く（UIKit・Storyboard は使わない）
- 計算・データ・通信は `Packages/StarCore` に置き、テストを書く。`App/` は画面だけにする
- テストは Swift Testing（`@Test`、`#expect`）で書く
- ファイルを足したり消したりしたら、`project.yml` を直して `xcodegen generate` を実行し、生成された `StarSpot.xcodeproj` もコミットする。`project.pbxproj` を手で編集しない（衝突したら `xcodegen generate` で作り直す）

## データの決まり

- 調べていない値を 0 や「問題なし」として入れない。分からなければ `null` にして、画面で「未確認」と出す
- 施設の営業時間・料金を確かめたら、`spots.json` の `lastVerifiedAt` に確認した日付を入れ、出典の URL を `officialWebsite` に入れる
- 建物データ（`buildings.json`）は今は手作りの概略。PLATEAU から作ったデータに置き換えるときは、出典と変換方法を PR に書く

## 触らないもの

- API キーやトークンをコミットしない
- `main` と `develop` への force push はしない
