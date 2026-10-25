"""既存CAFの16-bit PCMをAndroid対応WAVへ無損失で包み直す。"""
import array
from pathlib import Path
import shutil
import struct
import wave

def prepare(root: Path, output: Path):
    folder = root/'App/Resources/Sounds'
    shutil.copyfile(folder/'bgm_main.m4a', output/'bgm_main.m4a')
    for source in folder.glob('*.caf'):
        blob = source.read_bytes()
        assert blob[:4] == b'caff'
        offset, description, frames = 8, None, None
        while offset + 12 <= len(blob):
            kind, size = struct.unpack('>4sq', blob[offset:offset+12])
            offset += 12
            size = len(blob)-offset if size == -1 else size
            chunk = blob[offset:offset+size]
            if kind == b'desc':
                description = struct.unpack('>d4sIIIII', chunk)
            elif kind == b'data':
                frames = chunk[4:]
            offset += size
        assert description is not None and frames is not None
        rate, codec, flags, packet_bytes, packet_frames, channels, bits = description
        assert codec == b'lpcm' and bits == 16 and not flags & 1
        assert packet_frames == 1 and packet_bytes == channels*2
        if not flags & 2:
            samples = array.array('H')
            samples.frombytes(frames)
            samples.byteswap()
            frames = samples.tobytes()
        with wave.open(str(output/(source.stem+'.wav')), 'wb') as destination:
            destination.setparams((channels, 2, int(rate), 0, 'NONE', 'not compressed'))
            destination.writeframes(frames)
