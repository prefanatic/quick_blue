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
  quick_blue_darwin
  quick_blue_linux
  quick_blue_windows
  quick_blue
)

package_version() {
  sed -n 's/^version: //p' "$repo_root/$1/pubspec.yaml"
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
for package in quick_blue_darwin quick_blue_linux quick_blue_windows; do
  if ! grep -Fq "quick_blue_platform_interface: $expected_constraint" \
    "$repo_root/$package/pubspec.yaml"; then
    echo "$package does not depend on quick_blue_platform_interface $expected_constraint" >&2
    exit 65
  fi
done
for package in "${packages[@]:0:4}"; do
  if ! grep -Fq "$package: $expected_constraint" \
    "$repo_root/quick_blue/pubspec.yaml"; then
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
