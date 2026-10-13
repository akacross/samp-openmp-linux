# Starting games through sampcmd

[sampcmd](https://gitlab.com/akacross/sampcmd) is a command-line SA-MP
starter: it creates the game suspended, injects `samp.dll` (and
`omp-client.dll`), and with `--monitor` stays attached as a lightweight
debugger. That gives it a log of module loads and `OutputDebugString`, crash
capture (SA-MP's crash text, the code on the stack, a minidump next to
`sampcmd.log`), and host checks.

[omp-launcher-wine-sampcmd](https://github.com/akacross/omp-launcher-wine-sampcmd)
is the Wine launcher plus one change: with `OMP_SAMPCMD` set, it starts games
as

```
sampcmd.exe $OMP_SAMPCMD_ARGS --game-dir <game> [--exe <custom>] \
    --dll <samp.dll> --omp --omp-dll <omp-client.dll> \
    -- -c -n <name> -h <ip> -p <port> [-z <password>]
```

It passes the same DLLs it would have injected itself, and lets sampcmd do
the injecting. Unset or empty, it injects as upstream does. `OMP_SAMPCMD` is
`sampcmd.exe` (absolute, or relative to the game folder).
`OMP_SAMPCMD_ARGS` is split on whitespace. The launch script defaults it to
`--monitor --verbose --full-dump` for the sampcmd variant.

```bash
./install.sh --variant sampcmd --prefix ... --game ...   # needs sampcmd.exe in the game folder
```

`--full-dump` matters for heap corruption: a mini dump has only the faulting
thread and the code around it, not the memory that was damaged. Under Wine,
dbghelp ignores the extra-memory flags, so a full dump is the only way to
get the heap. It is ~1 GB per crash; delete old ones.
