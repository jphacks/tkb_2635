"""アプリの効果音（SE）7種を合成して App/Resources/Sounds/ に CAF で書き出す。

録音素材は使わず、グラスベル（ガラスの鐘のような倍音）・柔らかいパッド・ノイズの風音を数式で作る。
音の高さは BGM（全体bgm.mp3、Gマイナーと推定）に合わせ、G・B♭・C・D・F の5音だけを使う。
全部の音は同じ音圧（RMS）にそろえて書き出す。場面ごとの音量（45%・15% など）はアプリ側で掛ける。

    python3 -m venv ../outputs/se/venv && ../outputs/se/venv/bin/pip install numpy
    ../outputs/se/venv/bin/python scripts/generate_se.py

CAF への変換に macOS の afconvert を使う。
"""
import pathlib
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
OUT_DIR = pathlib.Path(__file__).resolve().parent.parent / 'App/Resources/Sounds'
TARGET_RMS_DB = -20.0  # 鳴っている部分の音圧をそろえる目標 [dBFS]
PEAK_LIMIT_DB = -1.0  # 音割れしないための上限 [dBFS]

# BGM の調（Gマイナー）から外れない音。G4 = 392Hz を基準にする
NOTE = {
    'G2': 98.0, 'D3': 146.8, 'G3': 196.0, 'Bb3': 233.1, 'D4': 293.7,
    'G4': 392.0, 'Bb4': 466.2, 'C5': 523.3, 'D5': 587.3, 'F5': 698.5,
    'G5': 784.0, 'Bb5': 932.3, 'D6': 1174.7, 'F6': 1396.9, 'G6': 1568.0,
    'Bb6': 1864.7, 'D7': 2349.3, 'G7': 3136.0,
}


def t_axis(duration):
    return np.arange(int(SR * duration)) / SR


def place(buf, sound, start):
    """buf の start 秒の位置に sound を足す（はみ出した分は切る）。"""
    i = int(start * SR)
    n = min(len(sound), len(buf) - i)
    buf[i:i + n] += sound[:n]


def glass_bell(freq, duration, decay=1.0, brightness=1.0, attack=0.012):
    """ガラスの鐘。倍音を整数倍から少しずらすと、金属でなくガラスのような澄んだ音になる。

    同じ音を少しだけ高さをずらして3つ重ね、ゆっくりうねらせて電子音らしさを消す。
    attack を長めにすると、叩く音より「ふわっ」と浮かぶ音になる。
    """
    t = t_axis(duration)
    partials = [(1.0, 1.0, 1.0), (2.0, 0.22, 1.6), (2.76, 0.12 * brightness, 2.6), (5.4, 0.04 * brightness, 4.5)]
    out = np.zeros_like(t)
    for ratio, amp, speed in partials:
        for detune, phase in ((-0.0025, 0.0), (0.0, 1.3), (0.0025, 2.1)):
            f = freq * ratio * (1 + detune)
            if f > 8000:
                continue
            out += amp * np.sin(2 * np.pi * f * t + phase) * np.exp(-t * speed * 3.0 / decay)
    env = np.minimum(t / attack, 1.0) ** 2
    return out / 3 * env


def soft_pad(freqs, duration, attack, release):
    """少しずつ音程をずらしたサイン波を重ねた、柔らかい持続音。"""
    t = t_axis(duration)
    out = np.zeros_like(t)
    for f in freqs:
        for detune in (-0.004, 0.0, 0.004):
            out += np.sin(2 * np.pi * f * (1 + detune) * t + 7 * detune)
    out /= 3 * len(freqs)
    env = np.sin(0.5 * np.pi * np.minimum(t / attack, 1.0)) ** 2 * np.clip((duration - t) / release, 0.0, 1.0)
    return out * env


def breath(duration, center, seed=0):
    """息のような、ごく小さな風の音。ベルやパッドの下に敷いて空気感を足す。"""
    noise = swept_noise(center * 0.8, center * 1.2, duration, q=0.8, seed=seed)
    return lowpass(noise / max(np.abs(noise).max(), 1e-9), 4000)


def glide(f_start, f_end, duration):
    """f_start から f_end へ滑らかに上がるサイン波（指数で動かすと耳に自然に聞こえる）。"""
    t = t_axis(duration)
    freq = f_start * (f_end / f_start) ** (t / duration)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR)


def swept_noise(f_start, f_end, duration, q=2.0, seed=0):
    """中心の高さが動く帯域ノイズ（風・空気の音）。2次のバンドパスを1サンプルずつ回す。"""
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(int(SR * duration))
    t = t_axis(duration)
    center = f_start * (f_end / f_start) ** (t / duration)
    out = np.zeros_like(noise)
    y1 = y2 = x1 = x2 = 0.0
    for i, x in enumerate(noise):
        w = 2 * np.pi * center[i] / SR
        alpha = np.sin(w) / (2 * q)
        a0 = 1 + alpha
        y = (alpha * x - alpha * x2 + 2 * np.cos(w) * y1 - (1 - alpha) * y2) / a0
        x2, x1, y2, y1 = x1, x, y1, y
        out[i] = y
    return out


