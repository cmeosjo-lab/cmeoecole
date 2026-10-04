from pathlib import Path
import base64, hashlib, zlib, subprocess
Path('dist').mkdir(exist_ok=True)
encoded=Path('ci/mobile_v062.diff.b64').read_text()
Path('dist/patch-transfer.txt').write_text(encoded)
if 'version: 0.6.2+16' not in Path('pubspec.yaml').read_text():
    # Correct transport transcription only; enforce the original SHA-256 below.
    for old,new in [('fXG4t7u3ixes','fXG4t7u3D3ixes'),('AnbXfgPys','AnbXfgys'),('AWAmoawW5Dz','AWAmoawWw5Dz'),('LtvDLugcKGwFJR2HN','LtvDLugcKGwF2HN'),('KuLyU5vy','KuLyUvy')]:
        encoded=encoded.replace(old,new)
    raw=zlib.decompress(base64.b64decode(encoded))
    assert hashlib.sha256(raw).hexdigest()=='06844ae11481b7f0df8a00f506be35c3eb6c8969a930700b0a038ea099670429', 'Patch checksum mismatch'
    subprocess.run(['git','apply','--check','-'], input=raw, check=True)
    subprocess.run(['git','apply','-'], input=raw, check=True)
p=Path('lib/screens/setup_screen.dart');s=p.read_text();s=s.replace('host.text = previous.host;', "host.text = previous.port == PrincipalApi.defaultPort ? previous.host : '${previous.host}:${previous.port}';")
s=s.replace("() => status = 'Connexion trouvée. Synchronisation de vos classes…',", "() { waiting = false; status = 'Connexion trouvée. Synchronisation de vos classes…'; },")
p.write_text(s)
print('Application V0.6.2 : interface simplifiée, compteurs sans suppression et QR avec attente d’accord.')
