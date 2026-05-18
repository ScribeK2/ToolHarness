#!/usr/bin/env bash
# Builds ToolHarness as a Linux x86_64 AppImage.
# Designed to run inside an ubuntu:22.04 container (CI), but works
# locally on any Ubuntu 22.04+/Fedora 38+ host with the prereqs below.
#
# Prereqs (install once):
#   - build-essential, curl, git, pkg-config, rsync
#   - libssl-dev, libyaml-dev, libffi-dev, libsqlite3-dev (build-time linkage)
#   - patchelf (used by linuxdeploy)
#
# Spec: .internal/specs/2026-05-18-appimage-runtime-design.md

set -euo pipefail

VERSION="${VERSION:-$(cat VERSION)}"
ARCH="x86_64"
WORK="${WORK:-$(pwd)/build/appimage}"
APP_DIR="$WORK/AppDir"
RUBY_VERSION="3.4.7"
OUT="ToolHarness-${VERSION}-${ARCH}.AppImage"

echo "==> Building ToolHarness ${VERSION} for ${ARCH}"
rm -rf "$WORK"
mkdir -p "$APP_DIR/usr/bin" "$APP_DIR/usr/lib" "$APP_DIR/usr/share/toolharness" \
         "$APP_DIR/usr/share/applications" "$APP_DIR/usr/share/icons/hicolor/256x256/apps" \
         "$APP_DIR/usr/etc/ssl/certs"

# ---- Fetch linuxdeploy and appimagetool (portable AppImages, run extracted) ----
mkdir -p "$WORK/tools"
cd "$WORK/tools"

if [ ! -f linuxdeploy ]; then
  curl -L -o linuxdeploy https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
  chmod +x linuxdeploy
fi
if [ ! -f appimagetool ]; then
  curl -L -o appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x appimagetool
fi

LINUXDEPLOY="$WORK/tools/linuxdeploy --appimage-extract-and-run"
APPIMAGETOOL="$WORK/tools/appimagetool --appimage-extract-and-run"

# ---- Compile Ruby ----
if [ ! -x "$APP_DIR/usr/bin/ruby" ]; then
  echo "==> Compiling Ruby ${RUBY_VERSION}"
  cd "$WORK"
  if [ ! -d ruby-build ]; then
    git clone --depth=1 https://github.com/rbenv/ruby-build.git
  fi
  RUBY_CONFIGURE_OPTS="--enable-shared --disable-install-doc --disable-install-rdoc" \
  CFLAGS="-O2 -pipe" \
  LDFLAGS="-Wl,-rpath,\$\$ORIGIN/../lib" \
    PREFIX="$APP_DIR/usr" ./ruby-build/bin/ruby-build "$RUBY_VERSION" "$APP_DIR/usr"
fi

export PATH="$APP_DIR/usr/bin:$PATH"

# ---- Install bundled CA bundle ----
# Source from the host (the ca-certificates apt package is installed by the workflow's
# prereqs step, or by the local user before invoking this script). Mozilla's curated
# bundle, ~200 KB, refreshed automatically by the host distribution. Drop falls back to
# downloading from curl.se if the host file isn't present (covers non-Ubuntu dev hosts).
if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
  cp /etc/ssl/certs/ca-certificates.crt "$APP_DIR/usr/etc/ssl/certs/ca-certificates.crt"
elif [ -f /etc/pki/tls/certs/ca-bundle.crt ]; then
  cp /etc/pki/tls/certs/ca-bundle.crt "$APP_DIR/usr/etc/ssl/certs/ca-certificates.crt"
else
  curl -L -o "$APP_DIR/usr/etc/ssl/certs/ca-certificates.crt" https://curl.se/ca/cacert.pem
fi

# ---- Stage the Rails app ----
echo "==> Staging Rails app"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_STAGE="$APP_DIR/usr/share/toolharness"
rsync -a --delete \
  --exclude=".git" \
  --exclude="node_modules" \
  --exclude="log" \
  --exclude="storage" \
  --exclude="tmp" \
  --exclude="test" \
  --exclude="build" \
  --exclude=".internal" \
  "$REPO_ROOT/" "$APP_STAGE/"

# Write VERSION inside the AppDir
echo "$VERSION" > "$APP_STAGE/VERSION"

# ---- Bundle install into the AppDir ----
echo "==> bundle install"
cd "$APP_STAGE"
export BUNDLE_PATH="$APP_DIR/usr/lib/ruby/bundle"
export BUNDLE_DEPLOYMENT=1
export BUNDLE_WITHOUT="development:test"
gem install bundler --no-document
bundle config set --local path "$APP_DIR/usr/lib/ruby/bundle"
bundle config set --local deployment 'true'
bundle config set --local without 'development test'
bundle install --jobs 4

# ---- Precompile assets ----
echo "==> assets:precompile"
RAILS_ENV=production SECRET_KEY_BASE=dummy bundle exec rails assets:precompile

# ---- Place desktop file and icon ----
sed "s/X-AppImage-Version=.*/X-AppImage-Version=${VERSION}/" \
  "$REPO_ROOT/script/toolharness.desktop" > "$APP_DIR/toolharness.desktop"
cp "$APP_DIR/toolharness.desktop" "$APP_DIR/usr/share/applications/toolharness.desktop"
cp "$REPO_ROOT/script/toolharness.png" "$APP_DIR/toolharness.png"
cp "$REPO_ROOT/script/toolharness.png" "$APP_DIR/usr/share/icons/hicolor/256x256/apps/toolharness.png"
ln -sf toolharness.png "$APP_DIR/.DirIcon"

# ---- Install AppRun ----
cp "$REPO_ROOT/script/AppRun.tmpl" "$APP_DIR/AppRun"
chmod +x "$APP_DIR/AppRun"

# ---- Walk ELF deps with linuxdeploy ----
echo "==> linuxdeploy (walking native deps)"
NATIVE_EXTS=$(find "$APP_DIR/usr/lib/ruby/bundle" -name "*.so" -type f)
EXEC_ARGS="--executable $APP_DIR/usr/bin/ruby"
for so in $NATIVE_EXTS; do
  EXEC_ARGS="$EXEC_ARGS --executable $so"
done

# shellcheck disable=SC2086
$LINUXDEPLOY \
  --appdir "$APP_DIR" \
  --desktop-file "$APP_DIR/toolharness.desktop" \
  --icon-file "$APP_DIR/toolharness.png" \
  $EXEC_ARGS

# ---- Pack ----
echo "==> appimagetool"
cd "$WORK"
ARCH=x86_64 $APPIMAGETOOL "$APP_DIR" "$REPO_ROOT/$OUT"

echo "==> Wrote $REPO_ROOT/$OUT"
ls -lh "$REPO_ROOT/$OUT"
