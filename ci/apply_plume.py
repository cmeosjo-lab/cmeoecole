from pathlib import Path
from PIL import Image
import json
root=Path('.')
image=Image.open(root/'branding/plume.webp').convert('RGB')
if image.size != (512,512): raise RuntimeError('Source icon dimensions changed')
pub=root/'pubspec.yaml'; s=pub.read_text()
if 'version: 0.6.2+16' in s: pub.write_text(s.replace('version: 0.6.2+16','version: 0.6.3+17'))
elif 'version: 0.6.3+17' not in s: raise RuntimeError('Unexpected source version')
p=root/'lib/services/principal_api.dart'; s=p.read_text()
if "mobileVersion = '0.6.2'" in s: p.write_text(s.replace("mobileVersion = '0.6.2'", "mobileVersion = '0.6.3'"))
elif "mobileVersion = '0.6.3'" not in s: raise RuntimeError('Unexpected user agent version')
res=root/'android/app/src/main/res'
if res.exists():
 for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
  d=res/f'mipmap-{density}'; d.mkdir(parents=True,exist_ok=True)
  image.resize((size,size),Image.Resampling.LANCZOS).save(d/'ic_launcher.png')
 for d in res.glob('mipmap-anydpi*'):
  for n in ['ic_launcher.xml','ic_launcher_round.xml']:
   if (d/n).exists(): (d/n).unlink()
icons=root/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
if icons.exists():
 config=json.loads((icons/'Contents.json').read_text())
 for item in config['images']:
  size=float(item['size'].split('x')[0])*float(item.get('scale','1x').removesuffix('x'))
  filename=item.get('filename') or f"Icon-{item['idiom']}-{item['size']}-{item.get('scale','1x')}.png"
  item['filename']=filename
  image.resize((round(size),round(size)),Image.Resampling.LANCZOS).save(icons/filename)
 (icons/'Contents.json').write_text(json.dumps(config,indent=2))
print('Plume applied. Version 0.6.3+17. No database, UI, network or dependency change.')
