from pathlib import Path
import plistlib
import re

info = Path("ios/Runner/Info.plist")
if not info.exists():
    raise SystemExit("Info.plist iOS introuvable")

with info.open("rb") as f:
    data = plistlib.load(f)

data["CFBundleDisplayName"] = "GESTCOURS Prof"
data["NSLocalNetworkUsageDescription"] = (
    "GESTCOURS Prof se connecte uniquement au PC Principal de l’établissement "
    "sur le réseau Wi-Fi/local afin de synchroniser les classes et les saisies."
)
data["NSCameraUsageDescription"] = (
    "La caméra sert uniquement à scanner le QR code facultatif de connexion au PC Principal."
)
ats = data.get("NSAppTransportSecurity")
if not isinstance(ats, dict):
    ats = {}
ats["NSAllowsLocalNetworking"] = True
data["NSAppTransportSecurity"] = ats

with info.open("wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML, sort_keys=False)

pbx = Path("ios/Runner.xcodeproj/project.pbxproj")
if not pbx.exists():
    raise SystemExit("Projet Xcode iOS introuvable")
text = pbx.read_text(encoding="utf-8")
text = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;", text)
pbx.write_text(text, encoding="utf-8")

print("iOS configuré : iOS 15+, réseau local, HTTP LAN et caméra QR.")
