#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 [--dry-run|--publish]"
}

mode="--dry-run"
if [[ $# -gt 1 ]]; then
  usage >&2
  exit 64
fi
if [[ $# -eq 1 ]]; then
  mode="$1"
fi
if [[ "$mode" != "--dry-run" && "$mode" != "--publish" ]]; then
  usage >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages=(
  quick_blue_platform_interface
  quick_blue_core
  quick_blue_linux_dart
  quick_blue_darwin
  quick_blue_linux
  quick_blue_windows
  quick_blue
)

package_version() {
  local value
  value="$(sed -n 's/^version: //p' "$repo_root/$1/pubspec.yaml")"
  if [[ ! "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
    echo "$1 has missing or malformed version: $value" >&2
    return 65
  fi
  printf '%s\n' "$value"
}

dependency_matches() {
  local lines
  lines="$(sed -n "s/^  $2: //p" "$repo_root/$1/pubspec.yaml")"
  [[ "$lines" == "$expected_constraint" ]]
}

release_version="$(package_version "${packages[0]}")"
for package in "${packages[@]}"; do
  version="$(package_version "$package")"
  if [[ "$version" != "$release_version" ]]; then
    echo "$package is $version; expected $release_version" >&2
    exit 65
  fi
done

expected_constraint="^$release_version"
for package in quick_blue_core quick_blue_darwin quick_blue_linux quick_blue_linux_dart quick_blue_windows; do
  if ! dependency_matches "$package" quick_blue_platform_interface; then
    echo "$package does not depend on quick_blue_platform_interface $expected_constraint" >&2
    exit 65
  fi
done
for package in quick_blue_linux quick_blue_linux_dart; do
  if ! dependency_matches "$package" quick_blue_core; then
    echo "$package does not depend on quick_blue_core $expected_constraint" >&2
    exit 65
  fi
done
if ! dependency_matches quick_blue_linux quick_blue_linux_dart; then
  echo "quick_blue_linux does not depend on quick_blue_linux_dart $expected_constraint" >&2
  exit 65
fi
for package in quick_blue_platform_interface quick_blue_core quick_blue_darwin quick_blue_linux quick_blue_windows; do
  if ! dependency_matches quick_blue "$package"; then
    echo "quick_blue does not depend on $package $expected_constraint" >&2
    exit 65
  fi
done

publish_args=(publish --dry-run --ignore-warnings)
if [[ "$mode" == "--publish" ]]; then
  publish_args=(publish)
fi

echo "QuickBlue $release_version ($mode)"
for package in "${packages[@]}"; do
  echo "Publishing $package"
  dart pub -C "$repo_root/$package" "${publish_args[@]}"
done
