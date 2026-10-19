# Design: Bridge reference — PowerShell

> PowerShell-specific notes for `module/PSCompletions/`.
> Generic duties live in `bridge.md`; this file records only what a porter would get wrong copying it blind.
> Code leaves, not prose mirrors: each item points at the function that owns it.

## Locked behaviors (do not change without a port note)

- Trigger owns every press: `Tab` is rebound to `menu.script`; installed and native completions share one dispatch (`menu.script`).
- Lazy init: first trigger runs `psc init` (`init_data`); management commands refresh it.
- Notifications: module updates persist; library `added`/`removed` are one-shot, `update`/`renamed` persist (`render_pending`, `render_library_changes`).
- Watchdog: 30 s stderr silence kills the menu, emits `ESC[?1049l`, restores the whole saved region (`show_module_menu`).
- Restore rules: exact `covered_*` on exit, whole region on abnormal death, nothing on no-render cancel; cursor always re-seated; input line never saved.

## Port-relevant quirks

- `darwin` names the binary dir, `macos` the protocol field — intentional, do not unify (`menu_binary`).
- nupkg drops the Unix exec bit: re-apply `+x` on discovery (`menu_binary`).
- Native output decodes via console encoding (GBK on Chinese systems): switch to UTF-8 around every binary call (`_forward_psc`).
- A data read prints the CLI's text as it stands (`_forward_psc -Plain`); a status message takes green, a failure red — the module builds no objects of its own (`bridge.md` §7).
- Manifest language is per-completion first, then module, then declared-first, cached (`get_language`); the engine's tip language follows the manifest file, not the config.
- Trigger-key rebind persists only after the bind succeeds, restoring the old key on failure (`psm1 config` set path).
- Legacy data migrates from versioned sibling dirs, else seeds bundled `psc` (bottom of `PSCompletions.ps1`).
- `MenuComplete` (the host menu) runs only when `enable_native_completion` is off; otherwise words unknown to the library resolve through `TabExpansion2` into our menu (`menu.script`).
