#!/bin/bash
#
# jvp (Jamy-chan Video Player)
# Copyright (C) 2026 iwaxse
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

eval "$(/opt/homebrew/bin/brew shellenv)"
. /opt/homebrew/opt/asdf/libexec/asdf.sh

echo "💅 Starting production bundle build for Jamy-chan Video Player..."

# 1. Clean up
rm -rf build/macos
mkdir -p build/symbols

# 2. Icon Generation
echo "🎨 Generating app icons from docs/iwaxse.png..."
ICON_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"
SOURCE="docs/iwaxse.png"
TEMP_SQUARE="build/icon_square.png"

if [ -f "$SOURCE" ]; then
  # 1. 縦横の大きい方に合わせて、黒背景(000000)で正方形にパディングする（引き伸ばし防止！）
  WIDTH=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/ {print $2}')
  HEIGHT=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/ {print $2}')
  MAX_DIM=$WIDTH
  if [ "$HEIGHT" -gt "$WIDTH" ]; then MAX_DIM=$HEIGHT; fi
  
  sips -p "$MAX_DIM" "$MAX_DIM" --padColor 000000 "$SOURCE" --out "$TEMP_SQUARE" > /dev/null 2>&1
  
  # 2. 正方形になった画像を各サイズにリサイズ
  sips -z 16 16   "$TEMP_SQUARE" --out "$ICON_DIR/app_icon_16.png"   > /dev/null 2>&1
  sips -z 32 32   "$TEMP_SQUARE" --out "$ICON_DIR/app_icon_32.png"   > /dev/null 2>&1
  sips -z 64 64   "$TEMP_SQUARE" --out "$ICON_DIR/app_icon_64.png"   > /dev/null 2>&1
  sips -z 128 128 "$TEMP_SQUARE" --out "$ICON_DIR/app_icon_128.png"  > /dev/null 2>&1
  sips -z 256 256 "$TEMP_SQUARE" --out "$ICON_DIR/app_icon_256.png"  > /dev/null 2>&1
  sips -z 512 512 "$TEMP_SQUARE" --out "$ICON_DIR/app_icon_512.png"  > /dev/null 2>&1
  sips -z 1024 1024 "$TEMP_SQUARE" --out "$ICON_DIR/app_icon_1024.png" > /dev/null 2>&1
  
  rm "$TEMP_SQUARE"
  echo "✅ Icons generated successfully (Square + Black BG)!"
else
  echo "⚠️ docs/iwaxse.png not found, skipping icon generation."
fi

# 3. Rust Codegen & Build
echo "🚀 Generating Rust/Dart bridges..."
flutter_rust_bridge_codegen generate

echo "🦀 Building Rust backend (Release)..."
cd rust
cargo build --release
cd ..

# 3. Flutter Build with Obfuscation
echo "💅 Building Flutter macOS app with obfuscation (Tehepero!)..."
flutter build macos --release --obfuscate --split-debug-info=build/symbols

# 4. Bundling Rust Library
# macOS apps expect native libs in Contents/Frameworks
APP_PATH="build/macos/Build/Products/Release/jvp.app"
FRAMEWORKS_PATH="$APP_PATH/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_PATH"

echo "📦 Bundling Rust library into the app..."
cp rust/target/release/librust_lib_jvp.dylib "$FRAMEWORKS_PATH/"

# 5. Fix dylib ID (Optional but recommended for rogue apps)
install_name_tool -id "@executable_path/../Frameworks/librust_lib_jvp.dylib" "$FRAMEWORKS_PATH/librust_lib_jvp.dylib"

# 6. Create Zip Archive for Distribution
echo "📦 Creating zip archive for distribution..."
ZIP_NAME="jvp-macos.zip"
cd build/macos/Build/Products/Release
zip -r "../../../../$ZIP_NAME" jvp.app > /dev/null
cd - > /dev/null

# もし build/ に置きたい場合はこちら (今回はルートに置いて見つけやすくするね！)
mv "$ZIP_NAME" "build/$ZIP_NAME"

echo "✨ DONE! Your rogue app is ready at: $APP_PATH"
echo "📦 Distribution zip created at: build/$ZIP_NAME"
echo "💅 Slay! Go share the magic! 💖🚀"
