#!/bin/bash

echo "========= OnTheSpot macOS Build Script =========="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo " => Cleaning up previous builds and preparing the environment..."
rm -f "$ROOT/build/dist/OnTheSpotRebuilt.tar.gz"
mkdir -p "$ROOT/build/dist" "$ROOT/build/deps"
python3 -m venv "$ROOT/venv"
source "$ROOT/venv/bin/activate"


echo " => Upgrading pip and installing necessary dependencies..."
"$ROOT/venv/bin/pip" install --upgrade pip wheel pyinstaller
"$ROOT/venv/bin/pip" install -r "$ROOT/requirements.txt"


echo " => Build FFMPEG (Optional)"

# if uname -m | grep -q x86_64; then
# 	if ! [ -f "$ROOT/build/deps/ffmpeg" ]; then
#     	curl -L -o "$ROOT/build/deps/ffmpeg.zip" https://evermeet.cx/ffmpeg/ffmpeg-7.1.zip
#     	unzip "$ROOT/build/deps/ffmpeg.zip" -d "$ROOT/build/deps"
# 	fi
# else
#     curl -L -o "$ROOT/build/deps/ffmpeg.zip" https://github.com/markus-perl/ffmpeg-build-script/archive/refs/heads/master.zip
#     unzip "$ROOT/build/deps/ffmpeg.zip" -d "$ROOT/build/deps"
#     cd "$ROOT/build/deps/ffmpeg-build-script-master"
#     ./build-ffmpeg --build --skip-install
#     
#     cp workspace/bin/ffmpeg "$ROOT/build/deps/ffmpeg"
# 
#     cd "$ROOT"
# fi



FFBIN="--add-binary=$ROOT/build/deps/ffmpeg:onthespot/bin/ffmpeg"



echo " => Running PyInstaller to create .app package..."
pyinstaller --windowed --noconfirm \
    --hidden-import="zeroconf._utils.ipaddress" \
    --hidden-import="zeroconf._handlers.answers" \
    --add-data="$ROOT/src/onthespot/qt/qtui/*.ui:onthespot/qt/qtui" \
    --add-data="$ROOT/src/onthespot/resources/icons/*.png:onthespot/resources/icons" \
    --add-data="$ROOT/src/onthespot/resources/translations/*.qm:onthespot/resources/translations" \
    --add-data="$ROOT/src/onthespot/resources/theme.qss:onthespot/resources" \
    $FFBIN \
    --paths="$ROOT/src/onthespot" \
    --name="OnTheSpotRebuilt" \
    --icon="$ROOT/src/onthespot/resources/icons/onthespot.png" \
    --distpath="$ROOT/build/dist" \
    --workpath="$ROOT/build/pyinstaller_work" \
    --specpath="$ROOT/build" \
    "$ROOT/src/portable.py"


echo " => Setting executable permissions..."
chmod +x "$ROOT/build/dist/OnTheSpotRebuilt.app"


echo " => Creating dmg..."
mkdir -p "$ROOT/build/dist/dmg"
mv "$ROOT/build/dist/OnTheSpotRebuilt.app" "$ROOT/build/dist/dmg/OnTheSpotRebuilt.app"
ln -s /Applications "$ROOT/build/dist/dmg"

echo "# Login Issues
Newer versions of macOS have restricted networking features
for apps inside the 'Applications' folder. To login to your
account you will need to:

1. Run the following command in terminal, 'echo \"127.0.0.1 \$HOST\" | sudo tee -a /etc/hosts'

2. Launch the app and click add account before dragging into the applications folder.

3. After successfully logging in you can drag the app into the folder.


# Security Issues
After all this, if you experience an error while trying to launch
the app you will need to open the 'Applications' folder, right-click
the app, and click open anyway." > "$ROOT/build/dist/dmg/readme.txt"

hdiutil create -srcfolder "$ROOT/build/dist/dmg" -format UDZO -o "$ROOT/build/dist/OnTheSpotRebuilt.dmg"


echo " => Cleaning up temporary files..."
rm -rf "$ROOT/__pycache__" "$ROOT/build/pyinstaller_work" "$ROOT/build"/*.spec "$ROOT/venv"


echo " => Done! .dmg available in 'build/dist/OnTheSpotRebuilt.dmg'."
