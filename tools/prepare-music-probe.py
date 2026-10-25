"""Local simulator-only music source. No network service or account is contacted."""
import math
import struct
import wave
from pathlib import Path

root = Path("Xcode/BuildOutput/MusicProbe")
root.mkdir(parents=True, exist_ok=True)
with wave.open(str(root / "music.wav"), "wb") as audio:
    audio.setparams((1, 2, 24000, 0, "NONE", "not compressed"))
    audio.writeframes(b"".join(struct.pack("<h", int(1200 * math.sin(2 * math.pi * 220 * i / 24000))) for i in range(24000 * 8)))
(root / "music.html").write_text('''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>YL 음악 동시 표시 시험</title>
<body><h1>음악 동시 표시 시험</h1><audio id="music" src="music.wav" loop></audio><button id="play" style="font-size:24px">테스트 음악 재생</button>
<script>const track=document.getElementById('music'),button=document.getElementById('play');button.onclick=async()=>{await track.play();if('mediaSession' in navigator){navigator.mediaSession.metadata=new MediaMetadata({title:'YL 테스트 음악',artist:'동시 표시 검증'});navigator.mediaSession.playbackState='playing';}button.textContent='테스트 음악 재생 중';};</script></body></html>''', encoding="utf-8")
