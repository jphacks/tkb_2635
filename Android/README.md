# Astera Android（14-01〜14-06）

Android 8.0以降（API 26）、OpenGL ES 3.0 / WebGL 2対応。Kotlinのアプリ内で、同梱したTypeScript画面とThree.jsの3Dを実行する。iOSコードは変更しない。

## 実装範囲

- 66対象（月・5惑星・8星座・52恒星）のスライド選択、丸窓、確認・戻る、選択結果の保存。
- 既存43地点・32都市のデータを共有。日時変更（日本時間）、地図、現在地からの距離、推薦／要確認、絞り込み・並べ替え、施設情報・経路・2地点比較。
- 月・太陽・惑星・恒星の位置、建物の部分形状・国土地理院の地形を合成した地平線、観測方向・天井、営業時間と例外、天気、薄明・光害・月明かりを使う判定。未取得・未確認を晴れや利用可能とは扱わない。曇天・降水時も推薦しない。
- 地点別PLATEAU LOD2都市、東京23区LOD1、中心付近2区のLOD2切り替え。回転・拡大、観測者の高さ、端末の向き、窓の時刻別点灯、観測者がいる建物の半透明表示。
- 昇没時刻、最高高度時刻、前後6時間の時刻スライダー、今から6時間の幾何学的な観測可能時間。
- 星座線と88星座絵。iOSと同じ画像の基準星を使う薄板スプラインで天球へ配置。
- 背面カメラAR：現在地・現在時刻・北基準の端末姿勢を使用。磁気偏角を補正。停止・背景移行・画面閉じでカメラとセンサーを解放する。
- ダーク／ライト／端末設定、12／24時間、方位名／角度、動きの軽減、効果音の保存。下部ナビゲーションは追加しない。

## ビルド

必要：Node.js 22以降、Python 3.12、JDK 17、Android SDK Platform 35・Build Tools 35.0.0。Android SDKは公式のライセンスを確認して導入する。

```powershell
# リポジトリのルートで実行。USDZをGit LFSポインタのままにしないこと。
python -m venv Android/.venv
Android/.venv/Scripts/python -m pip install -r scripts/android/requirements.txt
cd Android/web
npm ci
npm run prepare:data
cd ../..
Android/.venv/Scripts/python scripts/android/convert_models.py
Android/.venv/Scripts/python scripts/android/verify_assets.py
cd Android/web
npm test
npm run build
cd ..
# JAVA_HOME / ANDROID_HOMEを各自のインストール先へ設定する
./gradlew.bat :app:assembleDebug :app:lintDebug
```

APK：`Android/app/build/outputs/apk/debug/app-debug.apk`。試用用のデバッグ署名。Play Storeへの公開・配布用署名は別作業。
Linux/macOSでは `Scripts/python` を `bin/python`、`gradlew.bat` を `bash gradlew` に読み替える。

`prepare:data`はJSONと画像をコピーする。続く変換でUSDZをGLBへ変換し、画像をAndroid向けに縮小する。順序を入れ替えない。変換済みGLBは元USDZのSHA-256が同じなら再利用する。生成物・SDK・秘密鍵はコミットしない。Three.jsとLeafletのライセンス全文を生成物へ同梱する。78個の3Dモデルは約1.08GB、圧縮APKは約700MBになるため、インストールには十分な空き容量が必要。

画面だけの確認は `Android/web` で `npm run dev`。カメラARと端末方位はAndroidアプリで確認する。ブラウザー版をAPKとして扱わない。

## 権限・通信

カメラはAR開始時、位置情報は現在地取得またはAR開始時に求める。マイク・バックグラウンド位置情報・通知は利用しない。位置情報を保存・送信しない。天気APIへ送るのは既存観測地点の座標。地図タイルの要求先には表示中の地図の範囲が伝わる。

WebViewは `https://appassets.androidplatform.net` の同梱コンテンツだけをアプリ画面として読み、施設リンクは外部ブラウザーへ開く。ファイルアクセス・平文HTTP・混在コンテンツを禁止する。JavaScriptブリッジは端末方位・磁気偏角・消音状態だけを公開する。

## iOSとの差と検証待ち

- MapKit / RealityKitはAndroidにないためLeaflet / Three.jsを使用。形状・写真・基準座標は既存USDZを変換して利用する。広域LOD2は手動で中心付近2区へ切り替える方式。iOSでも自動LODは既定で無効。建物名ラベル、カメラ飛行、航空障害灯の点滅は未移植。広域の航空写真・VIIRS地面は共通素材を表示する。
- ARは方向を重ねる方式。ARCoreの平面検出や画像認識ではない。カメラ画角は概算で、実際のビルによるAR画像の遮蔽を自動認識しない。センサー・GPS・カメラの実機精度は未確認。
- 日時を選ぶ予測と、現在地・現在時刻のARを区別して表示する。星座の推薦判定は代表星であり、全体の可視性を保証しない。
- 昇没は5分刻み走査＋1秒の交差探索、最高高度は5分刻み。観測可能時間は幾何・窓・薄明だけで、天気や入場条件の保証ではない。
- BGMは既存M4A、効果音は既存CAFのPCMをWAVへ無損失変換して使用。端末の消音・効果音設定・背景移行に連動する。
- 自動テスト・Web画面・APKビルド・LintはPCで確認。ADBに接続された端末はなく、Android端末／エミュレーターの起動と、権限拒否・復帰・AR・低メモリ端末での実測は未確認。14-06は実機検証待ちのまま。
- Windows環境のため、既存iOSの `swift test` / Xcodeビルドは実行していない。

## 出典

元のデータ・画像の出典と利用条件はリポジトリのREADMEおよび既存の各素材ドキュメントを引き継ぐ。PLATEAU（CC BY 4.0）、国土地理院、EOG/Colorado School of Mines（VIIRS、CC BY 4.0）、Open-Meteo（CC BY 4.0）、OpenStreetMap contributors（ODbL）、NASA、d3-celestial（BSD-3-Clause）。追加ライブラリはThree.js（MIT）、Leaflet（BSD-2-Clause）、AndroidX（Apache-2.0）。


## PCでの確認結果（2026-10-25）

26件の自動テスト成功（JPL DE421・Astronomy Engine参照値、5方位のSwift遮蔽回帰値、地形・部分形状・曇天判定・営業時間・通信失敗・88星座の基準星）。78個のGLBはサイズとSHA-256を検証。Gradleラッパーの公式チェックサム照合・起動を確認。APK生成成功、Android Lintは0 errors / 12 warnings（SDK・依存ライブラリの更新案内、JavaScript有効化など）。Web画面の390px幅で丸窓・土星の環・日時変更・一覧を確認。公式天気APIはPCからHTTP 200／384時間分を確認。画面検証で標準fetchの呼び出し不具合を修正し、回帰テストを追加。Android実機での通信は検証待ち。
