"""Download pinned public model test inputs, verify all bytes, no user content/network TTS."""
import hashlib, pathlib, re, urllib.request
root = pathlib.Path(__file__).resolve().parent.parent
source = (root / 'TeslaLocal.swiftpm/Sources/AppModule/VoicePackManifest.swift').read_text()
revision = re.search(r'static let revision = "([a-f0-9]{40})"', source)[1]
entries = re.findall(r'\.init\(path: "([\w/\.]+)", bytes: (\d+), sha256: "([a-f0-9]{64})"\)', source)
assert len(entries) == 17
for name, size, digest in entries:
    path = root / 'Xcode/VoiceProbeData' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    url = f'https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/{revision}/{name}'
    urllib.request.urlretrieve(url, path)
    assert path.stat().st_size == int(size), name
    with path.open('rb') as stream:
        assert hashlib.file_digest(stream, 'sha256').hexdigest() == digest, name
print('PASS: all 17 pinned voice model files SHA256 and length')
