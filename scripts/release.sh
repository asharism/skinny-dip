#!/usr/bin/env bash
# Build Skinny and publish it as a GitHub Release that Sparkle can auto-update from.
#
#   scripts/release.sh 0.2.0              # test, build, sign, tag v0.2.0, publish
#   scripts/release.sh 0.2.0 --skip-tests
#   scripts/release.sh 0.2.0 --dry-run    # build and sign into dist/, publish nothing
#
# Signing (ADR-0009): uses "Developer ID Application" plus notarization when that
# identity is in the keychain (notary credentials from
# `xcrun notarytool store-credentials skinny-notary`), otherwise ad-hoc.
# Updates are always EdDSA-signed by Sparkle's generate_appcast, using the private
# key in the login keychain. Back that key up: without it, installed copies can
# never update again.
#   .build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x skinny-ed25519.key
set -euo pipefail

usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

VERSION="${1:-}"; shift || true
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || usage
SKIP_TESTS=0; DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --skip-tests) SKIP_TESTS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) usage ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Skinny"
SCHEME="SkinnyDip"
TAG="v$VERSION"
REPO="asharism/skinny-dip"
DERIVED="$ROOT/.build/release"
DIST="$ROOT/dist/$TAG"
SPARKLE_BIN="$ROOT/.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin"
NOTARY_PROFILE="${SKINNY_NOTARY_PROFILE:-skinny-notary}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────
step "Checking prerequisites"
for tool in xcodegen xcodebuild gh ditto; do
  command -v "$tool" >/dev/null || die "$tool not found"
done
if [[ $DRY_RUN == 0 ]]; then
  gh auth status >/dev/null 2>&1 || die "gh is not logged in (run: gh auth login)"
  [[ "$(git branch --show-current)" == "main" ]] || die "release from main"
  [[ -z "$(git status --porcelain)" ]] || die "working tree is not clean"
  git fetch --quiet origin main --tags
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main is not in sync with origin/main"
  ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "tag $TAG already exists"
fi

# Build number: the commit count, so it only ever grows (Sparkle compares it).
BUILD="$(git rev-list --count HEAD)"
echo "Version $VERSION, build $BUILD"
LATEST_BUILD="$(curl -fsL "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null \
  | sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | head -1 || true)"
if [[ -n "$LATEST_BUILD" ]]; then
  echo "Latest release is build $LATEST_BUILD"
  (( BUILD > LATEST_BUILD )) || die "build $BUILD is not newer than $LATEST_BUILD; installed copies would ignore it (commit something first)"
fi

if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  SIGNING="developer-id"
  SIGN_SETTINGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application"
                 ENABLE_HARDENED_RUNTIME=YES "OTHER_CODE_SIGN_FLAGS=--timestamp")
else
  SIGNING="ad-hoc"
  SIGN_SETTINGS=("CODE_SIGN_IDENTITY=-")
fi
echo "Signing: $SIGNING"

# ── Build ────────────────────────────────────────────────────────────────────
step "Generating the Xcode project"
xcodegen generate --quiet

if [[ $SKIP_TESTS == 0 ]]; then
  step "Running tests"
  swift test --package-path Packages/MarkdownCore --quiet
  xcodebuild test -scheme "$SCHEME" -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$ROOT/.build/xcode" -quiet
fi

step "Building $APP_NAME $VERSION (Release)"
rm -rf "$DERIVED/Build/Products/Release/$APP_NAME.app"
xcodebuild build -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" -quiet \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  "${SIGN_SETTINGS[@]}"
APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || die "build produced no $APP_NAME.app"

PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]] || die "Info.plist version mismatch"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")" == "$BUILD" ]] || die "Info.plist build mismatch"
codesign --verify --strict "$APP" || die "code signature is invalid"
# Every @rpath library must resolve inside the bundle, or the app dies at launch.
LOAD_COMMANDS="$(otool -l "$APP/Contents/MacOS/$APP_NAME")"
[[ "$LOAD_COMMANDS" == *"@executable_path/../Frameworks"* ]] \
  || die "missing the Mac rpath @executable_path/../Frameworks"
for lib in $(otool -L "$APP/Contents/MacOS/$APP_NAME" | awk '/@rpath\//{print $1}'); do
  [[ -e "$APP/Contents/Frameworks/${lib#@rpath/}" ]] || die "embedded library missing: $lib"
done

# ── Notarize (Developer ID only) ─────────────────────────────────────────────
mkdir -p "$DIST"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
rm -f "$ZIP"
if [[ $SIGNING == "developer-id" ]]; then
  step "Notarizing"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi

step "Packaging"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# ── Release notes + appcast ──────────────────────────────────────────────────
step "Writing release notes and appcast"
NOTES="$DIST/$APP_NAME-$VERSION.md"
if [[ $DRY_RUN == 0 ]]; then
  gh api "repos/$REPO/releases/generate-notes" -f tag_name="$TAG" -f target_commitish=main \
    --jq .body > "$NOTES"
else
  echo "Dry run of $TAG." > "$NOTES"
fi
# One-item feed: the latest release is all Sparkle needs.
rm -f "$DIST/appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --embed-release-notes \
  "$DIST"
[[ -f "$DIST/appcast.xml" ]] || die "generate_appcast wrote no appcast.xml"
grep -q 'sparkle:edSignature' "$DIST/appcast.xml" || die "appcast has no EdDSA signature"

if [[ $DRY_RUN == 1 ]]; then
  step "Dry run done"
  echo "$ZIP"
  echo "$DIST/appcast.xml"
  exit 0
fi

# ── Publish ──────────────────────────────────────────────────────────────────
step "Tagging $TAG and publishing the GitHub Release"
git tag -a "$TAG" -m "$APP_NAME $VERSION"
git push origin "$TAG"

INSTALL_NOTE=""
if [[ $SIGNING == "ad-hoc" ]]; then
  INSTALL_NOTE=$'\n\n---\n**First install:** unzip, drag Skinny to Applications, then open it once via System Settings → Privacy & Security → Open Anyway (the app is not notarized). Later updates install from inside the app.'
fi
gh release create "$TAG" "$ZIP" "$DIST/appcast.xml" \
  --repo "$REPO" --verify-tag --latest \
  --title "$APP_NAME $VERSION" \
  --notes "$(cat "$NOTES")$INSTALL_NOTE"

step "Released $APP_NAME $VERSION"
echo "https://github.com/$REPO/releases/tag/$TAG"
