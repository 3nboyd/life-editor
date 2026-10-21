#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-$root/.local-helpers}"
mkdir -p "$output/inventory"
"$output/ffmpeg" -version > "$output/inventory/ffmpeg-version.txt" 2>&1
"$output/ffmpeg" -hide_banner -buildconf > "$output/inventory/buildconf.txt" 2>&1
"$output/ffmpeg" -hide_banner -L > "$output/inventory/license.txt" 2>&1
"$output/ffmpeg" -hide_banner -protocols > "$output/inventory/protocols.txt" 2>&1
"$output/ffmpeg" -hide_banner -codecs > "$output/inventory/codecs.txt" 2>&1
"$output/ffmpeg" -hide_banner -formats > "$output/inventory/formats.txt" 2>&1
"$output/ffmpeg" -hide_banner -decoders > "$output/inventory/decoders.txt" 2>&1
"$output/ffmpeg" -hide_banner -encoders > "$output/inventory/encoders.txt" 2>&1
"$output/ffprobe" -hide_banner -buildconf > "$output/inventory/ffprobe-buildconf.txt" 2>&1
"$output/ffprobe" -hide_banner -L > "$output/inventory/ffprobe-license.txt" 2>&1
"$output/ffprobe" -v error -show_program_version -show_library_versions -of json > "$output/inventory/versions.json"
otool -L "$output/ffmpeg" "$output/ffprobe" > "$output/inventory/linked-libraries.txt"
python3 - "$output" <<'PY'
import json,pathlib,re,sys,hashlib
out=pathlib.Path(sys.argv[1]); inv=out/'inventory'
required=['source/ffmpeg-9.0.2.tar.xz','source/ffmpeg-9.0.2.tar.xz.asc','source/ffmpeg-devel.asc','source/config.mak','source/config.h','source/build-ffmpeg.sh','source/signature-verification.txt','licenses/COPYING.LGPLv2.1','NOTICE.txt']
for name in required:
    assert (out/name).is_file(), 'Missing distribution material: '+name
assert hashlib.sha256((out/'source/ffmpeg-9.0.2.tar.xz').read_bytes()).hexdigest()=='8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e', 'Wrong source archive'
assert 'VALIDSIG FCF986EA15E6E293A5644F10B4322F04D67658D8 ' in (out/'source/signature-verification.txt').read_text(), 'Source signature record missing'
config=(inv/'buildconf.txt').read_text()+(inv/'ffprobe-buildconf.txt').read_text()
probe_version=json.loads((inv/'versions.json').read_text())['program_version']
assert probe_version['version']=='9.0.2', 'Unexpected ffprobe version'
assert (inv/'ffmpeg-version.txt').read_text().startswith('ffmpeg version 9.0.2 '), 'Unexpected ffmpeg version'
for flag in ('--disable-gpl','--disable-nonfree','--disable-autodetect','--disable-network'):
    assert flag in config, flag
assert '--enable-gpl' not in config and '--enable-nonfree' not in config
for name in ['license.txt','ffprobe-license.txt']:
    assert 'GNU Lesser General Public License' in ' '.join((inv/name).read_text().split()), name
protocols=[line.strip() for line in (inv/'protocols.txt').read_text().splitlines() if line.startswith('  ')]
assert set(protocols)=={'file','pipe'}, protocols
links=(inv/'linked-libraries.txt').read_text()
for line in links.splitlines():
    if line.startswith('\t'):
        assert line.strip().startswith(('/usr/lib/','/System/Library/')),line
items={}
for category in ('codecs','formats','decoders','encoders'):
    rows=[]
    for line in (inv/(category+'.txt')).read_text().splitlines():
        match=re.match(r'^ ([A-Z\. ]{1,6})\s+(\S+)\s+(.*)$',line)
        if match and match.group(2)!='=':
            rows.append(dict(flags=match.group(1).strip(),name=match.group(2),description=match.group(3)))
    items[category]=rows
manifest=dict(dependency='FFmpeg',version='9.0.2',license='LGPL-2.1-or-later',source='https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz',protocols=sorted(set(protocols)),externalCodecLibraries=[],capabilities=items,binaries={name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in ('ffmpeg','ffprobe')})
(inv/'capabilities.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Verified LGPL configuration, system-only linkage, file/pipe protocols; inventory generated.')
PY
