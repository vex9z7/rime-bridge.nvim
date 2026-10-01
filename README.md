# rime-bridge.nvim

**v0.1.0 — MIT-licensed source release.**
This independent source tree starts with a system-Rime native worker and protocol
regressions, Lua lifecycle/health checks, opt-in ordinary-buffer input and a Blink
adapter. Real LazyVim integration has been tested separately. setup does not
create a scratch buffer or automatically enable input. See [release notes](CHANGELOG.md)
and [dependency/data boundaries](NOTICE.md).

## Build the worker

Linux, a C++17 compiler, CMake >=3.16, system librime development files and
nlohmann-json headers/CMake package are required. Tests additionally need Python3
and a Rime shared-data directory at /usr/share/rime-data with luna_pinyin_simp
for the native protocol suite (Ubuntu: rime-data-luna-pinyin). Ubuntu package names:
`g++ cmake librime-dev nlohmann-json3-dev librime-data python3`.
Install dependencies yourself; CMake does not download them or build librime.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
cmake --install build --prefix "$HOME/.local"
```

This installs `rime-bridge-worker` in the selected prefix's bin directory, not
librime or Lua files. Neovim plugin managers install the Lua modules; CMake does not install them. Use `-DBUILD_TESTING=OFF` for builds without the Python test runner.
A local build is not a universally portable binary.

## Data and scope

Users own the system engine and a separate writable Rime user directory. The
first-version scheme baseline is upstream Wanxiang Pure v18.0.15; no dictionaries,
models or personal learning data are bundled. Full Wanxiang/Ice, ARM64 validation
and cross-distribution prebuilt binaries are deferred. Model effectiveness is
not verified. This worker does not seed or replace configuration.

Use one worker per Neovim and one writer per dedicated data directory. The lock
coordinates this worker only: never share a live desktop-IME directory, or run
historical PoC workers concurrently against the same data. Their lock names differ.

## Development status and provenance

Native protocol handling and fixtures were extracted from the system-backed
PoC at parent revision a06142d, not from a new engine implementation. Historical
PoC sources remain unchanged. Tests here own independent copies and do not read
parent-repository paths. The worker uses the official Rime C API and user-installed
system dependencies, with no private library bundle.

Protocol tests are not proof of normal-buffer/Blink input. See doc/protocol.md.
Original plugin source is covered by the [MIT License](LICENSE), approved by the
repository owner. Separately installed dependencies and scheme data retain their
own terms; see [NOTICE.md](NOTICE.md).

## Foundation verification

On 2026-10-01, configure, compile, CTest (worker.protocol) and installation to an
isolated local prefix passed on Ubuntu 22.04 x86_64 with GCC 11.4, system librime
1.7.3 and nlohmann-json 3.10.5. No system packages were installed/upgraded.
The development container without librime-dev separately exercises the actionable
configure-time missing-dependency error. That initial foundation run did not establish normal-buffer acceptance; the
ordinary-buffer and Blink regressions below now supply that separate evidence.


## Opt-in ordinary-buffer input

Neovim >=0.10 is required; the tested host is Neovim 0.12.5. Load this repository
through your plugin manager, then configure a dedicated, prepared Rime directory:

```lua
require("rime_bridge").setup({
  worker = "/absolute/path/to/rime-bridge-worker", -- default: PATH lookup
  user_dir = "/absolute/path/to/dedicated-rime-data",
  schema = "wanxiang_pure", -- default; use the upstream Pure schema ID
})
```

setup does not start a worker, create buffers, install mappings or deploy data.
For a newly prepared/changed data directory, use `:RimeDeploy` explicitly and wait
until `:RimeInfo` reports initialized. Deployment disables input and is never
performed implicitly by enable/start. It does not download a scheme or seed data.

In a modifiable ordinary file buffer, use `:RimeEnable`, `:RimeDisable` or
`:RimeToggle`. Matching Lua functions are enable(), disable(), toggle(), deploy().
Activation is asynchronous; `:RimeInfo` reports enabled once the schema is selected.
Only one buffer is enabled at a time. Enabling another detaches the previous one;
leaving a buffer cancels composition without moving it to another buffer.

While enabled:
- Printable ASCII goes to Rime; inline preedit is not inserted into the file.
- A simple native floating window shows candidates in engine order.
- Space/Enter commits, 1–9 selects, -/= pages, Ctrl-n/p moves candidate selection.
- Esc, cursor movement, Tab, mode/buffer/window changes cancel composition.
- Paste via nvim_paste cancels composition and delegates to the original paste handler.
- Disabling removes owned mappings and restores previous buffer mappings; mappings
  replaced by the user while active are not overwritten on cleanup.

The prototype-independent input adapter temporarily owns these insert-mode keys.
The default native UI does not isolate competing completion. Use an isolated
configuration for native mode, or the explicit Blink adapter below. Standalone
AI virtual-text producers still require separate integration. No default F6 or global input
mapping is installed by the plugin itself. Configuration may add a toggle, but
input remains off until explicitly enabled.

start() initializes only the backend, without selecting/deploying a schema or
capturing keys. stop() detaches input and closes the backend; disable() keeps the
worker available. Exiting Neovim closes it. `:checkhealth rime_bridge` checks
configuration/runtime without starting it. Worker errors/timeouts restore maps,
remove UI and notify; inspect `:RimeInfo` and explicitly re-enable after fixing the
cause. Uncertain pending input is not replayed after failure to avoid duplication.
Engine stderr is classified into at most six fixed diagnostic categories exposed
by RimeInfo/checkhealth (runtime loader, Lua, component, schema, dictionary, generic
engine). Raw lines, candidate text and commits are never written to diagnostic
logs or included in these categories; stderr framing uses a transient 4 KiB tail.
Categories are hints, not proof of a functioning schema: successful deployment
still requires an actual candidate/commit check. Unknown messages produce only
the generic hint. No raw-log capture command is provided.

A busy directory fails before key interception, with advice to stop the other
bridge or configure another dedicated directory. **Do not delete the lock file**
to work around a live writer. Desktop IMEs use different locking; keep their
directories separate. RimeDeploy never replaces your source configuration files.

## Editor regression tests

CTest includes lua.foundation and lua.input when Neovim is found (or selected
with -DNVIM_EXECUTABLE=/path/to/nvim). Missing Neovim is reported, not a test pass.
The ordinary-buffer suite uses actual nvim_input events and nvim_paste, with no
Chinese buffer insertion used as typing evidence. It tests commit/rapid input,
selection/paging, cancel, undo/redo, mapping restoration, paste, buffer/cursor
changes, forced delayed responses, timeout/restart and worker death.

To run against an explicitly prepared **test-only** Pure directory:

```sh
RIME_BRIDGE_SOURCE="$PWD" \
RIME_BRIDGE_WORKER="$PWD/build/rime-bridge-worker" \
RIME_TEST_USER_DIR=/absolute/isolated-pure-test-data \
RIME_TEST_SCHEMA=wanxiang_pure \
nvim --headless -u NONE -i NONE -c "lua dofile('tests/test_input.lua')"
```

The supplied test directory is deployed and accumulates learning data; it is not
deleted. Never point this regression at a personal or live desktop-IME directory.
Without it, the editor test uses the small fixed dictionary/schema in tests/fixtures
in an automatically removed temporary directory. The native protocol suite still
requires system luna_pinyin_simp data. Real-scheme tests are a separate acceptance layer.

Repeatability check: after making edited test-fixture mtimes distinct for the old
engine's deployment cache, `ctest --repeat until-fail:5` passed both suites five
times on the host (exit 0). An earlier rapid-edit run missed the newly added
schema; this fixture correction does not claim a production deployment-cache fix.


## Ordinary-buffer acceptance — 2026-10-01

On Ubuntu 22.04 x86_64 with system librime 1.7.3 and Neovim 0.12.5, the final
three-test CTest suite passes. The same real-key ordinary-buffer regression also
passes with an isolated Wanxiang Pure v18.0.15 directory (exit 0, explicit PASS).
The tests include forced timeout/restart and worker death; error notifications in
that test output are expected. Lua formatting/lint checks pass. This evidence is
headless input, not a demonstration in the user's active editor, and does not
validate AI virtual-text coexistence, ARM64 or language-model effectiveness.
Blink-specific evidence follows below.


## Optional Blink adapter

Tested against blink.cmp **v1.10.2**, commit
`78336bc89ee5365633bcf754d93df01678b5c08f`, with its Lua fuzzy matcher. Native UI
remains the default and does not require Blink. For Blink, set `ui = "blink"` in
rime_bridge.setup and wrap the complete Blink options **before** Blink setup:

```lua
require("rime_bridge").setup({
  worker = "/absolute/path/to/rime-bridge-worker",
  user_dir = "/absolute/path/to/dedicated-rime-data",
  schema = "wanxiang_pure",
  ui = "blink",
})
local opts = { fuzzy = { implementation = "lua" } } -- your existing Blink options
require("blink.cmp").setup(require("rime_bridge.blink").options(opts))
```

With Lazy's opts callback, return rime_bridge.blink.options(opts) after other
customizations. The helper copies options rather than mutating your input table.
Do not call Blink setup twice or use only the provider without the isolation
configuration. Unknown keymap presets are rejected rather than silently remapped.

In the enabled buffer's Insert mode, the helper reserves Blink for Rime, even
between compositions: ordinary providers, auto-insert previews, ghost text and
custom accept/snippet key chains are suppressed. Per-filetype sources and delayed
provider results are guarded as well. Disable Rime or leave its buffer to restore
normal completion. This conservative Chinese-mode boundary avoids completion
races around composition start/commit; it is not a fine-grained mixed-mode policy.

Rime candidates keep engine order, including after an existing text prefix;
Blink fuzzy matching must not reorder/filter Chinese candidates based on that
prefix. Selecting a candidate, including through Blink's source execute API,
sends its page index to the worker. The adapter never invokes Blink's default
text insertion. Session/generation/revision checks reject stale candidate items.
Ctrl-n/p navigate Rime, Ctrl-y accepts, Ctrl-e cancels, and Space/Enter/digits
retain the normal input adapter's behavior. Source refresh uses public Blink
show/select APIs; no private runtime configuration or event emitters are patched.

This isolates Blink providers and wrapped key chains, **not arbitrary external
plugins**. Minuet has a separate opt-in adapter below. The target LazyVim config
passes a separate headless Pure integration test, including shared Ctrl-y,
switching Minuet presets, native snippets and returning to ordinary completion.
This is not a visible live-session demonstration.

### Blink tests

Provide an existing pinned checkout; builds/tests never download it:

```sh
cmake -S . -B build -DRIME_BRIDGE_BLINK_DIR=/absolute/path/to/blink.cmp
ctest --test-dir build --output-on-failure
```

The five-test suite passes on the host, adding full Blink real-key regression and
isolation tests. The latter starts a delayed foreign provider, checks prefix and
engine ordering, freezes the worker to prove Blink cannot insert the label before
an engine commit, rejects stale items and verifies ordinary completion restoration.
The same Blink real-key regression also passes against isolated Wanxiang Pure
v18.0.15 (exit 0, explicit PASS). These are headless tests, not a live-session demo.

References: [public source interface](https://cmp.saghen.dev/development/source-boilerplate),
[configuration](https://cmp.saghen.dev/configuration/reference), and the
[tested public API implementation](https://github.com/Saghen/blink.cmp/blob/78336bc89ee5365633bcf754d93df01678b5c08f/lua/blink/cmp/init.lua).

## Optional Minuet virtual-text isolation

The tested dependency is the **vex9z7/minuet-ai.nvim fork**, commit
`c2740cd` (after `0021d27`), not an arbitrary upstream version. That fork checks
predicates when requesting, receiving, rendering and accepting results, and
invalidates queued/streaming results on dismissal. Without those changes, a
predicate only at request time cannot prevent late results from leaking.

Wrap the full Minuet options before its single setup call:

```lua
require("minuet").setup(require("rime_bridge.minuet").options(minuet_opts))
```

Existing predicates, including explicit preset predicate lists, are preserved. Rime activation dismisses already-loaded
Minuet virtual text immediately, including during worker startup, without
lazy-loading Minuet or modifying its internal state. Only the enabled/pending
target buffer is reserved; an aborted startup after switching buffers releases
ownership. Disabling Rime permits new AI requests; cancelled old results remain
invalid. No AI network request is sent by this plugin.

To run the optional real-worker integration test with an existing fixed checkout:

```sh
cmake -S . -B build -DRIME_BRIDGE_MINUET_DIR=/absolute/path/to/minuet-ai.nvim
ctest --test-dir build --output-on-failure
```

The six-test suite (Blink and Minuet paths supplied) passes on the measured host.
The Minuet test uses actual nvim_input for `nihao → 你好`, real Minuet virtual text
and a stub **network provider only**. It verifies existing/late AI suppression,
isolation between compositions and AI recovery after disabling Rime. The fork's
66 existing tests and separate real-key cancellation regression also pass. The
new cancellation test fails against the pre-fix virtualtext.lua from `cc0346c`;
this is a verified regression test, not merely a green smoke test.

## Reproducible Pure data preparation

Install build/runtime packages yourself (Ubuntu baseline above). For the tested
Pure variant, librime-lua is **not required**: it has no Lua engine components.
Do not confuse Rime's native `script_translator` with a Lua translator.

Prepare a **new, dedicated** directory; never unpack over existing personal data.
For this configuration's default location, use `$HOME/.local/share/nvim/rime-bridge`
(or your XDG/Neovim data directory). For an existing directory, back it up and
review upstream/custom changes manually rather than running this fresh-install
example:

```sh
data="$HOME/.local/share/nvim/rime-bridge"
test ! -e "$data" || { echo "Refusing to replace existing data"; exit 1; }
download="$(mktemp -d)"
curl --fail --location --retry 3 -o "$download/pure.zip" \
  https://github.com/amzxyz/rime-wanxiang/releases/download/v18.0.15/rime-wanxiang-pure.zip
echo "582b6842ea6d4aebb5f6863df309f550a7104eb01fcfa6ae8d4dea88c3c2b31b  $download/pure.zip" | sha256sum --check
mkdir -p "$data"
unzip -q "$download/pure.zip" -d "$data"
```

The measured test directory also contains the upstream
`wanxiang-lts-zh-hans.gram` resource from
[the LTS model release](https://github.com/amzxyz/RIME-LMDG/releases/tag/LTS).
The measured asset SHA-256 is
`20b425ef65151c418248d2e9610fa5ebccddb846510c8282c8d25b5f108e5a3a`.
The LTS asset URL is mutable: verify the digest before using it for the same
baseline; a different digest requires a new integration run, not blind acceptance.
Its presence is not proof that the old system engine activates the model.

After configuring user_dir, explicitly run RimeDeploy, inspect RimeInfo, and
then enable Rime in an ordinary buffer and type `nihao`, Space. Check `你好`
is committed once. Keep source YAML/custom patches/dictionaries under your own
management; build caches and learned userdb belong to that dedicated directory.
The plugin does not download/update these resources for you.

See [source-release checklist and tested versions](doc/release.md).
