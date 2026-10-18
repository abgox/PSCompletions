# End-to-end testing with the built binary

Unit tests (`cargo test`) cover logic in isolation. When a change touches the real
menu path — manifest resolve → hook run → item build — verify it against the actual
`psc-menu` binary by driving build mode directly. This applies to any engine or
hook change, not one specific API: hook firing and position matching, item
building, log output, and failure surfacing.

All commands below assume the repository root as the working directory. Paths
under `/tmp/psc-e2e` are scratch space — pick any empty directory.

## 1. Rebuild and deploy first

`cargo test`/`cargo clippy`/`cargo build` do **not** update what the module loads. The module
runs **both** binaries under `module/PSCompletions/bin/<platform>-<arch>/` (e.g.
`linux-x64`) — `psc-menu` for the menu and `psc` for every management command — so a
Rust fix covered only by `cargo test` is invisible to the real thing. Deploy them:

```powershell
pwsh -NoProfile -File scripts/build-release.ps1
```

Defaults to the host platform/arch: release-builds the core workspace and copies
`psc-menu` + `psc` into the module directory (stopping a same-path running process
to release the file lock). See `scripts/build-release.ps1`.

Sanity-check the fresh binary before hand-driving it:

```powershell
./module/PSCompletions/bin/<platform>-<arch>/psc-menu --self-test
```

It parses a bundled sample, builds state, and exercises filters and layout
without touching a terminal; `self-test ok` means the binary is healthy.

If a fix "doesn't work" in manual testing, a stale binary is the first suspect —
rebuild + redeploy before investigating further.

## 2. Drive build mode with a hand-written input file

`psc-menu <input.json> --result <output.json>` with empty `items` and a `build`
context builds the candidates from the manifest + `hooks.lua`, rewrites the input
file with the built items, then opens the TUI. The full contract is in
[protocol.md](protocol.md); the minimal shape for a test is:

```json
{
  "items": [],
  "build": {
    "cmd": "t",
    "arg_tokens": ["help", ""],
    "treat_last_as_complete": false,
    "manifest": "/tmp/psc-e2e/t/language/en-US.json",
    "hooks": true,
    "cwd": "/tmp/psc-e2e/t",
    "config": {}, "global_config": {}, "data": {},
    "cache_dir": "",
    "log_dir": "/tmp/psc-e2e/log"
  },
  "config": { "flags": {} },
  "terminal": {
    "cursor": { "x": 0, "y": 5 },
    "buffer": { "w": 120, "h": 30 },
    "platform": "linux"
  }
}
```

Field notes:

- `manifest` points at the language file; the hook is located by replacing
  `<cmd>/language/<lang>.json` with `<cmd>/hooks.lua` (see `menu/protocol.rs`
  `hooks_path`), so a fixture must mirror that layout.
- `log_dir` non-empty enables `psc.log` → `debug.log`; hook errors
  (e.g. unknown `psc.on` targets) land in `error.log`.
- `cache_dir: ""` disables the 10-second result cache, so every run rebuilds.

## 3. The TUI blocks — launch, wait, kill, read back

The menu is interactive, so a foreground run never returns in a script. Launch it
detached, let the build stage finish, kill it, then read two artifacts:

```powershell
$bin = "./module/PSCompletions/bin/<platform>-<arch>/psc-menu"  # e.g. linux-x64
$proc = Start-Process -PassThru -NoNewWindow -FilePath $bin `
  -ArgumentList "/tmp/psc-e2e/in.json", "--result", "/tmp/psc-e2e/out.json" `
  -RedirectStandardError /tmp/psc-e2e/stderr.txt -RedirectStandardOutput /tmp/psc-e2e/stdout.txt
Start-Sleep -Seconds 3
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
Start-Sleep -Seconds 1  # let the background order thread flush its files
(Get-Content /tmp/psc-e2e/in.json -Raw | ConvertFrom-Json).items |
  ForEach-Object { $_.completion_text }
Get-Content /tmp/psc-e2e/out.json -ErrorAction SilentlyContinue
Get-Content /tmp/psc-e2e/log/debug.log -ErrorAction SilentlyContinue
```

