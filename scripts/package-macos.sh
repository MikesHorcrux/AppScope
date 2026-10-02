#!/bin/bash
# Produce an Intel + Apple Silicon archive, optionally Developer ID signed/notarized.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
if [[ "${APPSCOPE_REQUIRE_NOTARIZATION:-0}" == "1" && ( -z "${APPSCOPE_SIGNING_IDENTITY:-}" || -z "${APPSCOPE_NOTARY_PROFILE:-}" ) ]]; then
  printf 'Public packaging requires a Developer ID identity and notarytool profile.\n' >&2
  exit 1
fi
if [[ -d /Applications/Xcode.app/Contents/Developer && -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift run appscope-docs --check
# Swift 6.1's Xcode multi-architecture path can report dependency manifest errors
# even when compilation succeeds. Build each native slice and combine explicitly.
swift build --build-system native -c release --arch arm64 --product appscope --jobs 2
arm64_dir="$(swift build --build-system native -c release --arch arm64 --show-bin-path)"
swift build --build-system native -c release --arch x86_64 --product appscope --jobs 2
x86_64_dir="$(swift build --build-system native -c release --arch x86_64 --show-bin-path)"
mkdir -p "$repo_root/dist"
staging_parent="$(mktemp -d "$repo_root/dist/.stage.XXXXXX")"
trap 'rm -rf "$staging_parent"' EXIT
lipo -create "$arm64_dir/appscope" "$x86_64_dir/appscope" -output "$staging_parent/appscope"
version="$("$staging_parent/appscope" --version)"
staging="$staging_parent/appscope-$version-macos-universal"
mkdir -p "$staging/licenses"
install -m 755 "$staging_parent/appscope" "$staging/appscope"
cp LICENSE README.md SECURITY.md CONTRIBUTING.md CHANGELOG.md "$staging/"
cp -R docs examples assets "$staging/"
cp scripts/install-binary.sh "$staging/install.sh"
printf '%s\n' "$version" > "$staging/VERSION"
revision="$(git rev-parse HEAD)"
dirty=false
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then dirty=true; fi
printf '{"version":"%s","source_revision":"%s","uncommitted_changes":%s}\n' "$version" "$revision" "$dirty" > "$staging/BUILD.json"
for dependency in .build/checkouts/*; do
  for license in "$dependency"/LICENSE "$dependency"/LICENSE.txt "$dependency"/LICENSE.md; do
    if [[ -f "$license" ]]; then install -m 644 "$license" "$staging/licenses/$(basename "$dependency").txt"; break; fi
  done
done
if [[ -n "${APPSCOPE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$APPSCOPE_SIGNING_IDENTITY" "$staging/appscope"
else
  codesign --force --sign - "$staging/appscope"
fi
codesign --verify --strict "$staging/appscope"
lipo -archs "$staging/appscope"
archive="$repo_root/dist/appscope-$version-macos-universal.tar.gz"
if [[ -n "${APPSCOPE_NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${APPSCOPE_SIGNING_IDENTITY:-}" ]]; then printf 'Notarization requires APPSCOPE_SIGNING_IDENTITY.\n' >&2; exit 1; fi
  ditto -c -k --keepParent "$staging" "$staging.zip"
  xcrun notarytool submit "$staging.zip" --keychain-profile "$APPSCOPE_NOTARY_PROFILE" --wait --output-format json > "$staging_parent/notary-result.json"
  "$repo_root/scripts/check-notary-result.sh" "$staging_parent/notary-result.json"
  # A bare command-line executable cannot be stapled; Gatekeeper checks the online ticket.
fi
COPYFILE_DISABLE=1 tar -czf "$archive" -C "$staging_parent" "$(basename "$staging")"
(cd "$repo_root/dist" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
printf 'Archive: %s\n' "$archive"
