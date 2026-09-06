#!/bin/sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
master="$workspace_dir/Support/AquaApp/AppIcon-master.png"
catalog="$workspace_dir/Support/AquaApp/Assets.xcassets/AppIcon.appiconset"
icns="$workspace_dir/Support/AquaApp/AppIcon.icns"
scratch_dir=$(mktemp -d /private/tmp/webkitui-app-icon.XXXXXX)
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM
compiled_dir="$scratch_dir/compiled"

command -v magick >/dev/null
command -v xcrun >/dev/null
test -s "$master"
test "$(sips -g pixelWidth "$master" | awk '/pixelWidth:/ {print $2}')" = 1024
test "$(sips -g pixelHeight "$master" | awk '/pixelHeight:/ {print $2}')" = 1024
test "$(sips -g hasAlpha "$master" | awk '/hasAlpha:/ {print $2}')" = yes
test "$(magick "$master" -format '%[fx:p{0,0}.a]' info:)" = 0

for specification in \
  '16:icon_16x16.png' \
  '32:icon_16x16@2x.png' \
  '32:icon_32x32.png' \
  '64:icon_32x32@2x.png' \
  '128:icon_128x128.png' \
  '256:icon_128x128@2x.png' \
  '256:icon_256x256.png' \
  '512:icon_256x256@2x.png' \
  '512:icon_512x512.png' \
  '1024:icon_512x512@2x.png'; do
  pixels=${specification%%:*}
  filename=${specification#*:}
  magick "$master" -filter Lanczos -resize "${pixels}x${pixels}" \
    -colorspace sRGB -depth 8 "$catalog/$filename"
done

mkdir -p "$compiled_dir"
xcrun actool "$workspace_dir/Support/AquaApp/Assets.xcassets" \
  --compile "$compiled_dir" \
  --platform macosx \
  --minimum-deployment-target 15.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$compiled_dir/partial.plist" >/dev/null
install -m 0644 "$compiled_dir/AppIcon.icns" "$icns"
file "$icns" | grep -q 'Mac OS X icon'

for specification in \
  '16:icon_16x16.png' \
  '32:icon_16x16@2x.png' \
  '32:icon_32x32.png' \
  '64:icon_32x32@2x.png' \
  '128:icon_128x128.png' \
  '256:icon_128x128@2x.png' \
  '256:icon_256x256.png' \
  '512:icon_256x256@2x.png' \
  '512:icon_512x512.png' \
  '1024:icon_512x512@2x.png'; do
  pixels=${specification%%:*}
  filename=${specification#*:}
  test "$(sips -g pixelWidth "$catalog/$filename" | awk '/pixelWidth:/ {print $2}')" = "$pixels"
  test "$(sips -g pixelHeight "$catalog/$filename" | awk '/pixelHeight:/ {print $2}')" = "$pixels"
done

printf '%s\n' "App icon catalog and ICNS regenerated from AppIcon-master.png."
