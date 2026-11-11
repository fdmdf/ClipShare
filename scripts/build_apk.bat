@echo off
CALL stop_gradle
call flutter build apk --target-platform android-arm,android-arm64,android-x64 --split-per-abi
start ..\build\app\outputs\apk\release