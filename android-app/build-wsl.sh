#!/usr/bin/env bash
set -euo pipefail

source_dir=$(realpath "$1")
mode=$2
version=$3
build_number=$4
flutter=/home/flutterdev/flutter/bin/flutter
case "$mode" in debug|release) ;; *) exit 2 ;; esac

# Keep Flutter's intermediate files and Gradle's I/O on the WSL filesystem.
work=$(mktemp -d /tmp/rezeptgarten-android.XXXXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
tar -C "$source_dir" \
    --exclude=android/.gradle \
    --exclude=android/.kotlin \
    --exclude=android/.cxx \
    --exclude=android/local.properties \
    --exclude=android/release-signing.properties \
    --exclude=android/gradlew \
    --exclude=android/gradlew.bat \
    --exclude=android/gradle/wrapper/gradle-wrapper.jar \
    --exclude=GeneratedPluginRegistrant.java \
    -cf - android assets lib test analysis_options.yaml pubspec.yaml pubspec.lock | tar -xf -
if [[ "$mode" == release ]]; then
    install -m 0600 "$source_dir/android/release-signing.properties" android/release-signing.properties
fi

"$flutter" pub get --enforce-lockfile
"$flutter" analyze --no-pub
timeout --kill-after=10s 360s "$flutter" test --no-pub --concurrency=1
"$flutter" build apk "--$mode" --no-pub --target-platform android-arm64 \
    --build-name "$version" --build-number "$build_number"

output_dir="$source_dir/build/app/outputs/flutter-apk"
mkdir -p "$output_dir"
output=$(mktemp "$output_dir/staging.XXXXXXXXXX")
trap 'rm -f -- "$output"; rm -rf -- "$work"' EXIT
cp "build/app/outputs/flutter-apk/app-$mode.apk" "$output"
mv -f -- "$output" "$output_dir/app-$mode.apk"
