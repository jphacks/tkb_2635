import { Composition } from 'remotion';
import { AsteraIntro } from './AsteraIntro';

export const RemotionRoot = () => (
  <>
    <Composition id="AsteraIntro" component={AsteraIntro} durationInFrames={600} fps={30} width={1920} height={1080} />
    {/* インスタのリール用（9:16）。3D は astera_intro.py の --vertical で描く */}
    <Composition id="AsteraIntroVertical" component={AsteraIntro} durationInFrames={600} fps={30} width={1080} height={1920}
      defaultProps={{ vertical: true }} />
  </>
);
