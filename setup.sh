#!/usr/bin/env bash
# Installs jpm for a GitHub Actions job: downloads the release binary for this runner, checks it against
# the release's SHA256SUMS, puts jpm and jvm on PATH, and reports the version and paths as outputs.
set -euo pipefail

repo="${JPM_REPO:-java-package-manager/jpm}"
version="${INPUT_VERSION:-}"
if [ -z "$version" ]; then
  # the version the project pins ("jpm" in the root project.jsonc), which jpm would otherwise install on first use
  manifest="${GITHUB_WORKSPACE:-.}/project.jsonc"
  if [ -f "$manifest" ]; then
    version="$(grep -oE '"jpm"[[:space:]]*:[[:space:]]*"[^"]+"' "$manifest" | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/' || true)"
    [ -n "$version" ] && echo "project.jsonc pins jpm $version"
  fi
fi
version="${version:-latest}"
version="${version#v}"

case "${RUNNER_OS:-$(uname -s)}" in
  Linux) os=linux ;;
  macOS | Darwin) os=macos ;;
  Windows | MINGW* | MSYS* | CYGWIN*) os=windows ;;
  *) echo "::error::setup-jpm does not support the runner OS ${RUNNER_OS:-$(uname -s)}"; exit 1 ;;
esac
case "${RUNNER_ARCH:-$(uname -m)}" in
  X64 | x86_64 | amd64) arch=x64 ;;
  ARM64 | arm64 | aarch64) arch=arm64 ;;
  *) echo "::error::setup-jpm does not support the runner architecture ${RUNNER_ARCH:-$(uname -m)}"; exit 1 ;;
esac
if [ "$os" = windows ] && [ "$arch" != x64 ]; then
  echo "::error::jpm has no Windows $arch build; use an x64 Windows runner"
  exit 1
fi
exe=""
[ "$os" = windows ] && exe=".exe"
asset="jpm-$os-$arch$exe"

get() { curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors "$@"; }

if [ -n "${JPM_INSTALL_BASE:-}" ]; then
  base="${JPM_INSTALL_BASE%/}"
elif [ "$version" = latest ]; then
  base="https://github.com/$repo/releases/latest/download"
elif [ "$version" = canary ]; then
  # the release tagged canary names jpm's newest release or prerelease in VERSION
  canary="$(get "https://github.com/$repo/releases/download/canary/VERSION" | tr -d '[:space:]')"
  [ -n "$canary" ] || { echo "::error::could not find jpm's newest prerelease"; exit 1; }
  base="https://github.com/$repo/releases/download/$canary"
else
  base="https://github.com/$repo/releases/download/$version"
fi

home="${JPM_HOME:-$HOME/.jpm}"
if [ "$os" = windows ] && command -v cygpath >/dev/null; then home="$(cygpath -u "$home")"; fi
bin="$home/bin"
mkdir -p "$bin"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $asset from $base"
if ! get -o "$tmp/$asset" "$base/$asset"; then
  echo "::error::could not download $base/$asset; is $version a jpm release?"
  exit 1
fi
get -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"
expected="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' "$tmp/SHA256SUMS")"
if command -v sha256sum >/dev/null; then actual="$(sha256sum "$tmp/$asset" | awk '{ print $1 }')"
else actual="$(shasum -a 256 "$tmp/$asset" | awk '{ print $1 }')"; fi
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
  echo "::error::checksum mismatch for $asset (expected ${expected:-none}, got $actual)"
  exit 1
fi

install -m 755 "$tmp/$asset" "$bin/jpm$exe"
# jvm is the same binary under another name
if [ "$os" = windows ]; then cp "$bin/jpm$exe" "$bin/jvm$exe"; else ln -sf "jpm" "$bin/jvm"; fi

native_bin="$bin"
if [ "$os" = windows ] && command -v cygpath >/dev/null; then native_bin="$(cygpath -w "$bin")"; fi
echo "$native_bin" >> "$GITHUB_PATH"
{
  # the runner's PATH is set up already; do not ask GitHub for newer versions on every jpm --version
  echo "JPM_NO_UPDATE_CHECK=1"
  [ -n "${JPM_HOME:-}" ] || echo "JPM_HOME=$( [ "$os" = windows ] && command -v cygpath >/dev/null && cygpath -w "$home" || echo "$home")"
} >> "$GITHUB_ENV"

installed="$("$bin/jpm$exe" --version 2>/dev/null | head -n 1 | awk '{ print $2 }')"
[ -n "$installed" ] || { echo "::error::the downloaded jpm does not run"; exit 1; }

if [ "${INPUT_SHIMS:-false}" = true ]; then
  JPM_HOME="$home" "$bin/jpm$exe" jvm setup >/dev/null
fi

home_out="$home"
if [ "$os" = windows ] && command -v cygpath >/dev/null; then home_out="$(cygpath -w "$home")"; fi
{
  echo "version=$installed"
  echo "path=$( [ "$os" = windows ] && command -v cygpath >/dev/null && cygpath -w "$bin/jpm$exe" || echo "$bin/jpm$exe")"
  echo "home=$home_out"
} >> "$GITHUB_OUTPUT"
echo "Installed jpm $installed in $bin"
