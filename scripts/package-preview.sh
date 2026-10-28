#!/bin/zsh
# Build a reviewable development preview. Publishing is a separate action.
set -eu
cd "${0:A:h:h}"
preview_tag="${1:-0.1.0-alpha.1}"
if [[ ! "$preview_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$' ]]; then
  print -u2 'Use a preview version such as 0.1.0-alpha.1.'
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 'Commit or set aside source changes before packaging a preview.'
  exit 1
fi
preview_commit=$(git rev-parse HEAD)
preview_destination="${2:-$PWD/dist/releases}"
mkdir -p "$preview_destination"
preview_destination="${preview_destination:A}"
archive_name="Life-Editor-$preview_tag-macOS-arm64.zip"
if [[ -e "$preview_destination/$archive_name" || -e "$preview_destination/$archive_name.sha256" ]]; then
  print -u2 'Preview destination already exists; use a new version or directory.'
  exit 1
fi
preview_lock="$preview_destination/.$archive_name.lock"
if ! mkdir "$preview_lock" 2>/dev/null; then
  print -u2 'Another package job owns this version destination.'
  exit 1
fi
preview_work=""
trap '[[ -z "$preview_work" ]] || rm -rf "$preview_work"; rmdir "$preview_lock"' EXIT
preview_work=$(mktemp -d "$preview_destination/.life-preview.XXXXXXXX")
preview_root="$preview_work/Life Editor $preview_tag"
mkdir -p "$preview_root"
scripts/build-app.sh "$preview_root/Life Editor.app"
preview_app="$preview_root/Life Editor.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${preview_tag%%-alpha.*}" "$preview_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${preview_tag##*-alpha.}" "$preview_app/Contents/Info.plist"
codesign --force --sign - "$preview_app"
codesign --verify --strict "$preview_app"
lipo "$preview_app/Contents/MacOS/LifeEditor" -verify_arch arm64
cp LICENSE "$preview_root/LICENSE"
cp docs/DEPENDENCIES.md "$preview_root/DEPENDENCIES.md"
cp docs/PREVIEW.md "$preview_root/READ-ME.md"
python3 - "$preview_root" "$preview_tag" <<'PY'
import json, pathlib, plistlib, subprocess, sys
root=pathlib.Path(sys.argv[1]); app=root/'Life Editor.app'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
manifest=dict(version=sys.argv[2],commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
              minimumMacOS=info['LSMinimumSystemVersion'],architecture='arm64',
              signing='ad-hoc',notarized=False,mediaHelpers=(app/'Contents/Resources/Helpers/ffmpeg').is_file())
(root/'BUILD.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
ditto -c -k --sequesterRsrc --keepParent "$preview_root" "$preview_work/$archive_name"
# Validate the archive and signed app after extraction, not just the build tree.
mkdir "$preview_work/verify"
ditto -x -k "$preview_work/$archive_name" "$preview_work/verify"
codesign --verify --strict "$preview_work/verify/Life Editor $preview_tag/Life Editor.app"
(cd "$preview_work" && shasum -a 256 "$archive_name" > "$archive_name.sha256")
if [[ "$preview_commit" != "$(git rev-parse HEAD)" || -n "$(git status --porcelain)" ]]; then
  print -u2 'Source changed during packaging; archive was not published.'
  exit 1
fi
# Hard-link installation is atomic and fails if a destination already exists.
# The staging directory is on the destination volume.
ln "$preview_work/$archive_name" "$preview_destination/$archive_name"
ln "$preview_work/$archive_name.sha256" "$preview_destination/$archive_name.sha256"
print -r -- "$preview_destination/$archive_name"
