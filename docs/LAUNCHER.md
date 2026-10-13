# The open.mp launcher under Wine/Proton

open.mp launcher 1.6.1 is a Tauri 1 app (tao 0.16, wry 0.24) that draws its UI
in WebView2. Upstream's build installs and opens under Proton once WebView2 is
there, but it is unusable. The fixes below are in
[omp-launcher-wine](https://github.com/akacross/omp-launcher-wine); its
[WINE-BUILD.md](https://github.com/akacross/omp-launcher-wine/blob/wine/WINE-BUILD.md)
has them with the code. Outside Wine the rebuilt launcher behaves as
upstream's.

## WebView2

- **Use the offline standalone installer** (Evergreen, `fwlink 2124701`):
  `umu-run MicrosoftEdgeWebView2RuntimeInstallerX64.exe /silent /install`.
  The online bootstrapper half-installs under Wine. The x64 runtime serves
  the 32-bit launcher as well.
- The rebuilt launcher is a MinGW build. It loads WebView2 through
  `WebView2Loader.dll`, which has to sit next to `omp-launcher.exe`.

## Problems and fixes

| problem under Wine | cause | fix |
|---|---|---|
| Crash ~1 s after start, exit code 5 | wry swaps WebView2's drag-and-drop handler for its own with `RevokeDragDrop` on WebView2's window, which belongs to `msedgewebview2.exe`. Windows refuses; Wine's `RevokeDragDrop` lacks the cross-process check and releases another process's pointer. Not Xalia: it crashes with `PROTON_USE_XALIA=0` too. | No drag-and-drop handlers: `fileDropEnabled: false`, and `disable_file_drop_handler()` on overlays. |
| Typing and resizing lag; two cores busy while idle; wineserver ~70% | Server queries used tokio's `UdpSocket`. Wine's AFD poll can flag a connected UDP socket `AFD_POLL_CONNECT_FAIL` (0x100); tokio keeps `READ_CLOSED` set, while Wine's `recv` answers "would block". So tokio retried in a tight loop until the 2 s query timeout, on a socket that was cached and reused. | A blocking `std::net::UdpSocket` with a 2 s read timeout, on tokio's blocking pool. Idle CPU went from 17 s per 10 s to ~0.05 s. |
| Resize cursor stuck after crossing an edge | wry sets the resize cursors itself but leaves the arrow to Chromium, and Chromium (another process) cannot set this window's cursor under Wine. | Vendored wry always sets the cursor, the arrow included. |
| Black box around the window | A transparent window with a 4 px margin around a rounded panel; Wine shows that margin black. | No margin, no rounded corners. |
| Wine's generic icon in the taskbar | Tauri sets no window icon. Windows falls back to the exe's, but the Linux desktop only sees the window's. | `WM_SETICON` with the exe's icon resource. |
| The plugin gets "updated" to an older one (v0.1.4) | Upstream race: the loading screen's plugin check can use the update info's top-level fields (the previous launcher's plugin) instead of this build's `versions["6"]`. | The same version match there. |
| Its download of `omp-client.dll` stalls ~24 KB short | `tauri-plugin-upload` (reqwest on tokio) under Wine; not fixed. | `install.sh` downloads the plugin (URL and MD5 from `api.open.mp/launcher`). A correct plugin in place is kept. |
| The game tabs out; the in-game browser is empty, then opens only once | See [omp-ingame-browser-wine](https://github.com/akacross/omp-ingame-browser-wine). | The overlay is unfocused and parked off screen, with frames in shared memory. |
| The window goes blank and frozen | WebView2's browser process crashed; the page dies with it. | Overlays close between captures; a dead WebView2 process is logged, and the launcher restarts itself ([LAUNCHER-LOCKUP.md](https://github.com/akacross/omp-ingame-browser-wine/blob/main/docs/LAUNCHER-LOCKUP.md)). |

## Rendering

The rebuild appends `OMP_WEBVIEW2_ARGS` to WebView2's browser arguments.
WebView2's own `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` and its policy key are
ignored once the app passes arguments, which wry always does. The launch
script sets `--disable-gpu`, so WebView2 draws in software and hands Wine
plain GDI output, not a DXVK swapchain in another process's child window.

Measured with Chromium's event timing (`--remote-debugging-port` through the
same variable):
- with the GPU: 60 frames a second, and 4 of 24 keystrokes painted later than
  16 ms (worst 40 ms);
- in software: the monitor's rate, and all 24 painted within 16 ms.

## Running it

- **umu and the window class.** Proton names the window class
  `steam_app_<id>`, from `GAMEID=umu-<id>`. That has to match the desktop
  entry's `StartupWMClass` for the taskbar to group and badge it. umu only
  takes ids matching `umu-[A-Za-z0-9_]+`: `umu-omp-launcher` became
  `steam_app_0`, hence `umu-omplauncher`.
- **Plain window or virtual desktop.** It runs as a plain window. A Wine
  virtual desktop (`VIRTUAL_DESKTOP=1`) works too, but this Proton always
  opens it full screen, sizes ignored (even with
  `WINE_DISABLE_FULLSCREEN_HACK=1`). Games started from the launcher then
  open inside it.
- **Native Wayland does not work.** `PROTON_ENABLE_WAYLAND=1` gives a blank
  window, with the GPU and in software. winewayland shows nothing from a
  child window owned by another process, and WebView2's content window
  belongs to `msedgewebview2.exe`.
- **Xalia.** `PROTON_USE_XALIA=0`: Proton's accessibility helper reads the
  window through UI Automation, which switches Chromium's accessibility mode
  on and slows it down.
- **Games started from the launcher** inherit its environment.
  `WINEDLLOVERRIDES=d3d9=n,b` makes them use a DXVK `d3d9.dll` from the game
  folder if there is one.
- **One prefix, one wineserver, one launcher.** The in-game browser's frames
  go through named shared memory, which does not cross wineservers: start
  games from the launcher. A second launcher on the machine cannot bind the
  IPC port (45791), which the in-game browser needs.
- **`waitforexitandrun`.** A second `umu-run` into a busy prefix waits for
  the prefix to go idle; anything left running there blocks the next start.
  Tools started alongside need `PROTON_VERB=run`.
- **Stopping it.** Its processes live inside pressure-vessel, so `kill` from
  the host does nothing. `omp-launcher --stop` runs Wine's
  `taskkill /f /im omp-launcher.exe` in the prefix instead. Never
  `wineserver -k` a prefix with a game running in it: that ends the game too.

## Logs

`omp-launcher.log` sits next to the exe and is truncated at every start; the
rebuild keeps the previous run's as `omp-launcher.prev.log`. Its own output
(and Wine's) goes wherever the launch script was started from: a terminal, or
nowhere from the desktop menu. WebView2's crash reports go to
`%LOCALAPPDATA%\mp.open.launcher\EBWebView\Crashpad\reports\`.