Do **not** redirect with `> $null 2>&1` on the `Start-Process` line — it nulls the
`-PassThru` handle and the later `Stop-Process` fails on a null id. Use the
`-Redirect*` file arguments instead.

- The **rewritten input file** (`.items[].completion_text`) is the assertion
  surface for built candidates.
- The **result file** carries `{"status":"error",...}` when the build itself
  failed — check it before concluding the hook produced nothing.
- In a headless shell the UI dies after the build with `input poll failed` —
  that is expected noise; the build (and the input-file rewrite) already
  happened.

## 4. Isolate with a minimal fixture, then confirm on the real thing

Debug against a tiny manifest + hook outside the repo, so `psc.log` output is
unambiguous. Start with a probe that shows the context the hook actually sees,
then exercise the API under test:

```powershell
New-Item -ItemType Directory -Force /tmp/psc-e2e/t/language | Out-Null
Set-Content /tmp/psc-e2e/t/language/en-US.json '{ "next": [ { "name": "help" }, { "name": "cache", "next": [ { "name": "clear" } ] } ] }'
Set-Content /tmp/psc-e2e/t/hooks.lua 'psc.on({ command = "help" }, function() psc.log(psc.tokens) end)'
```

Run `luac -p` on any hook before testing — a syntax error fails silently at
runtime. Once the fixture behaves, re-run the same procedure against the real
completion (e.g. `completions/ya/language/en-US.json`) as the final confirmation.

Recipes worth reusing:

- **Root context**: `arg_tokens: [""], treat_last_as_complete: false` builds the
  command's root menu.
- **Deterministic builds**: `"hooks": false` skips hook subprocesses (e.g. git's)
  so the items reflect the static manifest only.
- **Verifying order files**: the background recompute fires only when the
  **top-level** `order` (`history`/`cmd`/`aliases`/`path`) is present — it writes
  the per-command file plus `_shared/`. The `build.order` paths only feed ranking
  reads. Point both at a scratch dir and inspect the written JSON afterwards.
- **Don't drive the host module headless**: dot-sourcing it with a partial init
  fails (`path.completions` points at the data dir, not the repo; `get_completion`
  needs full state). Verify host-side logic by copying the snippet into a
  standalone harness with mocked state, and verify the build with the repo
  manifest path directly.

## 5. Pitfalls

- `treat_last_as_complete: false` means the last token is **being typed**
  (pending); `true` means every token is completed. The name reads backwards —
  `false` is what a "user is typing" test wants.
- An empty-string last token with `treat_last_as_complete: true` counts as a
  **completed `unknown` token** and occupies the positional slot, so default
  (non-`multiple`) `psc.on` specs silently do not fire. With `false` the same
  token becomes the pending typing and the specs fire.
- A `psc.on` handler that never fires is usually slot gating (above) or an
  unknown target — the latter is logged to `error.log`, never raised.
- `debug.log` only grows when `log_dir` is non-empty; an empty `debug.log` after
  a run means logging was off, not that the hook was silent.

## 6. The CLI contract tests open exactly one port

`core/cli/tests/*` run the **built** `psc` binary (as this whole document does), so anything
that would touch the network must be answered locally. The rule is one server, in one place:

- **`common::spawn_server(routes)`** (`core/cli/tests/common/mod.rs`) is the only code in the
  suite that binds a port — `127.0.0.1:0`, so the OS picks a free one. Tests never collide with
  each other and **no fixed port exists anywhere**; parallel runs are safe.
- Routes are `(path, body)` pairs keyed **without** the leading `/` (`"completions.json"`) — the
  form `demo_routes()` uses; the request path is matched exactly, query string stripped.
- `spawn_server_mut(routes)` hands the route table back (`Arc<Mutex<HashMap<..>>>`) so a test can
  rewrite it between calls — e.g. bump the remote index from v2 to v3 and re-run `update`. It
  exists so that no test needs its own copy of the HTTP loop.
- `make_data(tag, url)` writes `settings.json` with `config.url` pointing at that server, which is
  what keeps `add` / `update` offline. A test that wants **no** network at all points `url` at
  `http://127.0.0.1:9` — the discard port, deliberately unreachable — never at a real host.

A new test that needs a server uses the helper; it does not open its own `TcpListener`.
