#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
configuration="${1:-release}"
sign_identity="${CODE_SIGN_IDENTITY:--}"

cd "$project_dir"
swift build -c "$configuration"

binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$project_dir/dist/Kvartz.app"
contents_dir="$app_dir/Contents"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/Kvartz" "$contents_dir/MacOS/Kvartz"
cp "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Assets/Kvartz.icns" "$contents_dir/Resources/Kvartz.icns"
chmod +x "$contents_dir/MacOS/Kvartz"
codesign --force --deep --sign "$sign_identity" "$app_dir"

echo "$app_dir"
