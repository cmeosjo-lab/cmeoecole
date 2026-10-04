#!/usr/bin/env bash
set -euo pipefail
# This runs only on a fresh CI emulator, not a user's phone.
PACKAGE=fr.ecolegestion.ecole_gestion_prof_mobile
APK=dist/GESTCOURS_PROF_ANDROID_V0_6_2_UNIVERSEL_VALIDATION.apk
adb install -r "$APK"
adb shell am start -W -n "$PACKAGE/.MainActivity"
sleep 6
FOUND=0
for attempt in $(seq 1 6); do
  adb shell uiautomator dump /sdcard/gestcours-startup.xml || true
  adb pull /sdcard/gestcours-startup.xml dist/android-startup.xml || true
  if [[ -f dist/android-startup.xml ]] && grep -q 'Connexion au Principal' dist/android-startup.xml; then
    FOUND=1
    break
  fi
  sleep 3
done
adb exec-out screencap -p > dist/android-startup.png
adb logcat -d -t 600 > dist/android-startup-logcat.txt
if [[ "$FOUND" != 1 ]]; then
  echo 'Startup setup screen not found' >&2
  exit 1
fi
if grep -Eq 'Protection des données|DatabaseException|PRAGMA busy_timeout' dist/android-startup.xml; then
  echo 'Startup protection error still visible' >&2
  exit 1
fi
echo 'Release APK reached Connexion au Principal on the Android emulator.' | tee dist/android-startup-result.txt
