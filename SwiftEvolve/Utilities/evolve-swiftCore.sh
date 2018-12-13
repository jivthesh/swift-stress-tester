#!/bin/bash

until [ -e build ]; do
  if [[ "$(pwd)" == "/" ]]; then
    echo "FAIL: Can't find build directory"
    exit 1
  fi
  cd ..
done

if ! git -C swift diff --exit-code --quiet -- stdlib; then
  git -C swift status stdlib
  echo "FAIL: Unstaged changes in stdlib"
  exit 1
fi

BUILD_SCRIPT_ARGS="--build-subdir=buildbot_evolve-swiftCore" $@
ROOT="$(pwd)"
BUILD=$ROOT/build/buildbot_evolve-swiftCore
BUILD_SWIFT=$BUILD/swift-macosx-x86_64
EVOLVE=$ROOT/swift-stress-tester/SwiftEvolve

set -e

function run() {
  descString="$1"
  shift 1

  echo "BEGIN: $descString"
  echo '$' $@
  if eval $@ ; then
    echo "PASS: $descString"
  else
    echo "FAIL: $descString"
    exit 1
  fi
}

function buildSwift() {
  run "Building Swift with $phase" swift/utils/build-script $BUILD_SCRIPT_ARGS $@
}

function testSwift() {
  run "Testing Swift with $phase" llvm/utils/lit/lit.py -sv --param swift_site_config=$BUILD_SWIFT/test-macosx-x86_64/lit.site.cfg $@ swift/test
}

function evolveSwift() {
  run "Evolving Swift source code" env PATH="$BUILD/swiftpm-macosx-x86_64/x86_64-apple-macosx/debug:$PATH" swift run --package-path $EVOLVE swift-evolve --replace --rules=$EVOLVE/Utilities/swiftCore-exclude.json $ROOT/swift/stdlib/public/core/*.swift
}

function libs() {
  echo "$BUILD_SWIFT/lib/swift$1$2"
}

function saveLibs() {
  rm -r $(libs $1 $2)
  mv $(libs) $(libs $1 $2)
}

function mixLibs() {
  rm -r $(libs $1 $2)
  run "Copying $1 Modules to $phase" cp -Rc $(libs $1 $1) $(libs $1 $2)
  run "Copying $2 Binaries to $phase" rsync -av --include '*/' --include '*.dylib' --exclude '*' $(libs $2 $2)/ $(libs $1 $2)
}

function useLibs() {
  rm $(libs)
  ln -s $(libs $1 $2) $(libs)
}

phase="Current Modules, Current Binaries"
#buildSwift --llbuild --swiftpm --swiftsyntax
testSwift
saveLibs 'Current' 'Current'

evolveSwift
git -C swift diff --minimal -- stdlib >stdlib.diff

phase="Evolved Modules, Evolved Binaries"
buildSwift
testSwift --param swift_evolve
saveLibs 'Evolved' 'Evolved'

phase="Current Modules, Evolved Binaries"
mixLibs 'Current' 'Evolved'
useLibs 'Current' 'Evolved'
testSwift --param swift_evolve
