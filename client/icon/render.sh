#!/bin/sh
# Renders the app icon PNGs from icon.svg. Needs rsvg-convert (librsvg) and
# ImageMagick 7. Run from anywhere; the PNGs are committed.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
client=$(dirname "$here")
svg="$here/icon.svg"

# iOS: full-bleed squares without transparency (the App Store rejects alpha).
ios="$client/ios/Runner/Assets.xcassets/AppIcon.appiconset"
for spec in 20x20@1x:20 20x20@2x:40 20x20@3x:60 29x29@1x:29 29x29@2x:58 \
  29x29@3x:87 40x40@1x:40 40x40@2x:80 40x40@3x:120 60x60@2x:120 \
  60x60@3x:180 76x76@1x:76 76x76@2x:152 83.5x83.5@2x:167 1024x1024@1x:1024; do
  name=${spec%:*}
  px=${spec#*:}
  rsvg-convert -w "$px" -h "$px" "$svg" | magick - -alpha off -strip "PNG24:$ios/Icon-App-$name.png"
done

# Android before 8.0, which has no adaptive icons: a round icon, 48dp.
res="$client/android/app/src/main/res"
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density=${spec%:*}
  px=${spec#*:}
  big=$((px * 4))
  rsvg-convert -w "$big" -h "$big" "$svg" | magick - -alpha set \
    \( -size "${big}x${big}" xc:none -fill white \
    -draw "circle $((big / 2)),$((big / 2)) $((big / 2)),0" \) \
    -compose DstIn -composite -resize "${px}x${px}" -strip \
    "PNG32:$res/mipmap-$density/ic_launcher.png"
done
