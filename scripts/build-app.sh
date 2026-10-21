#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if [[ -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}
fi
build_directory="${LIFE_BUILD_DIRECTORY:-$PWD/.build/app}"
swift build --disable-sandbox -c release --scratch-path "$build_directory"
binary_directory=$(swift build -c release --scratch-path "$build_directory" --show-bin-path)
app="${1:-$PWD/dist/Life Editor.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_directory/LifeEditor" "$app/Contents/MacOS/LifeEditor"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
# Helpers are generated artifacts; never retain an older helper build implicitly.
rm -rf "$app/Contents/Resources/Helpers"
if [[ -x .local-helpers/ffmpeg && -x .local-helpers/ffprobe ]]; then
  scripts/verify-ffmpeg.sh .local-helpers
  ditto .local-helpers "$app/Contents/Resources/Helpers"
  codesign --force --sign - "$app/Contents/Resources/Helpers/ffmpeg"
  codesign --force --sign - "$app/Contents/Resources/Helpers/ffprobe"
  scripts/verify-ffmpeg.sh "$app/Contents/Resources/Helpers"
fi
# Local source builds use ad-hoc signing; distribution signing is a separate step.
# Finder may attach display metadata after opening an existing generated bundle.
# Remove only resource-fork/Finder metadata from this build artifact.
xattr -dr com.apple.FinderInfo "$app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$app" 2>/dev/null || true
codesign --force --sign - "$app"
codesign --verify --strict "$app"
print -r -- "$app"
