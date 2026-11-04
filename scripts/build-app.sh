#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
swift build --package-path "$project_dir" --configuration release
binary_dir="$(swift build --package-path "$project_dir" --configuration release --show-bin-path)"
bundle_dir="$project_dir/build/Agent Meter.app"

if [[ ! -f "$project_dir/Resources/AppIcon.icns" ]]; then
    swift "$project_dir/scripts/generate-icon.swift" "$project_dir"
fi

mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
cp "$binary_dir/AgentMeter" "$bundle_dir/Contents/MacOS/AgentMeter"
cp "$project_dir/Resources/Info.plist" "$bundle_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$bundle_dir/Contents/Resources/AppIcon.icns"
touch "$bundle_dir"
codesign --force --sign - --identifier dev.yyc.AgentMeter --timestamp=none "$bundle_dir"
print -r -- "Built: $bundle_dir"
