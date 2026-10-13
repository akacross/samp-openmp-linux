# An open crash: `d3d9.dll+0x1A63E9` (DXVK)

**Status: cause not found.** [d3d9watch](https://github.com/akacross/d3d9watch)
is there to catch it next time.

```
ACCESS_VIOLATION at d3d9.dll+0x1A63E9   reading 0xFFFFFFFF
```

It happened three times, with DXVK 3.1.1 as the game's `d3d9.dll`:

| when | context |
|---|---|
| after ~8 min, on alt-tab back in | the swapchain is rebuilt |
| 161 s into a session | chat input opened 1 s before; the DXVK log ends with "Got VK_SUBOPTIMAL_KHR, recreating swapchain" |
| ~2.5 min after the last in-game browser use | full memory dump taken |

## What the fault is

The instruction is `movaps [edx+0x30], xmm1`, right after
`edx = allocator->free; allocator->free = *edx`. That pops a record off the
free list of DXVK's `DxvkResourceAllocation` pool (head at allocator+0x35E8).
The popped pointer was misaligned, so `movaps` faults with #GP, which
Windows reports as an access violation at 0xFFFFFFFF; that address means
nothing. The crash only surfaces the damage. The swapchain rebuilds and the
allocations (an ImGui renderer's discards, in the dump) are just whoever
took the next record.

## What the full dump shows

- **The head was off by one.** It was `0x380B6CFF`, exactly one less than a
  valid record at `0x380B6D00`.
- **The record format.** Records are 0x80 bytes. +0 is both the free-list
  "next" pointer and the reference count; +0x08 a resource cookie, +0x20 the
  size, +0x28 a mapped host pointer, +0x68 the allocator.
- **So:** a reference release (a decrement by one) hit a record that was
  already on the free list. Something used or released a D3D9 resource
  after its last release.
- **The neighbouring freed record** (cookie 0x141) was an old storage block
  of GTA's own RenderWare dynamic vertex buffer: 256 KB, `DYNAMIC|WRITEONLY`,
  held at `gta_sa.exe+0x897BC4`, renamed on every discard lock. Its index
  buffer twin is 20000 bytes.
- **GTA's device is single-threaded:** created with flags `0x50`, no
  `D3DCREATE_MULTITHREADED`. RenderWare adds that only when its "multithread
  safe" option is on (`gta_sa.exe` 0x7F6710), and GTA never sets it. So any
  D3D9 call from another thread races the game.

Ruled out:
- open.mp's client calling D3D9 off the main thread. Its IPC thread only
  queues messages, which are handled per frame on the main thread.
- A deleted texture still bound, or named in an ImGui draw command, at crash
  time.
- MoonLoader's Lua lanes, which only decode images (WIC).
- A map mod's tile eviction, which skips anything its last frame drew.

Scanning the dump by vtable also finds dead objects: vectors keep stale
entries after a clear. So "a tracking entry points at a freed record" proves
nothing on its own.

## d3d9watch

An ASI that hooks every `IDirect3DDevice9` method, and every DXVK texture,
surface and buffer vtable (found by RTTI, base classes included), chaining
to any existing hooks. It logs, with the caller's `module+offset` and a short
stack, any of:
- a call from a thread other than the game window's;
- a method called on an object DXVK has already deleted (the private
  refcount at +8 has 0x80000000 added just before deletion);
- a deleted resource handed to the device.

It writes to `d3d9watch.log` (previous run in `d3d9watch.prev.log`) and to
`OutputDebugString`. Normal calls cost about 0.3 ns. If this crash comes back,
its log should name the culprit even before DXVK falls over.
