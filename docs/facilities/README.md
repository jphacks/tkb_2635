# 公式施設情報（1-03・1-04・1-05）

3施設の通常営業時間・料金・利用条件を、公式案内から取得する。
取得処理は `scripts/update_official_facilities.py`、出典と変更時の確認日は `official-checks.json`。

| 施設 | 公式の確認先 | 反映する内容 |
|---|---|---|
| SHIBUYA SKY | [公式サイト](https://www.shibuya-scramble-square.com/sky/)・[チケット](https://www.shibuya-scramble-square.com/sky/ticket/) | 通常営業時間、最終入場、WEB大人料金・小人料金、日時指定券の事前購入推奨、屋上の天候制限・持込制限 |
| 都庁南展望室 | [東京都財務局の利用案内](https://www.zaimu.metro.tokyo.lg.jp/tochousha/goannai/tenbou) | 開室時間・最終入室、無料、予約受付なし、定期休室、撮影制限、一部照明の消灯案内 |
| KITTEガーデン | [施設別の案内](https://marunouchi.jp-kitte.jp/guide/facilities.jsp) | 平日と土日祝の開放時間、無料、天候による閉鎖、東京駅方面の眺望紹介 |

旧都庁案内サイトは移転案内なので、新サイトを確認先に使う。
KITTEの店舗・郵便局長室の営業時間と屋上庭園の時間を混同しない。
SHIBUYA SKYはHTML内に本文がないため、ページが指定する同一公式サイトのJavaScriptから、営業時間とチケットのJSONデータだけを読み取る。JavaScriptコードは実行しない。

## 日次確認とPR

`.github/workflows/official-facilities.yml` が毎日 **06:17（日本時間）** に確認する。GitHubの混雑で遅れる場合がある。
変更があれば作業ブランチを作り、`develop` 宛てにPRを出す。人が出典と差分を確認してマージする。

- 変更なしならPRは作らない。毎回の実行日・取得結果はActionsの実行サマリーに残す。
- 同じ種類の未マージPRがあるときは重複PRを作らない。最新の結果は実行サマリーを確認し、既存PRをマージ・クローズした後に再実行する。
- 取得失敗やページ構成の変更、当年の祝日不足は失敗として記録する。該当施設は情報・確認日の両方を維持する。他の施設の正常な変更はPRにできる。
- `lastVerifiedAt` は「現在の内容を公式案内で確認した日」。毎日の取得日だけでは更新しない。
- アプリは同梱データを使うため、PRのマージ後にビルドしたアプリへ反映される。配布済みアプリのデータを直接更新する仕組みではない。

開始に必要な設定:

1. このワークフローを**GitHubの既定ブランチ**にも含める（既定が`main`の間は、チームの `develop` → `main` PRで反映する）。GitHubの定期実行は既定ブランチ上のワークフローだけが対象。
2. リポジトリの **Settings → Actions → General → Workflow permissions** で、GitHub ActionsからPRを作成する許可を有効にする。組織側で禁止されている場合は管理者の設定が必要。
3. Actionsの「公式施設情報の確認」→「Run workflow」で初回実行を確認する。APIキーは不要。`main`・`develop` に直接pushしない。

## 休日・最終入場の扱い

[内閣府の国民の祝日CSV](https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv)を使う。祝日の振替休日もCSVの値を採用する。
KITTEは土日祝の閉園時刻を適用。都庁南は第1・第3火曜、祝日なら翌平日、12/29〜31・1/2〜3の休室を日付ごとの例外に展開する。
都庁元日は通常と異なる特別開室の確認が必要なので、未確認の日付として推薦対象にしない。
祝日表がある当年以降の年だけを対象にし、有効範囲の外は開いていると判断しない。
`isOpen` は「その時刻に新たに入場できるか」を判定し、最終入場時刻を過ぎた地点は推薦しない。入場済みの人の滞在可否とは異なる。

## 観測方向と制限項目の追加

1-08・1-09・1-10の[実装範囲・出典・実機確認箇所](observation-conditions.md)を参照。閉鎖条件・撮影機材制限は別の項目として保存し、更新処理でも追従する。都庁の窓の境界角度は確認待ち。
追加タスク f で足した7公園は[出典と確認の記録](more-parks.md)を参照。

## 確認できない項目

窓や柵の正確な可視範囲、見上げられる高さ、近傍照明の0〜3評価は、眺望写真や消灯案内から推測しない。
既存の未確認値と注意表示を保つ。KITTEの予約要否は公式施設案内に明記がないため `null`。
当日の屋上開閉、臨時休館・庁舎点検日・東京マラソン日の特別営業時間、空席はこの処理では自動判定できない。画面の注意と公式リンクで確認する。
屋上開閉の現在値は変動が多く、日次の通常営業時間とは別なので保存しない。

## 手元での実行

```bash
python3 scripts/update_official_facilities.py                 # 確認のみ
python3 scripts/update_official_facilities.py --write         # 正常な施設の変更を反映
python3 -m unittest discover -s scripts/tests -v              # 通信しない取得処理テスト
swift test --package-path Packages/StarCore
```

Python 3.10以降。追加ライブラリなし。テスト用の保存済みデータは `scripts/tests/fixtures/` に、2026-10-24の公式ページの該当箇所・祝日表から抜粋してある。