def lowpass(x, cutoff):
    """1次のローパス。高音のキンキンした成分を丸める。"""
    a = np.exp(-2 * np.pi * cutoff / SR)
    out = np.zeros_like(x)
    y = 0.0
    for i, v in enumerate(x):
        y = (1 - a) * v + a * y
        out[i] = y
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def reverb(mono, size, mix):
    """左右で少し違う残響を付けてステレオにする（Schroeder 型のくし形・オールパスフィルタ）。

    size は残響の長さの目安 [0, 1]。mix は残響の混ぜる量。
    """
    channels = []
    predelay = int(0.018 * SR)  # 響きを少し遅らせ、元の音の奥に空間が広がって聞こえるようにする
    source = np.concatenate([np.zeros(predelay), mono[:-predelay]])
    for spread in (0, 23):
        wet = np.zeros_like(mono)
        feedback = 0.74 + 0.2 * size
        for delay_ms in (29.7, 37.1, 41.1, 43.7):
            d = int((delay_ms + spread * 0.1) * SR / 1000)
            comb = np.copy(source)
            for i in range(d, len(comb)):
                comb[i] += feedback * comb[i - d]
            wet += comb
        for delay_ms in (12.0, 5.0, 1.7):
            d = int((delay_ms + spread * 0.02) * SR / 1000)
            ap = np.zeros_like(wet)
            for i in range(len(wet)):
                delayed = ap[i - d] if i >= d else 0.0
                src = wet[i - d] if i >= d else 0.0
                ap[i] = -0.7 * wet[i] + src + 0.7 * delayed
            wet = ap
        wet = lowpass(wet, 4500)  # 残響は高音を早く消し、宇宙の奥行きのように聞かせる
        wet /= max(np.abs(wet).max(), 1e-9)
        dry_peak = max(np.abs(mono).max(), 1e-9)
        channels.append(mono / dry_peak * (1 - mix) + wet * mix)
    return np.stack(channels, axis=1)


def fade_tail(stereo, fade):
    """最後の fade 秒で音を消しきる（ファイルの終わりで音が切れないように）。"""
    n = int(fade * SR)
    stereo[-n:] *= np.linspace(1, 0, n)[:, None] ** 2
    return stereo


# ---- 7種の効果音 ----

def launch():
    """1. アプリ起動（1.5秒）: 低く柔らかい宇宙のアンビエント → グラスベルが「キララン」と広がる。"""
    d = 1.5
    buf = np.zeros(int(SR * d))
    place(buf, highpass(soft_pad([NOTE['G2'], NOTE['D3'], NOTE['G3']], d, 0.45, 0.9), 110) * 0.32, 0)
    place(buf, soft_pad([NOTE['D4'], NOTE['Bb4'], NOTE['D5']], 1.25, 0.55, 0.7) * 0.22, 0.15)
    place(buf, breath(d, 900, seed=1) * np.sin(np.pi * t_axis(d) / d) * 0.05, 0)
    for k, note in enumerate(['G5', 'D6', 'Bb6', 'D7']):
        place(buf, glass_bell(NOTE[note], 1.2, decay=1.8, brightness=0.5, attack=0.03) * (0.42 - 0.07 * k), 0.38 + 0.1 * k)
    return fade_tail(reverb(lowpass(buf, 6500), size=1.0, mix=0.55), 0.45)


def map_open():
    """2. 3Dマップを開く（1.2秒）: 空間が広がりながら低音から高音へ上がる「フォワァン」。"""
    d = 1.2
    t = t_axis(d)
    buf = np.zeros(int(SR * d))
    swell = np.sin(np.pi * np.clip(t / 1.05, 0, 1)) ** 2
    place(buf, swept_noise(200, 2500, d, q=1.5, seed=2) * swell * 0.05, 0)
    # パッドの和音を1オクターブ上へゆっくり持ち上げる。音を少しずつずらして重ね、単純な電子音に聞こえないようにする
    rise = np.zeros_like(t)
    for base in (NOTE['G3'], NOTE['D4'], NOTE['Bb4']):
        for detune in (-0.005, 0.0, 0.005):
            f0 = base * (1 + detune)
            rise += glide(f0, f0 * 2, d)
    place(buf, lowpass(rise / 9, 2500) * swell * 0.5, 0)
    place(buf, glass_bell(NOTE['D6'], 0.6, decay=1.4, brightness=0.3, attack=0.04) * 0.22, 0.6)
    place(buf, glass_bell(NOTE['G6'], 0.5, decay=1.2, brightness=0.2, attack=0.04) * 0.14, 0.7)
    return fade_tail(reverb(lowpass(buf, 6000), size=0.95, mix=0.55), 0.3)


def pin_tap():
    """3. 地図のピンをタップ（0.3秒）: 小さなガラス玉を軽く叩く「ポロン」。反応の速さを優先して立ち上がりは短め。"""
    d = 0.3
    buf = np.zeros(int(SR * d))
    place(buf, glass_bell(NOTE['D6'], d, decay=0.45, brightness=0.5, attack=0.006), 0)
    place(buf, glass_bell(NOTE['G6'], d, decay=0.4, brightness=0.3, attack=0.01) * 0.35, 0.04)
    return fade_tail(reverb(lowpass(buf, 7000), size=0.4, mix=0.3), 0.08)


