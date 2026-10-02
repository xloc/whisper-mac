#!/bin/sh
set -eu

if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release

app="Whisper PTT.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/release/whisper-ptt" "$app/Contents/MacOS/whisper-ptt"
cp App/Info.plist "$app/Contents/Info.plist"
cp -R .build/release/whisper-ptt_WhisperPTTCore.bundle "$app/Contents/Resources/"

signing_identity="${WHISPER_PTT_SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ]; then
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)".*/\1/p' | head -1)
fi

if [ -n "$signing_identity" ]; then
    echo "signing with $signing_identity"
    codesign --force --deep --sign "$signing_identity" "$app"
else
    echo "warning: no Apple Development identity; using ad-hoc signing"
    echo "Accessibility permission may need to be granted again after source changes"
    codesign --force --deep --sign - "$app"
fi
echo "$app"
