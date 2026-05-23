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

# Resolve REPO_ROOT once, before any cd, using BASH_SOURCE to handle relative invocations.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-$(cat "$REPO_ROOT/VERSION")}"
ARCH="x86_64"
WORK="${WORK:-$REPO_ROOT/build/appimage}"
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
  RUBY_CONFIGURE_OPTS="--enable-shared --enable-load-relative --disable-install-doc --disable-install-rdoc" \
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
# Ruby 3.4 ships with bundler as a default gem — no `gem install bundler` needed.
bundle config set --local path "$APP_DIR/usr/lib/ruby/bundle"
bundle config set --local deployment 'true'
bundle config set --local without 'development test'
bundle install --jobs 4

# Drop .bundle/config — it baked in the build-time absolute path under
# BUNDLE_PATH, and modern bundler treats local config as higher precedence
# than the BUNDLE_PATH env var AppRun exports at runtime. Without this,
# bundler at runtime looks in /home/runner/.../bundle (nonexistent) and
# falls back to "locally installed gems" mode → all gems "missing".
rm -rf "$APP_STAGE/.bundle"

# ---- Precompile assets ----
echo "==> assets:precompile"
RAILS_ENV=production SECRET_KEY_BASE=dummy bundle exec rails assets:precompile

# ---- Rewrite absolute-path shebangs to relocatable form ----
# ruby-build/rubygems write wrapper scripts (bundle, gem, rake, plus any gem-provided
# binaries) with a shebang hardcoded to the build-time absolute path:
#   #!/home/runner/.../AppDir/usr/bin/ruby
# That path won't exist on a user's machine after AppImage extraction, so any direct
# exec of those wrappers fails with "bad interpreter". Rewrite to /usr/bin/env ruby
# so they pick up Ruby from PATH (AppRun puts $HERE/usr/bin first).
#
# MUST run AFTER bundle install — gem install bundler and bundle install both write
# scripts that would otherwise re-introduce the bad shebang.
echo "==> Rewriting build-path shebangs to /usr/bin/env ruby"
shebang_dirs=("$APP_DIR/usr/bin")
for gembin in "$APP_DIR/usr/lib/ruby/bundle/ruby/"*/bin; do
  [ -d "$gembin" ] && shebang_dirs+=("$gembin")
done
fixed_count=0
for dir in "${shebang_dirs[@]}"; do
  for script in "$dir"/*; do
    [ -f "$script" ] || continue
    first_line=$(head -c 200 "$script" 2>/dev/null | head -n1 || true)
    case "$first_line" in
      "#!"*"/ruby"|"#!"*"/ruby "*)
        sed -i '1c\#!/usr/bin/env ruby' "$script"
        fixed_count=$((fixed_count + 1))
        ;;
    esac
  done
done
echo "==> Rewrote $fixed_count shebangs across ${#shebang_dirs[@]} bin dirs"

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
# Walk the entire ruby tree so that BOTH Ruby's built-in extensions
# (usr/lib/ruby/3.4.0/x86_64-linux/openssl.so, etc.) AND gem-installed native
# extensions (usr/lib/ruby/bundle/ruby/3.4.0/gems/.../...so) get their rpaths set.
# Missing this caused Fedora to load /usr/lib64/libssl.so.3 (which lacks
# EC_GROUP_new_curve_GF2m) instead of our bundled libssl.
echo "==> linuxdeploy (walking native deps)"
NATIVE_EXTS=$(find "$APP_DIR/usr/lib/ruby" -name "*.so" -type f)
EXEC_ARGS="--executable $APP_DIR/usr/bin/ruby"
for so in $NATIVE_EXTS; do
  EXEC_ARGS="$EXEC_ARGS --executable $so"
done

# LD_LIBRARY_PATH tells linuxdeploy's internal ldd lookup to also consider the
# in-AppDir libraries we just compiled — notably libruby.so.3.4 from --enable-shared.
# Without this, linuxdeploy fails with "Could not find dependency: libruby.so.3.4".
# shellcheck disable=SC2086
LD_LIBRARY_PATH="$APP_DIR/usr/lib:${LD_LIBRARY_PATH:-}" $LINUXDEPLOY \
  --appdir "$APP_DIR" \
  --desktop-file "$APP_DIR/toolharness.desktop" \
  --icon-file "$APP_DIR/toolharness.png" \
  $EXEC_ARGS

# ---- Sanity-check: confirm mysql2's libmariadb shipped and resolves ----
MYSQL2_SO=$(find "$APP_DIR/usr/lib/ruby" -name 'mysql2.so' | head -1)
if [ -n "$MYSQL2_SO" ]; then
  echo "[smoke] checking mysql2.so linkage…"
  ldd "$MYSQL2_SO" | tee /tmp/ldd-mysql2.txt
  if grep -q 'not found' /tmp/ldd-mysql2.txt; then
    echo "ERROR: mysql2.so has unresolved shared library deps — build is broken"
    exit 1
  fi
else
  echo "WARN: no mysql2.so found in $APP_DIR/usr/lib/ruby — mysql2 gem not installed?"
  exit 1
fi

# ---- Pack ----
echo "==> appimagetool"
cd "$WORK"
ARCH=x86_64 $APPIMAGETOOL "$APP_DIR" "$REPO_ROOT/$OUT"

echo "==> Wrote $REPO_ROOT/$OUT"
ls -lh "$REPO_ROOT/$OUT"
