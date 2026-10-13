# Troubleshooting

## Where the logs are

| log | where | what |
|---|---|---|
| `omp-launcher.log` / `.prev.log` | next to `omp-launcher.exe` | the launcher. Look for `[wine_overlay]` lines: overlays opening and closing, and WebView2 processes dying. |
| WebView2 crash reports | `%LOCALAPPDATA%\mp.open.launcher\EBWebView\Crashpad\reports\*.dmp` | a crashed WebView2 process |
| `sampcmd.log`, `sampcmd-crash-*.dmp` | the game folder | the sampcmd variant: the game's start, its `OutputDebugString` (ompoverlay, d3d9watch, animwipefix lines), and crashes |
| `animwipefix.log` | the game folder | whether the reconnect crash fix is in place |
| `d3d9watch.log` / `.prev.log` | the game folder | misuse of the D3D9 device (if d3d9watch is installed) |

`%LOCALAPPDATA%` is `<prefix>/drive_c/users/steamuser/AppData/Local` under
Proton.

## Common problems

- **The launcher crashes about a second in.** That is upstream's build (the
  `RevokeDragDrop` crash). Install the rebuilt one.
- **The launcher's window is blank or frozen.** WebView2 died. The rebuild
  restarts itself and logs the failure kind; if it didn't, check the
  Crashpad reports and `omp-launcher.prev.log`.
- **The launcher hangs at start, nothing happens.** Another program is still
  running in the prefix, and Proton's `waitforexitandrun` is waiting for it.
  Close it, or `omp-launcher --stop`.
- **The in-game browser shows only a cursor.** No launcher, no WebView2, or
  the game is in a different prefix or wineserver than the launcher. Start
  the game from the launcher.
- **It shows an empty square.** `ompoverlay.asi` is missing from the game
  folder, or the launcher is upstream's.
- **It works once.** An old `ompoverlay.asi`: update it.
- **The game tabs out when the browser opens.** Upstream's launcher, or an
  old rebuild.
- **"Failed to bind to IPC port"** in the launcher log: another launcher on
  the machine holds 45791. Run one.
- **The plugin download never finishes.** Run `install.sh` again (it fetches
  `omp-client.dll` itself), or place it by hand.
- **A crash ~30 s after reconnecting** (`gta_sa.exe+0x41214A`):
  `animwipefix.asi` is missing; see
  [RECONNECT-CRASH.md](https://github.com/akacross/omp-ingame-browser-wine/blob/main/docs/RECONNECT-CRASH.md).
- **`d3d9.dll+0x1A63E9`:** see [DXVK-CRASH.md](DXVK-CRASH.md).
- **`0x007F7C82` in `gta_sa.exe`, EAX 0, after the window changed size or an
  alt-tab:** a `Reset` failed. RenderWare resets the device when the window's
  client size changes and never checks the result. After a failed one it
  clears the camera raster it has just released. DXVK fails `Reset` while
  anything still holds a `D3DPOOL_DEFAULT` resource. With
  [d3d9watch](https://github.com/akacross/d3d9watch) installed, `d3d9watch.log`
  lists what was still held, and who made or fetched it.
