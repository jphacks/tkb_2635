# Astera 効果音

効果音の仕様書（幻想的・神秘的な宇宙空間 × 透明感のある UI）に沿って、7種類を合成で作った。録音素材は使っていない。音の高さは全体 BGM（Gマイナーと推定）に合わせ、G・B♭・C・D・F の5音だけを使う。最初の版が電子音っぽかったので、立ち上がりをゆるやかにし、音を少しずらして重ね、残響を長くして「ふわっと」した音に直した（task.md の p-1。p で作った WAV の版から置き換えた）。

素材は `App/Resources/Sounds/`（CAF・44.1 kHz・ステレオ・16 bit）。7種類とも音圧（RMS）をそろえて書き出し、場面ごとの音量はアプリ側で掛ける（`Packages/StarCore/Sources/StarCore/Sound/SoundEffect.swift`）。

| ファイル | 使用場面 | 長さ | 音量 | 続けて鳴らせる間隔 |
|---|---|---:|---:|---:|
| `se_launch.caf` | アプリ起動 | 1.50秒 | 45% | 1秒 |
| `se_map_open.caf` | 詳細画面で 3D を開く | 1.20秒 | 40% | 1秒 |
| `se_pin_tap.caf` | 地図のピンを押す | 0.30秒 | 35% | 0.15秒 |
| `se_body_select.caf` | 星・月を選ぶ | 0.60秒 | 40% | 0.15秒 |
| `se_time_tick.caf` | 時刻スライダーが 15 分動く | 0.12秒 | 15% | 0.08秒 |
| `se_spot_found.caf` | 推薦の条件を満たす地点がある・推薦に変わった | 1.40秒 | 50% | 3秒 |
| `se_map_gesture.caf` | 3D の回転・拡大を始める | 0.25秒 | 15% | 0.6秒 |

- 地点一覧の左上のスピーカーのボタンで ON/OFF できる（アプリを閉じても覚えている）
- 再生は `AVAudioSession` の ambient で行う。消音スイッチ（マナーモード）がオンのときは鳴らず、ほかのアプリの音楽も止めない
- 地点発見の音は、推薦（`RecommendationTier.recommended`）の条件を実際に満たしたときだけ鳴らす

## 再生成と試聴

```sh
python3 -m venv ../outputs/se/venv && ../outputs/se/venv/bin/pip install numpy
../outputs/se/venv/bin/python scripts/generate_se.py
```

7種類を順番に並べたプレビューは `docs/design/sound-effects/preview.wav`（時刻スライダーは3回続けて鳴らしている）。