def body_select():
    """4. 星・月を選択（0.6秒）: 高音のベルを3音重ねた繊細な「キラン」。"""
    d = 0.6
    buf = np.zeros(int(SR * d))
    for k, note in enumerate(['Bb5', 'D6', 'G6']):
        place(buf, glass_bell(NOTE[note], 0.55, decay=0.8, brightness=0.3, attack=0.015) * (0.5 - 0.1 * k), 0.05 * k)
    place(buf, glass_bell(NOTE['D7'], 0.4, decay=0.5, brightness=0.0, attack=0.02) * 0.08, 0.12)
    return fade_tail(reverb(lowpass(buf, 7000), size=0.7, mix=0.45), 0.15)


def time_tick():
    """5. 時刻スライダー（0.12秒）: 連続しても耳障りにならない、小さなガラスの粒のような「チッ」。"""
    d = 0.12
    t = t_axis(d)
    tone = sum(np.sin(2 * np.pi * NOTE['G6'] * (1 + dt) * t) for dt in (-0.003, 0.0, 0.003)) / 3
    tone += 0.25 * np.sin(2 * np.pi * NOTE['G6'] * 2.0 * t) * np.exp(-t / 0.006)
    env = np.minimum(t / 0.004, 1.0) ** 2 * np.exp(-t / 0.018)
    mono = lowpass(tone * env, 5000)
    return fade_tail(reverb(mono, size=0.1, mix=0.15), 0.03)


def spot_found():
    """6. 観測可能な場所を発見（1.4秒）: 柔らかい「ポン」→ 4音のベルが上がる「キラララン」。"""
    d = 1.4
    buf = np.zeros(int(SR * d))
    t = t_axis(0.8)
    pon = (np.sin(2 * np.pi * NOTE['G3'] * t) + 0.3 * np.sin(2 * np.pi * NOTE['G4'] * t)) * np.exp(-t * 5) * np.minimum(t / 0.015, 1) ** 2
    place(buf, pon * 0.5, 0)
    for k, note in enumerate(['G5', 'Bb5', 'D6', 'G6']):
        place(buf, glass_bell(NOTE[note], 1.15, decay=1.7, brightness=0.4, attack=0.025) * 0.4, 0.16 + 0.11 * k)
    place(buf, soft_pad([NOTE['Bb4'], NOTE['D5'], NOTE['G5']], 1.15, 0.35, 0.6) * 0.16, 0.22)
    place(buf, breath(1.1, 1200, seed=3) * np.sin(np.pi * t_axis(1.1) / 1.1) * 0.04, 0.2)
    return fade_tail(reverb(lowpass(buf, 6500), size=1.0, mix=0.55), 0.35)


def map_gesture():
    """7. 3Dマップの回転・拡大（0.25秒）: 柔らかい風だけの控えめな「シュッ」。"""
    d = 0.25
    t = t_axis(d)
    env = np.sin(0.5 * np.pi * np.minimum(t / 0.07, 1.0)) ** 2 * np.exp(-np.maximum(t - 0.07, 0) / 0.06)
    air = swept_noise(500, 1100, d, q=0.9, seed=7)
    air /= np.abs(air).max()
    mono = lowpass(lowpass(air * env, 2500), 3500)  # 高音を抑える
    return fade_tail(reverb(mono, size=0.4, mix=0.3), 0.06)


SOUNDS = {
    'se_launch': launch,
    'se_map_open': map_open,
    'se_pin_tap': pin_tap,
    'se_body_select': body_select,
    'se_time_tick': time_tick,
    'se_spot_found': spot_found,
    'se_map_gesture': map_gesture,
}


def normalize(stereo):
    """鳴っている部分（最大の -40dB より大きい所）の RMS を目標にそろえ、ピークは上限で抑える。"""
    level = np.abs(stereo).max(axis=1)
    active = stereo[level > level.max() * 0.01]
    rms = np.sqrt((active ** 2).mean())
    gain = 10 ** (TARGET_RMS_DB / 20) / rms
    peak = np.abs(stereo).max() * gain
    limit = 10 ** (PEAK_LIMIT_DB / 20)
    if peak > limit:
        gain *= limit / peak
    return stereo * gain


def write_caf(name, stereo):
    pcm = (np.clip(stereo, -1, 1) * 32767).astype('<i2')
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = pathlib.Path(tmp) / f'{name}.wav'
        with wave.open(str(wav_path), 'wb') as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(['afconvert', '-f', 'caff', '-d', 'LEI16', str(wav_path), str(OUT_DIR / f'{name}.caf')], check=True)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, make in SOUNDS.items():
        stereo = normalize(make())
        write_caf(name, stereo)
        print(f'{name}.caf  {len(stereo) / SR:.2f}s  peak {20 * np.log10(np.abs(stereo).max()):.1f}dBFS')


if __name__ == '__main__':
    main()
