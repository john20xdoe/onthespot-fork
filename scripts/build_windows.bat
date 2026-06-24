@echo off

set FOLDER_NAME=%cd%
for %%F in ("%cd%") do set FOLDER_NAME=%%~nxF
if /i "%FOLDER_NAME%"=="scripts" (
    echo You are in the scripts folder. Changing to the parent directory...
    cd ..
)

set ROOT=%cd%

echo ========= OnTheSpot Windows Build Script =========


echo =^> Cleaning up previous builds...
del /F /Q /A "%ROOT%\build\dist\OnTheSpot.exe" "%ROOT%\build\dist\onthespot_win_executable.exe" 2>nul


echo =^> Creating virtual environment...
python -m venv "%ROOT%\venvwin"


echo =^> Activating virtual environment...
call "%ROOT%\venvwin\Scripts\activate.bat"


echo =^> Installing dependencies via pip...
python -m pip install --upgrade pip wheel pyinstaller
pip install -r "%ROOT%\requirements.txt"


echo =^> Downloading FFmpeg binary...
mkdir "%ROOT%\build\deps" 2>nul
if not exist "%ROOT%\build\deps\ffmpeg.zip" (
    curl -L -o "%ROOT%\build\deps\ffmpeg.zip" https://github.com/GyanD/codexffmpeg/releases/download/7.1/ffmpeg-7.1-essentials_build.zip
)
if not exist "%ROOT%\build\deps\ffmpeg" (
    powershell -Command "Expand-Archive -Path %ROOT%\build\deps\ffmpeg.zip -DestinationPath %ROOT%\build\deps\ffmpeg"
)


echo =^> Running PyInstaller to create .exe package...
pyinstaller --onefile --noconsole --noconfirm ^
    --hidden-import="zeroconf._utils.ipaddress" ^
    --hidden-import="zeroconf._handlers.answers" ^
    --add-data="%ROOT%\src\onthespot\resources\translations\*.qm;onthespot/resources/translations" ^
    --add-data="%ROOT%\src\onthespot\qt\qtui\*.ui;onthespot/qt/qtui" ^
    --add-data="%ROOT%\src\onthespot\resources\icons\*.png;onthespot/resources/icons" ^
    --add-data="%ROOT%\src\onthespot\resources\theme.qss;onthespot/resources" ^
    --add-binary="%ROOT%\build\deps\ffmpeg\ffmpeg-7.1-essentials_build\bin\ffmpeg.exe;onthespot/bin/ffmpeg" ^
    --paths="%ROOT%\src\onthespot" ^
    --name="OnTheSpot" ^
    --icon="%ROOT%\src\onthespot\resources\icons\onthespot.png" ^
    --distpath="%ROOT%\build\dist" ^
    --workpath="%ROOT%\build\pyinstaller_work" ^
    --specpath="%ROOT%\build" ^
    "%ROOT%\src\portable.py"


echo =^> Cleaning up temporary files...
del /F /Q "%ROOT%\build\*.spec" 2>nul
rmdir /s /q "%ROOT%\build\pyinstaller_work" __pycache__ ffbin_win "%ROOT%\venvwin" 2>nul


echo =^> Done! Executable available as 'build/dist/OnTheSpot.exe'.
