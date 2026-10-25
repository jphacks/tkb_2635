import { Composition } from 'remotion';
import { AsteraIntro } from './AsteraIntro';

export const RemotionRoot = () => (
  <Composition id="AsteraIntro" component={AsteraIntro} durationInFrames={600} fps={30} width={1920} height={1080} />
);
