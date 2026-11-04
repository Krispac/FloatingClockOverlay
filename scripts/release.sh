#!/bin/bash
# Build and publish a GitHub release for both apps. Users are NOT offered it until
# you run scripts/rollout.sh <version>.
#   scripts/release.sh 1.4.1 "Short notes shown in the update pop-up"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [notes]}"
NOTES="${2:-Bug fixes and improvements.}"
TAG="v$VERSION"
APP=FloatingClockOverlay
SIGN_ID="FloatingClockOverlay Local Signing"
OUT="build/release-$VERSION"

security find-identity -p codesigning | grep -q "$SIGN_ID" || { echo "Missing signing certificate: $SIGN_ID"; exit 1; }
[ -z "$(git status --porcelain -- FloatingClockOverlay FloatingClockOverlay-Windows)" ] || { echo "Commit your app changes first."; exit 1; }

echo "→ Setting version $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" $APP/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION//./}" $APP/Info.plist
sed -i '' "s#<Version>.*</Version>#<Version>$VERSION</Version>#" $APP-Windows/$APP/$APP.csproj
git add $APP/Info.plist $APP-Windows/$APP/$APP.csproj
git diff --cached --quiet || git commit -m "Release $TAG" >/dev/null
git push -q origin HEAD
COMMIT=$(git rev-parse HEAD)

echo "→ Building macOS app"
rm -rf "$OUT" && mkdir -p "$OUT/dmg"
xcodebuild archive -project $APP.xcodeproj -scheme $APP -configuration Release -archivePath "$OUT/$APP.xcarchive" -quiet
ditto "$OUT/$APP.xcarchive/Products/Applications/$APP.app" "$OUT/dmg/$APP.app"
codesign --force --deep --preserve-metadata=entitlements,flags,identifier --sign "$SIGN_ID" "$OUT/dmg/$APP.app"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname $APP -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/$APP.dmg" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$OUT/dmg/$APP.app" "$OUT/$APP-macOS.zip"

echo "→ Waiting for the Windows build of $COMMIT"
# A push only triggers the Windows build when Windows files changed; start one otherwise.
find_run() { gh run list --workflow windows-build.yml --commit "$COMMIT" --json databaseId -q '.[0].databaseId' || true; }
RUN=""
for i in $(seq 1 30); do
  RUN=$(find_run)
  [ -n "$RUN" ] && break
  [ "$i" = 3 ] && gh workflow run windows-build.yml --ref "$(git rev-parse --abbrev-ref HEAD)"
  sleep 10
done
[ -n "$RUN" ] || { echo "Windows build did not start"; exit 1; }
gh run watch "$RUN" --exit-status >/dev/null
gh run download "$RUN" -n $APP-Windows -D "$OUT/win"

echo "→ Publishing $TAG"
(cd "$OUT/win" && zip -q "../$APP-Windows.zip" "$APP.exe")
gh release create "$TAG" "$OUT/$APP.dmg" "$OUT/$APP-macOS.zip" "$OUT/win/$APP.exe" "$OUT/$APP-Windows.zip" \
  --title "$TAG" --notes "$NOTES"
echo "$NOTES" > "$OUT/notes.txt"

echo
echo "✓ Released $TAG on GitHub. Users are not offered it yet."
echo "  Try it yourself, then run: scripts/rollout.sh $VERSION"
