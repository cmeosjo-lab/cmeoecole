"""Apply and verify the existing GESTCOURS release identity. Never create a new key."""
from pathlib import Path
import base64
import hashlib
import os
import re
import subprocess
import tempfile

EXPECTED = '8c7ee6a60b8687a5fff73fccc6d49b06bfbbf843df44818867bf5eb2e714c173'
KEYS = ('RELEASE_KEYSTORE_B64', 'RELEASE_STORE_PASSWORD', 'RELEASE_KEY_ALIAS', 'RELEASE_KEY_PASSWORD')

def main():
    present = [bool(os.environ.get(k)) for k in KEYS]
    if not any(present):
        print('Secrets absents : aucun APK OFFICIEL publié. Les APK VALIDATION nécessitent la signature permanente avant diffusion.')
        return
    if not all(present):
        raise SystemExit('Configuration de signature incomplète. Aucun changement de clé automatique autorisé.')
    dist = Path('dist').resolve()
    jar = dist / 'apksigner.jar'
    inputs = sorted(dist.glob('*_VALIDATION.apk'))
    if not jar.is_file() or not inputs:
        raise SystemExit('Outil officiel apksigner ou APK de compilation absent.')
    with tempfile.TemporaryDirectory(prefix='gestcours-signing-') as temp:
        key = Path(temp) / 'release.p12'
        key.write_bytes(base64.b64decode(os.environ['RELEASE_KEYSTORE_B64'], validate=True))
        key.chmod(0o600)
        for apk in inputs:
            output = dist / apk.name.replace('_VALIDATION.apk', '_OFFICIEL.apk')
            temporary = Path(temp) / output.name
            subprocess.run(['java', '-jar', str(jar), 'sign', '--ks', str(key), '--ks-type', 'PKCS12',
                '--ks-pass', 'env:RELEASE_STORE_PASSWORD', '--ks-key-alias', os.environ['RELEASE_KEY_ALIAS'],
                '--key-pass', 'env:RELEASE_KEY_PASSWORD', '--v4-signing-enabled', 'false',
                '--out', str(temporary), str(apk)], check=True)
            checked = subprocess.run(['java', '-jar', str(jar), 'verify', '--verbose', '--print-certs', str(temporary)],
                check=True, capture_output=True, text=True)
            fingerprints = re.findall(r'certificate SHA-256 digest:\s*([0-9a-fA-F:]+)', checked.stdout)
            if fingerprints != [EXPECTED]:
                normalized = [x.replace(':', '').lower() for x in fingerprints]
                if normalized != [EXPECTED]:
                    raise SystemExit('Certificat différent de la signature permanente GESTCOURS : publication bloquée.')
            output.write_bytes(temporary.read_bytes())
            output.with_suffix('.verification.txt').write_text(checked.stdout, encoding='utf-8')
            output.with_suffix('.sha256.txt').write_text(hashlib.sha256(output.read_bytes()).hexdigest()+'  '+output.name+'\n', encoding='utf-8')
            print('Signature permanente vérifiée : '+output.name)

if __name__ == '__main__':
    main()
