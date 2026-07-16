#!/bin/bash

echo "========= OnTheSpot Linux Build Script ========="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo " => Cleaning up previous builds and preparing the environment..."
rm -f "$ROOT/build/dist/OnTheSpot.tar.gz"
mkdir -p "$ROOT/build/dist" "$ROOT/build/deps"
python3 -m venv "$ROOT/venv"
source "$ROOT/venv/bin/activate"


echo " => Upgrading pip and installing necessary dependencies..."
"$ROOT/venv/bin/pip" install --upgrade pip wheel pyinstaller
"$ROOT/venv/bin/pip" install -r "$ROOT/requirements.txt"


#echo " => Build FFMPEG (Optional)"
#FFBIN="--add-binary=$ROOT/build/deps/ffmpeg:onthespot/bin/ffmpeg"
#if ! [ -f "$ROOT/build/deps/ffmpeg" ]; then
#    mkdir -p "$ROOT/build/deps"
#    cd "$ROOT/build"
#    curl https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz -o ffmpeg.tar.xz
#    tar xf ffmpeg.tar.xz
#    cd ffmpeg-*
#    ./configure --enable-small --disable-ffplay --disable-ffprobe --disable-doc --disable-htmlpages --disable-manpages --disable-podpages --disable-txtpages
#    make
#    cp ffmpeg "$ROOT/build/deps/ffmpeg"
#    cd "$ROOT"
#fi


echo " => Running PyInstaller to create binary..."
pyinstaller --onefile \
    --hidden-import="zeroconf._utils.ipaddress" \
    --hidden-import="zeroconf._handlers.answers" \
    --add-data="$ROOT/src/onthespot/qt/qtui/*.ui:onthespot/qt/qtui" \
    --add-data="$ROOT/src/onthespot/resources/icons/*.png:onthespot/resources/icons" \
    --add-data="$ROOT/src/onthespot/resources/translations/*.qm:onthespot/resources/translations" \
    --add-data="$ROOT/src/onthespot/resources/theme.qss:onthespot/resources" \
    $FFBIN \
    --paths="$ROOT/src/onthespot" \
    --name=onthespot-gui \
    --icon="$ROOT/src/onthespot/resources/icons/onthespot.png" \
    --distpath="$ROOT/build/dist" \
    --workpath="$ROOT/build/pyinstaller_work" \
    --specpath="$ROOT/build" \
    "$ROOT/src/portable.py"


echo " => Packaging executable as tar.gz archive..."
cd "$ROOT/build/dist"
tar -czvf OnTheSpot.tar.gz onthespot-gui
cd "$ROOT"


echo " => Cleaning up temporary files..."
rm -rf "$ROOT/__pycache__" "$ROOT/build/pyinstaller_work" "$ROOT/build"/*.spec "$ROOT/venv"


echo " => Done! Packaged tar.gz is available in 'build/dist/OnTheSpot.tar.gz'."
