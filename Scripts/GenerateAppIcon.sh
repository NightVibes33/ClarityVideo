#!/bin/sh
set -eu

SOURCE="$SRCROOT/ClarityVideo/Resources/Assets.xcassets/ReferenceArtwork.imageset/artwork.jpeg"
DESTINATION="$SRCROOT/ClarityVideo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
TEMP_ICON="$DERIVED_FILE_DIR/ClarityVideo-AppIcon-crop.png"

if [ ! -f "$SOURCE" ]; then
  echo "error: ClarityVideo reference artwork is missing: $SOURCE"
  exit 1
fi

mkdir -p "$(dirname "$DESTINATION")" "$DERIVED_FILE_DIR"

/usr/bin/sips   --cropToHeightWidth 248 248   --cropOffset 118 46   "$SOURCE"   --out "$TEMP_ICON" >/dev/null

/usr/bin/sips   --resampleHeightWidth 1024 1024   "$TEMP_ICON"   --out "$DESTINATION" >/dev/null

WIDTH=$(/usr/bin/sips -g pixelWidth "$DESTINATION" | /usr/bin/awk '/pixelWidth/ {print $2}')
HEIGHT=$(/usr/bin/sips -g pixelHeight "$DESTINATION" | /usr/bin/awk '/pixelHeight/ {print $2}')

if [ "$WIDTH" != "1024" ] || [ "$HEIGHT" != "1024" ]; then
  echo "error: Generated AppIcon.png is not 1024x1024"
  exit 1
fi

echo "Generated ClarityVideo AppIcon.png from the supplied reference artwork."
