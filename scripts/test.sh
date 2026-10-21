#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if [[ -z ${DEVELOPER_DIR:-} && -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
# CLT has a Swift compiler/SDK but does not ship the complete Testing overlay.
frameworks=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
if [[ $DEVELOPER_DIR == /Library/Developer/CommandLineTools && -d $frameworks/Testing.framework ]]; then
  swift test --disable-sandbox -Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" "$@"
else
  swift test --disable-sandbox "$@"
fi
