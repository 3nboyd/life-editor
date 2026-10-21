#!/bin/bash
set -euo pipefail
# No external codec libraries; rebuild when changing this pin or configuration.
version=9.0.2
sha256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
fingerprint=FCF986EA15E6E293A5644F10B4322F04D67658D8
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${LIFE_HELPER_OUTPUT:-$root/.local-helpers}"
work="${LIFE_FFMPEG_WORK:-$root/.ffmpeg-build}"
command -v gpg >/dev/null || { echo 'GnuPG required to authenticate official source.' >&2; exit 1; }
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || { echo 'This build targets Apple Silicon macOS.' >&2; exit 1; }
mkdir -p "$work/download" "$output/source" "$output/licenses" "$output/inventory" "$work/keyring"
chmod 700 "$work/keyring"
archive="ffmpeg-$version.tar.xz"
for suffix in '' '.asc'; do
  [ -s "$work/download/$archive$suffix" ] || curl --fail --location --retry 3 --max-time 180 "https://ffmpeg.org/releases/$archive$suffix" -o "$work/download/$archive$suffix"
done
curl --fail --location --retry 3 --max-time 60 https://ffmpeg.org/ffmpeg-devel.asc -o "$work/download/ffmpeg-devel.asc"
gpg --homedir "$work/keyring" --batch --import "$work/download/ffmpeg-devel.asc" >/dev/null 2>&1
gpg --homedir "$work/keyring" --batch --status-fd 1 --verify "$work/download/$archive.asc" "$work/download/$archive" > "$output/source/signature-verification.txt" 2>&1
grep -q "VALIDSIG $fingerprint " "$output/source/signature-verification.txt"
actual_sha256="$(shasum -a 256 "$work/download/$archive" | cut -d ' ' -f 1)"
[ "$actual_sha256" = "$sha256" ] || { echo 'Source checksum differs from authenticated release pin.' >&2; exit 1; }
printf '%s  %s\n' "$sha256" "$archive" > "$output/source/SHA256SUMS"
cp "$work/download/$archive" "$work/download/$archive.asc" "$work/download/ffmpeg-devel.asc" "$output/source/"
[ -f "$work/ffmpeg-$version/configure" ] || tar -xf "$work/download/$archive" -C "$work"
cd "$work/ffmpeg-$version"
if [ ! -f ffbuild/config.mak ]; then
 ./configure --prefix="$work/install" --arch=arm64 --target-os=darwin --cc=clang \
  --disable-gpl --disable-nonfree --disable-version3 --disable-autodetect \
  --disable-shared --enable-static --disable-doc --disable-debug --disable-ffplay \
  --disable-network --disable-protocols --enable-protocol=file,pipe \
  --disable-devices --disable-indevs --disable-outdevs --enable-videotoolbox --enable-audiotoolbox \
  --extra-cflags=-mmacosx-version-min=15.0 --extra-ldflags=-mmacosx-version-min=15.0
fi
make -j "${LIFE_BUILD_JOBS:-4}" ffmpeg ffprobe
cp ffmpeg ffprobe "$output/"
cp COPYING.* LICENSE.md "$output/licenses/"
cp ffbuild/config.mak config.h "$output/source/"
cp "$root/scripts/build-ffmpeg.sh" "$output/source/build-ffmpeg.sh"
printf '%s\n' 'FFmpeg is a separate executable dependency, licensed LGPL-2.1-or-later.' 'Original Life Editor code is MIT; its license does not replace FFmpeg notices.' 'Matching upstream source archive, signature, configure output, and build script accompany these binaries.' 'No external codec libraries are linked. Apple system frameworks are provided by macOS.' 'Upstream: https://ffmpeg.org/ ; source: https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz' > "$output/NOTICE.txt"
"$root/scripts/verify-ffmpeg.sh" "$output"
