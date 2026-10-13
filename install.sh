#!/usr/bin/env bash
# install.sh - the open.mp launcher, with its in-game server browser, for
# SA-MP under Proton (umu-run). Idempotent: run it again to update.
#
#   ./install.sh --prefix ~/Games/samp/pfx --game ~/Games/gta-sa
#
# Options:
#   --prefix DIR    the Wine prefix SA-MP plays in (the folder holding drive_c)   [required]
#   --game DIR      the GTA San Andreas folder (gta_sa.exe 1.0 US, samp.dll)       [required]
#   --proton DIR    PROTONPATH for umu-run (default: umu's own GE-Proton)
#   --variant V     wine (default) or sampcmd: start games through sampcmd.exe,
#                   which must then be in the game folder (or in --from)
#   --name NAME     SA-MP player name, if none is set yet
#   --gameid ID     umu game id (default umu-omplauncher; see bin/omp-launcher.sh)
#   --from DIR      take files from DIR instead of downloading them:
#                   MicrosoftEdgeWebView2RuntimeInstallerX64.exe, omp-launcher.exe,
#                   WebView2Loader.dll, omp-client.dll, ompoverlay.asi,
#                   animwipefix.asi, sampcmd.exe (any that are missing are downloaded)
#   --no-asi        leave the game folder alone (no ompoverlay.asi / animwipefix.asi)
#   --no-desktop    no launch script in ~/.local/bin, no desktop entry
#   --dry-run       say what would be done, change nothing
#
# Everything it does, and why, is in README.md and docs/.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LAUNCHER_REPO_WINE=akacross/omp-launcher-wine
LAUNCHER_REPO_SAMPCMD=akacross/omp-launcher-wine-sampcmd
ASI_REPO=akacross/omp-ingame-browser-wine
WEBVIEW2_URL="https://go.microsoft.com/fwlink/p/?LinkId=2124701"   # offline standalone installer
OMP_API="https://api.open.mp/launcher"
BUILD_VERSION=6        # this launcher build's entry in the API (src/constants/app.ts)

PREFIX="" GAME="" PROTON="" VARIANT=wine NAME="" GAMEID=umu-omplauncher FROM=""
NO_ASI=0 NO_DESKTOP=0 DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="${2%/}"; shift ;;
        --game) GAME="${2%/}"; shift ;;
        --proton) PROTON="${2%/}"; shift ;;
        --variant) VARIANT="$2"; shift ;;
        --name) NAME="$2"; shift ;;
        --gameid) GAMEID="$2"; shift ;;
        --from) FROM="${2%/}"; shift ;;
        --no-asi) NO_ASI=1 ;;
        --no-desktop) NO_DESKTOP=1 ;;
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
act() { if [ "$DRY" = 1 ]; then note "would: $*"; else "$@"; fi }

[ -n "$PREFIX" ] && [ -n "$GAME" ] || die "--prefix and --game are required (see --help)"
case "$VARIANT" in wine|sampcmd) ;; *) die "--variant is wine or sampcmd" ;; esac
[[ "$GAMEID" =~ ^umu-[A-Za-z0-9_]+$ ]] || die "--gameid must match umu-[A-Za-z0-9_]+ (umu ignores anything else)"
for c in umu-run curl python3 sha256sum md5sum; do command -v "$c" >/dev/null || die "$c is not installed"; done
[ -d "$PREFIX/drive_c" ] || die "$PREFIX is not a Wine prefix (no drive_c)"
[ -f "$GAME/gta_sa.exe" ] || die "no gta_sa.exe in $GAME"
[ -f "$GAME/samp.dll" ] || die "no samp.dll in $GAME: install SA-MP 0.3.7 first"
if [ "$VARIANT" = sampcmd ] && [ ! -f "$GAME/sampcmd.exe" ] && { [ -z "$FROM" ] || [ ! -f "$FROM/sampcmd.exe" ]; }; then
    die "the sampcmd variant needs sampcmd.exe in $GAME (or in --from): https://gitlab.com/akacross/sampcmd/-/releases"
fi

if [ -d "$PREFIX/drive_c/users/steamuser" ]; then USERDIR="$PREFIX/drive_c/users/steamuser"
else USERDIR="$(find "$PREFIX/drive_c/users" -mindepth 1 -maxdepth 1 -type d ! -name Public | head -1)"; fi
[ -n "$USERDIR" ] || die "no user folder in $PREFIX/drive_c/users"
LAUNCHER_DIR="$PREFIX/drive_c/Program Files (x86)/Open Multiplayer Launcher"
PLUGIN="$USERDIR/AppData/Local/mp.open.launcher/omp/omp-client.dll"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/samp-openmp-linux"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/samp-openmp-linux"
mkdir -p "$CACHE"

if pgrep -f '^C:.*omp-launcher\.exe' >/dev/null; then
    note "an omp-launcher.exe is running (this prefix's or another's): restart it to use the new one"
fi

# Run a Windows program in the prefix without waiting for the prefix to go idle.
wine_run() {
    local env=(GAMEID="$GAMEID" STORE=none WINEPREFIX="$PREFIX" PROTON_VERB=run PROTON_USE_XALIA=0)
    [ -n "$PROTON" ] && env+=(PROTONPATH="$PROTON")
    env "${env[@]}" umu-run "$@"
}

