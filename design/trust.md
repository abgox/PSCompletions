# Design: Trust model (hooks, sources, sandbox)

> What the sandbox actually guarantees, where trust comes from, and what counts as an official source.
> Companion docs: `hooks.md` (API reference), `psc-cli.md` (§7 `url`).

## 1. What the sandbox guarantees

A hook runs in a Lua VM with no native dangerous surface:

- Disabled: `io`, `package`/`require`, `dofile`/`loadfile`/`load`, `debug`, `os.execute`/`os.exit`/`os.remove`/`os.rename`/`os.tmpname`/`os.getenv`. What remains of `os` is time functions only. Even a bundled `luasocket` cannot be loaded.
- The `psc.*` capability set outside pure string tools: `read` / `exist` / `ls` / `glob` / `json` / `toml` / `yaml` (and `_batch`) / `which` / `env` (all read-only), `log` (writes only to the hook log dir), `add` / `items` (in-memory candidate list only).
- The single exception is **`psc.run` / `psc.run_batch`: arbitrary subprocess execution**
(no allowlist).
It is legitimate egress — `git`/`scoop` completions need it — and the only way a hook touches the network (`curl` ships everywhere; 5 s default timeout is plenty for exfiltration).

So the sandbox guarantees one thing: **apart from spawning subprocesses, a hook cannot touch the system**.
`read` can stage secrets and `run` can transmit them, but that is a two-step spelling `review` sees in plain text.
Timeouts (10 s hook, 5 s run, 500 ms glob) bound accidents, not malice.

## 2. Where trust comes from

Same as installing software, two legs:

1. **Opt-in**: hooks run only for completions the user installed (`add`), and only when `enable_hooks` is not `0` (`psc`'s own hooks cannot be disabled).
2. **Review**: the official library is reviewed; a malicious hook must spell `curl` (or equivalent) in reviewable Lua — it cannot hide behind an indirect API.

## 3. Official sources

An official source is any `config.core.url` value the project itself suggests:

- `""` (auto: Gitee/GitHub by language, then the Pages root), or
- a candidate from the installed psc manifest's `config core url` value list (`next → config → core → url → next[].name`, quotes stripped), or
- a static default base (`core/cli/src/net.rs`: Gitee, GitHub, Pages root) when the manifest is unreadable.

Setting any other URL prints a one-time warning (`url_untrusted`, text + `--json` `warning` field): the source is unreviewed and its `hooks.lua` runs with the user's privileges.
Clearing `url` back to `""` returns to official.
