#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if [[ -z ${DEVELOPER_DIR:-} && -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
# CLT does not expose Testing on its default module search path. Use Xcode's
# complete overlay when installed, otherwise the selected CLT framework.
frameworks=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
if [[ ! -d $frameworks/Testing.framework ]]; then
  frameworks="$DEVELOPER_DIR/Library/Developer/Frameworks"
fi
if [[ $DEVELOPER_DIR == /Library/Developer/CommandLineTools && -d $frameworks/Testing.framework ]]; then
  overlay_flags=()
  # Some CLT releases ship the Foundation attachment binary without its Swift
  # module. Tests do not use attachment APIs; avoid importing that absent module.
  if [[ ! -d $frameworks/_Testing_Foundation.framework/Modules ]]; then
    overlay_flags=(-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays)
  fi
  swift test --disable-sandbox -Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" "${overlay_flags[@]}" "$@"
else
  swift test --disable-sandbox "$@"
fi
