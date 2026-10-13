#!/usr/bin/env bash
# Start the open.mp launcher (Wine build) in the SA-MP prefix, through umu-run.
# install.sh writes the config this reads; every setting can also come from the
# environment.
#
#   omp-launcher.sh             start it
#   omp-launcher.sh --dry-run   print what it would run
#
# Settings (config file or environment):
#   PREFIX        the Wine prefix (the folder holding drive_c)
#   PROTONPATH    the Proton umu-run uses (default: umu's GE-Proton)
#   GAMEID        umu game id. Proton names the window class steam_app_<id
#                 after "umu-">, which the desktop entry's StartupWMClass must
#                 match; umu only takes ids matching umu-[A-Za-z0-9_]+ (a dash
#                 after the prefix gives steam_app_0)
#   VARIANT       wine (omp-launcher-wine) or sampcmd (omp-launcher-wine-sampcmd)
#   VIRTUAL_DESKTOP=1   run inside a Wine virtual desktop instead (Proton opens
#                 it full screen; games started from the launcher open in it too)
#
# What the environment below is for (all of it is in docs/LAUNCHER.md):
#   OMP_WEBVIEW2_ARGS  extra Chromium flags; the Wine build appends them (WebView2's
#                 own WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS is ignored there).
#                 --disable-gpu: software rendering, frames at monitor rate and
#                 every keystroke painted within 16 ms (GPU through DXVK: 60 fps,
#                 40 ms worst). Set it empty to use the GPU.
#   PROTON_USE_XALIA=0 Proton's accessibility helper reads the window through UI
#                 Automation, which switches Chromium's accessibility mode on and
#                 slows it down.
#   WINEDLLOVERRIDES=d3d9=n,b  for games started from the launcher: a DXVK
#                 d3d9.dll in the game folder first, Wine's own otherwise.
#   OMP_SAMPCMD / OMP_SAMPCMD_ARGS  (sampcmd variant) start games through
#                 sampcmd.exe in the game folder with these options.
#
# Stopping it: its processes run inside pressure-vessel, so kill from the host
# does nothing. `omp-launcher.sh --stop` asks Wine's taskkill instead; never
# wineserver -k a prefix with a game running in it.
set -euo pipefail

CONF="${OMP_LAUNCHER_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/samp-openmp-linux/omp-launcher.conf}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

: "${PREFIX:?PREFIX is not set (run install.sh, or set it in $CONF)}"
GAMEID="${GAMEID:-umu-omplauncher}"
VARIANT="${VARIANT:-wine}"
VIRTUAL_DESKTOP="${VIRTUAL_DESKTOP:-0}"
LAUNCHER_DIR="$PREFIX/drive_c/Program Files (x86)/Open Multiplayer Launcher"
LAUNCHER_EXE="$LAUNCHER_DIR/omp-launcher.exe"

export OMP_WEBVIEW2_ARGS="${OMP_WEBVIEW2_ARGS---disable-gpu}"
if [ "$VARIANT" = sampcmd ]; then
    export OMP_SAMPCMD="${OMP_SAMPCMD-sampcmd.exe}"
    export OMP_SAMPCMD_ARGS="${OMP_SAMPCMD_ARGS---monitor --verbose --full-dump}"
fi

umu_env=(GAMEID="$GAMEID" STORE=none WINEPREFIX="$PREFIX")
[ -n "${PROTONPATH:-}" ] && umu_env+=(PROTONPATH="$PROTONPATH")

if [ "${1:-}" = --stop ]; then
    exec env "${umu_env[@]}" PROTON_VERB=run umu-run "$PREFIX/drive_c/windows/system32/taskkill.exe" /f /im omp-launcher.exe
fi

[ -f "$LAUNCHER_EXE" ] || { echo "no launcher at $LAUNCHER_EXE (run install.sh)" >&2; exit 1; }
if [ "$VIRTUAL_DESKTOP" = 1 ]; then
    run=("$PREFIX/drive_c/windows/explorer.exe" "/desktop=omp-launcher" "$LAUNCHER_EXE")
else
    run=("$LAUNCHER_EXE")
fi

cmd=(env WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d9=n,b}" PROTON_USE_XALIA=0 MANGOHUD="${MANGOHUD:-0}"
     "${umu_env[@]}" umu-run "${run[@]}")
if [ "${1:-}" = --dry-run ]; then
    printf '%q ' cd "$LAUNCHER_DIR"; echo '&&'; printf '%q ' "${cmd[@]}"; echo
    exit 0
fi
cd "$LAUNCHER_DIR"
exec "${cmd[@]}"
