# 紹介動画（発表の冒頭）

夜の23区の 3D を回りながら東大本郷へ寄り、カメラが空を見上げて満天の星空になり、「Astera」が左から手書きで書かれる 20 秒の動画（1920×1080・30fps・音なし）。

| 秒 | 中身 | 作るところ |
|---|---|---|
| 0〜9 | 23区の建物（PLATEAU LOD2）を上空から回りながら、東大本郷（水色の光の輪）へ寄る | Blender |
| 9〜13 | カメラが上を向き、星空と天の川へ | Blender |
| 13〜20 | 「Astera」を1文字ずつ手書きで書き、「街の中で、星が見える場所へ。」を出す | Remotion |

## 作り直す手順

前提: Blender 4.0（`/Applications/Blender.app`）、Node、区ごとの広域 3D（`python3 scripts/build_wide_ward.py <区コード> --lod 2` で作る `../outputs/wide2-*/wide.usdz`）。

```bash
# 1. 3D を連番の PNG で描く（M5 で 3 つ並べて約 30 分）。見上げたあと（401〜600）は建物を外して速く描く
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b --python video/blender/astera_intro.py -- video/render/frames 1 200
$B -b --python video/blender/astera_intro.py -- video/render/frames 201 400
$B -b --python video/blender/astera_intro.py -- video/render/frames 401 600 --sky

# 2. タイトルの文字の形を作る（文字を変えるときだけ。pip install fonttools が要る）
python3 video/scripts/title_paths.py Astera video/remotion/src/title-paths.json

# 3. タイトルを重ねて mp4 にする
cd video/remotion && npm install && ln -sfn ../../render/frames public/frames
npx remotion render AsteraIntro out/astera-intro.mp4
```

試しに数コマだけ見るときは、`astera_intro.py -- 出力先 1 200 600 --stills --preview` で静止画を描く。

## 出典

- 建物: 国土交通省 Project PLATEAU（CC BY 4.0）
- 天の川: NASA SVS「Deep Star Maps 2020」（`App/Resources/Sky/stars_dark.png`）
- 書体: Snell Roundhand（macOS 付属）、ヒラギノ明朝