# get NAME URL: the path of NAME, from --from or downloaded into the cache
get() {
    local name="$1" url="$2"
    if [ -n "$FROM" ] && [ -f "$FROM/$name" ]; then echo "$FROM/$name"; return; fi
    if [ "$DRY" = 1 ]; then echo "$CACHE/$name"; return; fi
    note "downloading $name" >&2
    curl -fL --retry 3 --progress-bar -o "$CACHE/$name.part" "$url" >&2
    mv "$CACHE/$name.part" "$CACHE/$name"
    echo "$CACHE/$name"
}

# check FILE against a SHA256SUMS file (skipped for --from files without one)
check_sha() {
    local file="$1" sums="$2" want got
    [ "$DRY" = 1 ] && return 0
    want="$(awk -v n="$(basename "$file")" '$2 == n {print $1}' "$sums")"
    [ -n "$want" ] || die "$(basename "$file") is not in $sums"
    got="$(sha256sum "$file" | cut -d' ' -f1)"
    [ "$want" = "$got" ] || die "$(basename "$file"): sha256 $got, expected $want"
}

# install SRC DEST: copy through a temporary name, so a running program keeps its file
install_file() {
    act mkdir -p "$(dirname "$2")"
    act cp "$1" "$2.new"
    act mv -f "$2.new" "$2"
}

# ---------------------------------------------------------------------------
step "1/7  WebView2 runtime"
if find "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application" -name msedgewebview2.exe \
        -print -quit 2>/dev/null | grep -q .; then
    note "already installed"
else
    # the offline standalone installer; the online bootstrapper half-installs under Wine
    installer="$(get MicrosoftEdgeWebView2RuntimeInstallerX64.exe "$WEBVIEW2_URL")"
    act wine_run "$installer" /silent /install || true
    if [ "$DRY" = 0 ] && ! find "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application" \
            -name msedgewebview2.exe -print -quit 2>/dev/null | grep -q .; then
        die "WebView2 did not install (run the installer by hand: umu-run $installer)"
    fi
fi

# ---------------------------------------------------------------------------
step "2/7  open.mp launcher ($VARIANT)"
repo="$LAUNCHER_REPO_WINE"; [ "$VARIANT" = sampcmd ] && repo="$LAUNCHER_REPO_SAMPCMD"
release="https://github.com/$repo/releases/latest/download"
exe="$(get omp-launcher.exe "$release/omp-launcher.exe")"
loader="$(get WebView2Loader.dll "$release/WebView2Loader.dll")"
if [ -z "$FROM" ] || [ ! -f "$FROM/omp-launcher.exe" ]; then
    sums="$(get SHA256SUMS "$release/SHA256SUMS")"
    check_sha "$exe" "$sums"; check_sha "$loader" "$sums"
fi
install_file "$exe" "$LAUNCHER_DIR/omp-launcher.exe"
install_file "$loader" "$LAUNCHER_DIR/WebView2Loader.dll"
note "into $LAUNCHER_DIR"

# ---------------------------------------------------------------------------
step "3/7  open.mp client plugin (omp-client.dll)"
# The launcher downloads this itself, but under Wine that download stalls ~24 KB
# short every time; a plugin already in place with the right MD5 is kept.
if [ -n "$FROM" ] && [ -f "$FROM/omp-client.dll" ]; then
    install_file "$FROM/omp-client.dll" "$PLUGIN"; note "from $FROM"
elif [ "$DRY" = 1 ]; then
    note "would fetch $OMP_API, download versions[\"$BUILD_VERSION\"].ompPluginDownload and check its MD5"
else
    read -r url md5 < <(curl -fsSL "$OMP_API" | python3 -c '
import json, sys
d = json.load(sys.stdin); v = d.get("versions", {}).get(sys.argv[1]) or d
print(v["ompPluginDownload"], v["ompPluginChecksum"])' "$BUILD_VERSION")
    if [ -f "$PLUGIN" ] && [ "$(md5sum "$PLUGIN" | cut -d' ' -f1)" = "$md5" ]; then
        note "up to date ($md5)"
    else
        curl -fL --retry 3 --progress-bar -o "$CACHE/omp-client.dll" "$url"
        [ "$(md5sum "$CACHE/omp-client.dll" | cut -d' ' -f1)" = "$md5" ] || die "omp-client.dll: MD5 mismatch"
        install_file "$CACHE/omp-client.dll" "$PLUGIN"; note "$url ($md5)"
    fi
fi

# ---------------------------------------------------------------------------
step "4/7  game folder in the registry"
# The launcher reads the game from SA-MP's own key, HKCU\Software\SAMP.
win_path() {   # a Linux path as Wine sees it: C: inside the prefix, Z: (the root) otherwise
    case "$1" in
        "$PREFIX/drive_c/"*) printf 'C:\\%s' "${1#"$PREFIX/drive_c/"}" | tr '/' '\\' ;;
        *) printf 'Z:%s' "$1" | tr '/' '\\' ;;
    esac
}
reg_value() {  # reg_value NAME: the value in user.reg's [Software\\SAMP], or nothing
    python3 - "$PREFIX/user.reg" "$1" <<'EOF'
import sys, re
try: text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
except OSError: sys.exit()
m = re.search(r'^\[Software\\\\SAMP\][^\n]*\n(.*?)(?:\n\n|\Z)', text, re.S | re.M)
if m:
    v = re.search(r'^"%s"="(.*)"$' % re.escape(sys.argv[2]), m.group(1), re.M)
    if v: print(v.group(1).replace('\\\\', '\\'))
EOF
}
current="$(reg_value gta_sa_exe)"
want="$(win_path "$GAME/gta_sa.exe")"
if [ -n "$current" ]; then
    note "gta_sa_exe = $current"
    [ "$current" = "$want" ] || note "(the launcher will use that; change it in its settings, or delete the value and run this again)"
