# 観測方向・施設の制限・12地点への拡充（1-08・1-09・1-10）

確認日: 2026-10-24。実機確認後にpush・PR作成する。統合先はdevelop。

## 1-08: 都庁南展望室の方角

詳細画面に「窓・屋根と見える方角」を追加し、公式案内にある北東・南東・南西・西の眺望紹介と、確認できていない範囲を分けて表示する。

- 出典: [東京都財務局の展望室利用案内](https://www.zaimu.metro.tokyo.lg.jp/tochousha/goannai/tenbou)
- 調査した図面: [南展望室の出店者公募要項](https://www.zaimu.metro.tokyo.lg.jp/documents/d/zaimu/2024minamikoubo)のPDF24ページ「別紙7 案内図・明細図」。現時点の窓ごとの可視角度の境界を確定する資料にはできなかった。
- **ユーザーと合意した範囲**: 方角案内と判定機能まで用意し、正確な角度は確認待ちにする。`viewingDirectionMask` は未設定、`directionMaskVerified` はfalseを維持する。task.mdの1-08は、当初の完了条件（角度確認済み）を満たすまで🔄。
- 既存の高度上限35°は暫定値のまま。画面にも暫定値と表示する。
- 判定機能は複数の窓、北をまたぐ範囲、全方位、窓の高度上限に対応。屋内で範囲の登録が無いときは、確認フラグだけをtrueにしても「確認済み」にならない。

今後、現地の窓の向きと境界角度を記録し、その出典とともに範囲をJSONへ入れて確認フラグをtrueにする。眺望紹介の「方面」を、そのまま精密な角度へ変換しない。

## 1-09: 天候と撮影機材

`weatherClosureConditions` と `photographyRestrictions` を省略できる項目として追加。旧データも読める。詳細画面で項目ごとに表示し、値が無い場合は「未確認」とする。

| 地点 | 天候による閉鎖条件 | 撮影機材の制限 | 出典 |
|---|---|---|---|
| SHIBUYA SKY | 強風、雨、雪、雷雲接近、光化学スモッグ・異常高温等で屋上閉鎖の可能性 | 三脚・一脚・自撮り棒等の持込不可。カメラ・双眼鏡のストラップ等の条件も表示 | [チケット・屋上の注意](https://www.shibuya-scramble-square.com/sky/ticket/) |
| 都庁南展望室 | 悪天候等で急な閉室の可能性 | 三脚等を使った撮影不可 | [利用案内](https://www.zaimu.metro.tokyo.lg.jp/tochousha/goannai/tenbou) |
| KITTEガーデン | 天候による閉鎖の可能性。数値基準は未確認 | 未確認 | [施設案内](https://marunouchi.jp-kitte.jp/guide/facilities.jsp) |

通常案内であり、当日の開閉状況や予報からの閉鎖判断ではない。来訪前に公式情報を確認する。
既存の公式情報更新処理にも新項目を追加した。窓の範囲・確認フラグは自動更新しない。取得失敗時は既存データと確認日を維持する。

## 1-10: 追加3公園

| 地点 | 区 | 確認した通常案内 | 公式情報 |
|---|---|---|---|
| 舎人公園 | 足立区 | 常時開園、無料（一部有料施設あり） | [東京都公園協会](https://www.tokyo-park.or.jp/park/toneri/) |
| 水元公園 | 葛飾区 | 同上 | [東京都公園協会](https://www.tokyo-park.or.jp/park/mizumoto/) |
| 駒沢オリンピック公園 | 世田谷区の代表点 | 同上 | [東京都公園協会](https://www.tokyo-park.or.jp/park/komazawa-olympic/) |

駐車場・スポーツ施設・立入禁止区域の利用時間とは区別する。駒沢のストリートスポーツ広場の[11/25〜26の点検・予備日11/27](https://www.tokyo-park.or.jp/park/komazawa-olympic/news/2026/52457.html)は一部区域の注意として表示し、公園全体を閉園扱いにしない。

代表座標は地理院地図で園内の位置を確認。標高は[国土地理院の標高取得プログラム](https://maps.gsi.go.jp/development/elevation_s.html)から取得した。出典・座標・元の応答は[保存記録](added-parks-evidence.json)にある。国土地理院の地図・標高データを加工して使用している。舗装面や観測位置の現地測量ではなく、目線高さ1.5mも想定値。

追加3地点の建物・樹木・窓や柵の方向・広域光害・近傍照明・天候閉鎖条件・撮影機材制限は未確認。推測値を登録せずnullまたは未設定にし、「要確認」を維持する。地平線は従来の簡易計算を使用し、暫定値と表示する。
未取得の光害は0（暗い）扱いにせず、名前を付けた中間値で仮計算し、未確認の注意を付ける。最新developで取り込まれた既存9地点のVIIRS出典・値は保持する。VIIRS変換スクリプトの確認表も新規地点のnullに対応した。

## 検証

- StarCore: 49テスト成功（窓の範囲による推薦結果、北またぎ・全方位・高度、旧JSONとの互換性、12地点の読み込みと未確認扱いを含む）。
- `python3 -m unittest discover -s scripts/tests -q`: 35件中29件成功、6件スキップ。rasterioがないため既存の疑似GeoTIFF変換テストをスキップ。新規地点nullの表示・更新のテストは成功。
- `python3 -m unittest discover -s scripts/night_access_tests -v`: 23件成功。
- `xcodebuild -scheme StarSpot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/astera-1-08-derived build`: 成功。
- 通常の`swift test --package-path Packages/StarCore`は、この環境のDocuments配下のビルド生成物に付くFinder情報により署名エラー。既存キャッシュのclean後も再発したため、`--scratch-path /tmp/astera-1-08-starcore`で全テストを実行して成功した。リポジトリのソースや署名設定は変更していない。
- iPhone 17 Proシミュレータで、追加3公園の一覧、舎人公園の詳細・光害の未確認表示、SHIBUYA SKYの閉鎖・撮影条件、都庁の方角未確認・高度暫定・4方面の案内、詳細から一覧への戻る操作を確認した。

画面の記録: [追加3公園の一覧](screenshots/observation-conditions/iphone17pro-new-parks.png)、[SHIBUYA SKYの閉鎖・撮影条件](screenshots/observation-conditions/iphone17pro-sky-conditions.png)。

## 実機で確認する箇所（ユーザー担当）

1. 一覧で舎人公園・水元公園・駒沢オリンピック公園を開けること。
2. SHIBUYA SKY・都庁・KITTEの詳細に「天候による閉鎖条件」「撮影機材の制限」があり、KITTEの撮影機材制限が「未確認」であること。
3. 都庁の「窓・屋根と見える方角」に4方面の案内があり、正確な方角が「未確認」、高度上限35°が「暫定値」であること。
4. 追加3公園の光害が「未確認」と表示され、月が地平線より高く通常利用時間内でも「要確認」になること。
5. 詳細の3D表示・戻る操作・長い説明文のスクロールが動くこと。

実機テストと窓の境界角度の現地確認は別の確認。実機テスト完了だけで窓の確認フラグをtrueにはしない。
