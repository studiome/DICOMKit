#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <CharLS tag or commit>" >&2
    exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
charls_directory="$repository_root/Vendor/CharLS"

git -C "$charls_directory" fetch --tags origin
git -C "$charls_directory" checkout "$1"

echo "CharLS is now pinned to $(git -C "$charls_directory" rev-parse HEAD)."
echo "Run swift test, then stage .gitmodules and Vendor/CharLS before committing."