else
    act wine_run "$PREFIX/drive_c/windows/system32/reg.exe" add 'HKCU\Software\SAMP' /v gta_sa_exe /t REG_SZ /d "$want" /f >/dev/null 2>&1; note "gta_sa_exe = $want"
fi
if [ -n "$NAME" ] && [ -z "$(reg_value PlayerName)" ]; then
    act wine_run "$PREFIX/drive_c/windows/system32/reg.exe" add 'HKCU\Software\SAMP' /v PlayerName /t REG_SZ /d "$NAME" /f >/dev/null 2>&1; note "PlayerName = $NAME"
fi

# ---------------------------------------------------------------------------
step "5/7  game plugins: ompoverlay.asi (in-game browser), animwipefix.asi (reconnect crash)"
if [ "$NO_ASI" = 1 ]; then
    note "skipped (--no-asi)"
else
    rel="https://github.com/$ASI_REPO/releases/latest/download"
    o="$(get ompoverlay.asi "$rel/ompoverlay.asi")"; a="$(get animwipefix.asi "$rel/animwipefix.asi")"
    if [ -z "$FROM" ] || [ ! -f "$FROM/ompoverlay.asi" ]; then
        sums="$(get ASI-SHA256SUMS "$rel/SHA256SUMS")"; check_sha "$o" "$sums"; check_sha "$a" "$sums"
    fi
    install_file "$o" "$GAME/ompoverlay.asi"; install_file "$a" "$GAME/animwipefix.asi"
    note "into $GAME (any ASI loader: SA-MP's, CLEO's or Silent's)"
fi
if [ "$VARIANT" = sampcmd ] && [ ! -f "$GAME/sampcmd.exe" ]; then
    install_file "$FROM/sampcmd.exe" "$GAME/sampcmd.exe"   # checked at the start
fi

# ---------------------------------------------------------------------------
step "6/7  launch script and its config"
conf="$CONF_DIR/omp-launcher.conf"
if [ "$DRY" = 1 ]; then
    note "would write $conf and ~/.local/bin/omp-launcher"
else
    mkdir -p "$CONF_DIR"
    {
        echo "# written by samp-openmp-linux/install.sh; read by omp-launcher"
        printf 'PREFIX=%q\n' "$PREFIX"
        printf 'GAME=%q\n' "$GAME"
        [ -n "$PROTON" ] && printf 'PROTONPATH=%q\n' "$PROTON"
        printf 'GAMEID=%q\n' "$GAMEID"
        printf 'VARIANT=%q\n' "$VARIANT"
    } > "$conf"
    note "$conf"
    if [ "$NO_DESKTOP" = 0 ]; then
        mkdir -p "$HOME/.local/bin"
        install -m 755 "$here/bin/omp-launcher.sh" "$HOME/.local/bin/omp-launcher"
        note "~/.local/bin/omp-launcher"
    fi
fi

# ---------------------------------------------------------------------------
step "7/7  desktop entry"
if [ "$NO_DESKTOP" = 1 ]; then
    note "skipped (--no-desktop)"
elif [ "$DRY" = 1 ]; then
    note "would extract the launcher's icons and write ~/.local/share/applications/omp-launcher.desktop"
else
    # the icon comes from the installed exe, so this repository carries none of
    # open.mp's artwork
    python3 "$here/bin/extract-icons.py" "$LAUNCHER_DIR/omp-launcher.exe" \
        "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" omp-launcher >/dev/null
    apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    mkdir -p "$apps"
    cat > "$apps/omp-launcher.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=open.mp launcher
Comment=SA-MP and open.mp server browser (Wine/Proton)
Exec=$HOME/.local/bin/omp-launcher
Icon=omp-launcher
Terminal=false
Categories=Game;
StartupWMClass=steam_app_${GAMEID#umu-}
EOF
    command -v update-desktop-database >/dev/null && update-desktop-database "$apps" >/dev/null 2>&1 || true
    note "$apps/omp-launcher.desktop (StartupWMClass steam_app_${GAMEID#umu-})"
fi

step "done"
note "start it from the menu or with ~/.local/bin/omp-launcher, then start games from it"
note "(the in-game browser needs the game and the launcher in one wineserver)"
