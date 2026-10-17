# SA-MP + open.mp launcher on Linux (Proton / umu)

Running the [open.mp launcher](https://github.com/openmultiplayer/launcher) on
Linux under Proton, next to an existing SA-MP install. That means the server
browser, starting games from it, and open.mp's **in-game** server browser.
This is the setup ([`install.sh`](install.sh), [`bin/omp-launcher.sh`](bin/omp-launcher.sh))
and the findings: what broke under Wine, what the cause actually was, and
where I was wrong on the way.

**Result:**
- the launcher runs as a normal window: no crash, no lag, with the right
  cursor and taskbar icon;
- games start from it, optionally through
  [sampcmd](https://gitlab.com/akacross/sampcmd);
- the in-game browser works in game: pictures, input, reopening, connecting,
  with no tab-out.

| piece | repository |
|---|---|
| the launcher, Wine compatibility pass | [omp-launcher-wine](https://github.com/akacross/omp-launcher-wine) (fork of openmultiplayer/launcher) |
| the same, starting games through sampcmd | [omp-launcher-wine-sampcmd](https://github.com/akacross/omp-launcher-wine-sampcmd) |
| the reconnect crash fix, and the in-game browser's game side (built into the launcher since 1.7.0-wine.1) | [omp-ingame-browser-wine](https://github.com/akacross/omp-ingame-browser-wine) |
| a D3D9 watchdog for an open DXVK crash | [d3d9watch](https://github.com/akacross/d3d9watch) |
| this setup and the findings | here |

---

## Test machine

| | |
|---|---|
| OS | CachyOS (Arch), KDE Plasma on Wayland (Xwayland for Wine) |
| GPU | RTX 3070, NVIDIA proprietary driver |
| Proton | proton-cachyos 11.0 (Wine 11.0) through [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) 1.4 |
| Game | GTA San Andreas 1.0 US, SA-MP 0.3.7-R5, open.mp client 0.4.0 (launcher 1.7's), DXVK `d3d9.dll` in the game folder |
| Launcher | open.mp launcher 1.7.0 (rebuilt), WebView2 155 |

---

## The short version

1. **WebView2 from the offline standalone installer** (`fwlink 2124701`,
   `/silent /install`) installs fine under Proton. The launcher is a Tauri app
   and needs it.
2. **Upstream's launcher crashes under Wine** about a second in. wry calls
   `RevokeDragDrop` on WebView2's window, which belongs to another process,
   and Wine's implementation lacks the cross-process check. The rebuilt
   launcher has no drag-and-drop handlers.
3. **It also lagged badly, spinning two cores.** Its server queries used
   tokio's UDP socket, and Wine's poll reports a "connect failed" readiness
   that tokio keeps retrying. The rebuild uses a blocking socket with a
   timeout.
4. **The launcher's own download of the open.mp plugin stalls** ~24 KB short
   under Wine. `install.sh` downloads `omp-client.dll` itself and checks its
   MD5; the launcher keeps a correct one.
5. **Render WebView2 in software** (`--disable-gpu`, passed through the
   rebuild's `OMP_WEBVIEW2_ARGS`): faster and smoother than through DXVK here.
6. **Start games from the launcher.** The in-game browser hands frames over in
   shared memory, which only works within one wineserver. That means one
   prefix, and one launcher per machine (it owns TCP port 45791).
7. **The in-game browser needs the rebuilt launcher.** Since 1.7.0-wine.1 it
   injects the game's side of the browser itself (from
   [omp-ingame-browser-wine](https://github.com/akacross/omp-ingame-browser-wine));
   older rebuilds need that repository's `ompoverlay.asi` in the game folder.
8. **Reconnecting from the in-game browser could crash the game** 30 s later.
   It's an old GTA SA bug that the reconnect happens to trigger;
   `animwipefix.asi` fixes it.
9. **open.mp 1.7's client crashed the game as it quit** (`0xC0000409`: a
   thread object destroyed while still joinable). The rebuilt launcher's
   injected hook releases it first, so the game exits cleanly.

Everything else is in [docs/](docs/):

| | |
|---|---|
| [LAUNCHER.md](docs/LAUNCHER.md) | every launcher problem under Wine, its cause and fix, plus running it (Wayland, virtual desktop, icons, stopping it) |
| [IN-GAME-BROWSER.md](https://github.com/akacross/omp-ingame-browser-wine/blob/main/docs/IN-GAME-BROWSER.md) | the in-game browser, end to end |
| [RECONNECT-CRASH.md](https://github.com/akacross/omp-ingame-browser-wine/blob/main/docs/RECONNECT-CRASH.md) | the reconnect crash: dump, cause, fix |
| [SAMPCMD.md](docs/SAMPCMD.md) | starting games through sampcmd |
| [DXVK-CRASH.md](docs/DXVK-CRASH.md) | an open crash in DXVK's `d3d9.dll`, and the watchdog for it |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | logs, and what to look at first |

---

## Install

You need:
- a Wine/Proton prefix where SA-MP already plays: GTA SA 1.0 US with SA-MP
  0.3.7 installed;
- `umu-run`, `curl`, `python3`, `sha256sum`, `md5sum`.

```bash
git clone https://github.com/akacross/samp-openmp-linux && cd samp-openmp-linux
./install.sh --prefix ~/Games/samp/pfx --game ~/Games/gta-sa \
             --proton /usr/share/steam/compatibilitytools.d/proton-cachyos-slr
```

It is idempotent: run it again to update. In order, it:

1. installs WebView2 into the prefix, unless it is there;
2. installs the launcher build from the latest release of
   [omp-launcher-wine](https://github.com/akacross/omp-launcher-wine)
   (`--variant sampcmd`: [the sampcmd one](https://github.com/akacross/omp-launcher-wine-sampcmd)),
   checked against its `SHA256SUMS`;
3. downloads `omp-client.dll` from the URL open.mp's API gives, and checks its
   MD5;
4. sets the game folder in SA-MP's registry key if none is set
   (`HKCU\Software\SAMP`, `gta_sa_exe`), plus `--name`;
5. copies `animwipefix.asi` into the game folder, checked against its
   release's `SHA256SUMS` (`--no-asi` to skip);
6. writes `~/.config/samp-openmp-linux/omp-launcher.conf` and
   `~/.local/bin/omp-launcher`;
7. extracts the launcher's icons from the installed exe into
   `~/.local/share/icons/hicolor`, and writes a desktop entry whose
   `StartupWMClass` matches the window (see LAUNCHER.md).

`--from DIR` takes any of the downloads from a folder instead; `--dry-run`
only says what it would do. Start the launcher from the menu or with
`omp-launcher`. `omp-launcher --stop` stops it.

## License

The scripts and docs here are MIT. The open.mp launcher is open.mp's
(MPL-2.0 with a trademark supplement: modified versions keep its name and
branding, which the builds above do). WebView2 is Microsoft's. The icon the
desktop entry uses is extracted from your installed launcher and is not
distributed here.
