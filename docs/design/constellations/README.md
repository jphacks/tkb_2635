# 星座線データ

アプリ内の `App/Resources/Sky/constellations.json` は、[d3-celestial](https://github.com/ofrohn/d3-celestial) の星座線と日本語名を、実行時通信を使わないよう必要な項目だけに整形したデータです。線の座標は J2000 の星位置をもとにした GeoJSON 形式です。アプリは経度を赤経、緯度を赤緯として赤道座標に戻し、星図と同じ天球の向きに重ねます。

d3-celestial は星座線データの出典として IAU の星座図を挙げています。データとソフトウェアは BSD 3-Clause License で配布されているため、利用条件を `App/Resources/Sky/constellations-LICENSE.txt` に同梱し、画面の出典表示にも記載しています。イラスト素材は含めず、星座線のみをガラス調の半透明線で描画しています。

これは無料の REST API ではなく、公開されている静的データです。アプリへの同梱により、通信環境や API キーに依存せず表示できます。
