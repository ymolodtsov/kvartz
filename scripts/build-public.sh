#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
arm_scratch="$project_dir/.build/public-arm64"
intel_scratch="$project_dir/.build/public-x86_64"
app_dir="$project_dir/dist/Kvartz.app"
contents_dir="$app_dir/Contents"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")"
archive="$project_dir/dist/Kvartz-$version-macOS-universal.zip"
sign_identity="${CODE_SIGN_IDENTITY:--}"

cd "$project_dir"
swift build -c release --arch arm64 --scratch-path "$arm_scratch"
swift build -c release --arch x86_64 --scratch-path "$intel_scratch"

arm_binary_dir="$(swift build -c release --arch arm64 --scratch-path "$arm_scratch" --show-bin-path)"
intel_binary_dir="$(swift build -c release --arch x86_64 --scratch-path "$intel_scratch" --show-bin-path)"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
lipo -create "$arm_binary_dir/Kvartz" "$intel_binary_dir/Kvartz" -output "$contents_dir/MacOS/Kvartz"
cp "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Assets/Kvartz.icns" "$contents_dir/Resources/Kvartz.icns"
chmod +x "$contents_dir/MacOS/Kvartz"

if [[ "$sign_identity" == "-" ]]; then
    codesign --force --deep --sign - "$app_dir"
else
    codesign --force --deep --options runtime --timestamp --sign "$sign_identity" "$app_dir"
fi

codesign --verify --deep --strict "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive"

echo "$archive"
lipo -archs "$contents_dir/MacOS/Kvartz"
shasum -a 256 "$archive"
