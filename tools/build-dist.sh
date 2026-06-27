#!/usr/bin/env bash
#
# build-dist.sh — Sorter 배포판(.app → .dmg + .zip) 빌드 스크립트
#
# 사용법:
#   tools/build-dist.sh            # Release 빌드 후 DMG/ZIP 생성
#   tools/build-dist.sh --app-only # 빌드만(.app 까지)
#   SKIP_BUILD=1 tools/build-dist.sh  # 기존 build 산출물 재사용(재빌드 생략)
#
# 산출물:
#   build/Build/Products/Release/Sorter.app
#   dist/Sorter-<version>.dmg   (앱 + /Applications 링크 + 설치안내 README)
#   dist/Sorter-<version>.zip   (ditto)
#
set -euo pipefail

SCHEME="Sorter"
CONFIG="Release"
# 스크립트 위치 기준으로 프로젝트 루트 결정 (어디서 실행해도 동작)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/$SCHEME.app"
README_SRC="$ROOT/dist-assets/설치안내-README.txt"

APP_ONLY=0
[[ "${1:-}" == "--app-only" ]] && APP_ONLY=1

# ── 1) Release 빌드 ──────────────────────────────────────────
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "▶︎ [1/4] Release 빌드..."
  xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" -destination 'platform=macOS' \
    build
else
  echo "▶︎ [1/4] SKIP_BUILD=1 — 빌드 생략, 기존 산출물 사용"
fi

[[ -d "$APP_PATH" ]] || { echo "✗ .app 을 찾을 수 없습니다: $APP_PATH" >&2; exit 1; }

# ── 2) 버전 추출 (Info.plist 의 CFBundleShortVersionString) ──
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP_PATH/Contents/Info.plist")"
echo "▶︎ [2/4] 버전: $VERSION"

if [[ "$APP_ONLY" == "1" ]]; then
  echo "✓ 빌드 완료 (--app-only): $APP_PATH"
  exit 0
fi

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$SCHEME-$VERSION.dmg"
ZIP_PATH="$DIST_DIR/$SCHEME-$VERSION.zip"

# ── 3) DMG 생성 (스테이징: 앱 + /Applications 링크 + README) ──
echo "▶︎ [3/4] DMG 생성: $DMG_PATH"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
# 코드서명 메타데이터 보존 위해 ditto 사용
ditto "$APP_PATH" "$STAGING/$SCHEME.app"
ln -s /Applications "$STAGING/Applications"
[[ -f "$README_SRC" ]] && cp "$README_SRC" "$STAGING/"

rm -f "$DMG_PATH"
hdiutil create -volname "$SCHEME $VERSION" \
  -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null

# ── 4) ZIP 생성 (Gatekeeper 메타데이터 보존) ─────────────────
echo "▶︎ [4/4] ZIP 생성: $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "✓ 완료"
echo "  DMG: $DMG_PATH"
echo "  ZIP: $ZIP_PATH"
