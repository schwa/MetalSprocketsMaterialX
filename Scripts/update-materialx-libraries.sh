#!/bin/bash
# Replaces Sources/MaterialX/Resources/libraries with the .mtlx data libraries from a MaterialX release.
# Usage: Scripts/update-materialx-libraries.sh [tag]   (default v1.39.4)
# Shader-generator folders (gen*) are left out. Run the tests afterwards; update NOTICE.md if the version changes.
set -euo pipefail

tag="${1:-v1.39.4}"
root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$root/Sources/MaterialX/Resources/libraries"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsSL "https://github.com/AcademySoftwareFoundation/MaterialX/archive/refs/tags/$tag.tar.gz" | tar -xz -C "$work"
source="$(echo "$work"/MaterialX-*/libraries)"

rm -rf "$destination"
mkdir -p "$destination"
cp "$source/README.md" "$destination/"
(cd "$source" && find . -name '*.mtlx' -not -path '*/gen*' -print0) | while IFS= read -r -d '' file; do
    mkdir -p "$destination/$(dirname "$file")"
    cp "$source/$file" "$destination/$file"
done
echo "Updated $destination from MaterialX $tag"
