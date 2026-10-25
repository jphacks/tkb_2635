import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from 'remotion';
import title from './title-paths.json';

// Blender で描いた 3D（video/blender/astera_intro.py）の連番の上に、手書きのタイトルを重ねる
const WRITE_START = 400;   // 13.3 秒: 見上げ終わってから書き始める
const WRITE_END = 505;     // 1 文字ずつ、左から書く
const TAGLINE_START = 515;

const [minX, minY, maxX, maxY] = title.box;
const pad = 120;
const viewBox = `${minX - pad} ${-maxY - pad} ${maxX - minX + pad * 2} ${maxY - minY + pad * 2}`;

const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;

// 横長（発表用）と縦長（インスタのリール用）で、連番の置き場所と文字の大きさを変える
type Props = { vertical?: boolean };
const layout = (vertical?: boolean) => vertical
  ? { frames: 'frames-vertical', titleWidth: 940, titleTop: -140, taglineTop: 300, taglineSize: 40 }
  : { frames: 'frames', titleWidth: 1100, titleTop: -90, taglineTop: 330, taglineSize: 46 };

const Background = ({ vertical }: Props) => {
  const frame = useCurrentFrame();
  const name = `${layout(vertical).frames}/frame_${String(frame + 1).padStart(4, '0')}.png`;
  const fadeIn = interpolate(frame, [0, 20], [1, 0], clamp);
  return (
    <AbsoluteFill>
      <Img src={staticFile(name)} style={{ width: '100%', height: '100%' }} />
      <AbsoluteFill style={{ backgroundColor: 'black', opacity: fadeIn }} />
    </AbsoluteFill>
  );
};

const Title = ({ vertical }: Props) => {
  const frame = useCurrentFrame();
  const { titleWidth, titleTop } = layout(vertical);
  const count = title.glyphs.length;
  const span = (WRITE_END - WRITE_START) / count;
  return (
    <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center' }}>
      <svg viewBox={viewBox} style={{ width: titleWidth, marginTop: titleTop, overflow: 'visible' }}>
        <defs>
          <filter id="glow" x="-20%" y="-50%" width="140%" height="200%">
            <feGaussianBlur stdDeviation="18" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>
        <g transform="scale(1,-1)" filter="url(#glow)">
          {title.glyphs.map((glyph, index) => {
            const start = WRITE_START + index * span * 0.85;
            const end = start + span * 1.5;
            const draw = interpolate(frame, [start, end], [1, 0], { ...clamp, easing: Easing.out(Easing.quad) });
            const fill = interpolate(frame, [end - span * 0.4, end + 14], [0, 1], clamp);
            return (
              <g key={index} transform={`translate(${glyph.x},0)`}>
                <path d={glyph.d} pathLength={1} fill="none" stroke="#dff6ff" strokeWidth={7}
                  strokeDasharray="1 1" strokeDashoffset={draw} strokeLinecap="round" />
                <path d={glyph.d} fill="#f4fbff" opacity={fill} />
              </g>
            );
          })}
        </g>
      </svg>
    </AbsoluteFill>
  );
};

const Tagline = ({ vertical }: Props) => {
  const frame = useCurrentFrame();
  const { taglineTop, taglineSize } = layout(vertical);
  const opacity = interpolate(frame, [TAGLINE_START, TAGLINE_START + 30], [0, 1], clamp);
  const y = interpolate(frame, [TAGLINE_START, TAGLINE_START + 30], [12, 0], { ...clamp, easing: Easing.out(Easing.cubic) });
  return (
    <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center' }}>
      <div style={{
        marginTop: taglineTop, opacity, transform: `translateY(${y}px)`, color: '#e6f1ff',
        fontFamily: '"Hiragino Mincho ProN", serif', fontSize: taglineSize, letterSpacing: '0.3em',
        textShadow: '0 0 24px rgba(120, 200, 255, 0.55)',
      }}>
        街の中で、星が見える場所へ。
      </div>
    </AbsoluteFill>
  );
};

export const AsteraIntro = ({ vertical }: Props) => {
  const frame = useCurrentFrame();
  // 文字が読みやすいよう、書き始める少し前から空を少しだけ暗くする
  const dim = interpolate(frame, [380, 430], [0, 0.25], clamp);
  return (
    <AbsoluteFill style={{ backgroundColor: 'black' }}>
      <Background vertical={vertical} />
      <AbsoluteFill style={{ background: 'radial-gradient(ellipse at center, rgba(0,0,0,0.6), transparent 70%)', opacity: dim * 4 }} />
      <Title vertical={vertical} />
      <Tagline vertical={vertical} />
    </AbsoluteFill>
  );
};
