# rime-bridge.nvim

**v0.1.0 — MIT-licensed source release.**
This independent source tree starts with a system-Rime native worker and protocol
regressions, Lua lifecycle/health checks, opt-in ordinary-buffer input and a Blink
adapter. Real LazyVim integration has been tested separately. setup does not
create a scratch buffer or automatically enable input. See [release notes](CHANGELOG.md)
and [dependency/data boundaries](NOTICE.md).

## Install with lazy.nvim / LazyVim

Copy [examples/lazy.lua](examples/lazy.lua) into your plugin-spec directory. It
contains the CMake build hook and the tested Blink wrapper; merge its Blink opts
callback with your existing configuration rather than calling setup twice. The
example pins the tested Blink version and uses its Lua matcher. The management
regression loads this example and checks its provider/build configuration.

Install the system build packages listed below yourself, then let the plugin
manager run the build hook. The default dedicated data directory is
`vim.fn.stdpath("data") .. "/rime-bridge"`; no directory or input mappings are
created by setup. Prepare [scheme data](#reproducible-pure-data-preparation), run
`:RimeDeploy`, wait for completion, then `:RimeCheck` and `<leader>uR` to enable.
The plugin never downloads dictionaries, changes system packages or enables
Chinese input automatically.

Worker discovery, in order:

1. Explicit `worker = "..."` (never silently replaced if missing/broken).
2. This plugin's `build/rime-bridge-worker`.
3. `rime-bridge-worker` on PATH.

Discovery runs again at startup, so a build completed after setup is recognized.
A present but non-executable plugin-local worker is reported, not silently
replaced by an older PATH version. `:RimeInfo` reports the selected path/origin;
`:checkhealth rime_bridge` gives the rebuild command and missing-tool hints.
Use `user_dir`, `schema`, `shared_dir`, `worker` and `lua_plugin` overrides only
when needed. For standalone native UI, `require("rime_bridge").setup()` suffices
once the worker and Pure data are prepared; Blink is optional.

## Build the worker

Linux, a C++17 compiler, CMake >=3.16 and system librime development files are
required. Install system dependencies yourself (Ubuntu: `g++ make cmake librime-dev`).
Engine initialization also needs a shared Rime data directory (Ubuntu:
`librime-data` provides `/usr/share/rime-data`), or an explicit prepared `shared_dir`.
CMake never downloads or builds librime.

CMake FetchContent downloads nlohmann-json **3.12.0** into `build/_deps/`, with a
fixed SHA256 and HTTPS certificate verification. No system JSON package is needed.
The first configure needs network access and trusted CA certificates. JSON is
header-only: its code is compiled into the worker, not loaded as a runtime library.
Tests additionally need Python3 and a Rime shared-data directory at
`/usr/share/rime-data` with `luna_pinyin_simp` (Ubuntu:
`python3 librime-data rime-data-luna-pinyin`).

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
cmake --install build --prefix "$HOME/.local"
```

This installs `rime-bridge-worker` in the selected prefix's bin directory, not
librime, JSON headers or Lua files. The JSON license is installed under
`share/licenses/rime-bridge/`. Neovim plugin managers install the Lua modules;
CMake does not install them. Use `-DBUILD_TESTING=OFF` for builds without the
Python test runner.
A local build is not a universally portable binary.

## C++ project layout

- `CMakeLists.txt`: project entry point and CTest registration.
- `cmake/Dependencies.cmake`: system Rime target and pinned JSON acquisition.
- `src/`: worker target and implementation; compile/link requirements are target-local.
- `tests/`: protocol and editor regressions; `lua/`: Neovim modules.
- `build/`: ignored generated files, downloaded dependency sources and worker binary.

The worker remains at `build/rime-bridge-worker`, preserving plugin-manager build
commands. There is no public C++ API, so no public `include/` tree is needed.
For a fresh offline build, unpack the pinned JSON archive in advance and configure
with `-DFETCHCONTENT_SOURCE_DIR_NLOHMANN_JSON=/absolute/path/to/json` (the directory
containing its `CMakeLists.txt` and `LICENSE.MIT`). Verify the archive against the
SHA256 in `cmake/Dependencies.cmake`; this source override bypasses downloading and
its automatic hash check. Update the version and hash together when upgrading JSON,
then run the build, CTest and isolated-prefix install checks.

## Build CI

`.github/workflows/build.yml` independently checks the worker on Linux x86_64 and ARM64 in
clean Ubuntu 22.04 and 24.04 containers for main pushes, pull requests and manual
runs. It installs only build dependencies (no system JSON package or editor),
then checks FetchContent configure/build, a disconnected build using pre-fetched
sources, isolated installation, the JSON license and an installed-worker protocol
smoke test. `BUILD_TESTING=OFF` keeps this gate independent of Neovim, Blink,
Minuet and scheme fixtures. The existing `ci.yml` retains the full integration
regressions on both native architectures. These checks do not certify portable
binaries or arbitrary schemes.

## Checks, deployment and status

- `:checkhealth rime_bridge` is passive: worker/build prerequisites, directory
  permissions, scheme-file hints and the last runtime result. It starts no worker.
- `:RimeInfo` shows resolved configuration, state and read-only scheme hints.
- `:RimeCheck` explicitly starts/initializes the worker if necessary and checks
  protocol compatibility and the engine schema list. Initialization can create
  the configured directory and acquire its lock. It does **not** deploy data,
  select a schema or enable input; availability in the list is not proof of
  working dictionaries, candidates or model quality.
- `:RimeDeploy` disables input, deploys through librime, then verifies that the
  configured schema appears in the engine list. Start/success/failure are reported.
  Duplicate deploy requests and enable attempts during deployment do not capture
  input or start another deployment. Re-enable explicitly after success.
- `:RimeStop` releases input mappings and requests worker shutdown (including its
  normal learning-data flush). `:RimeDisable` only disables input, retaining the worker.

`require("rime_bridge").status()` retains its engine `phase` and adds `mode`
(`off`, `starting`, `on`, `deploying`, `error`), `active` for the current buffer and
`buffer` for the enabled/pending target. The existing `enabled` field means there
is an attached input session, not necessarily in the current buffer. Deployment
state is `running`, `succeeded` or `failed` when available. Failures carry recovery
`advice`; stderr remains reduced to privacy-safe categories, never raw input logs.

For a statusline component, use `require("rime_bridge").statusline` (a function)
or `%{v:lua.require('rime_bridge').statusline()}` in a native statusline. It returns
fixed labels such as `Rime:on`; it neither reads scheme files nor starts a process.
No statusline, color scheme, new preedit UI or notification styling is installed.

File hints distinguish missing sources, missing compiled schemas and potentially
stale direct schema/global YAML. They are advisory: included dictionaries, Lua,
conversion resources and model changes are not fully tracked. Explicitly redeploy
after updating those resources even if no stale-file warning is shown.

## Data and scope

Users own the system engine and a separate writable Rime user directory. The
first-version scheme baseline is upstream Wanxiang Pure v18.0.15; no dictionaries,
models or personal learning data are bundled. Full Wanxiang/Ice, live ARM64 input-experience evaluation
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
librime, with no private engine library bundle. JSON is fetched at build time.

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
  worker = "/absolute/path/to/rime-bridge-worker", -- optional override; local build, then PATH
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
- Printable ASCII goes to Rime; uncommitted input is kept in engine state,
  not displayed as inline virtual text or inserted into the file.
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

The original six-test suite (Blink and Minuet paths supplied) passed on the measured host.
Current CI additionally registers lua.management for installation/data/status checks.
The Minuet test uses actual nvim_input for `nihao → 你好`, real Minuet virtual text
and a stub **network provider only**. It verifies existing/late AI suppression,
isolation between compositions and AI recovery after disabling Rime. The fork's
66 existing tests and separate real-key cancellation regression also pass. The
new cancellation test fails against the pre-fix virtualtext.lua from `cc0346c`;
this is a verified regression test, not merely a green smoke test.

## Integrating existing schemes and safe updates

1. Use a **dedicated copy**, never the directory actively used by a desktop IME
   or another worker. `user_dir` is writable; `shared_dir` is the system/shared
   resource root, not a replacement for writable user data.
2. With the original writer stopped, copy the scheme's source YAML, dictionary,
   OpenCC/Lua/model resources as required by its upstream documentation. Point
   `schema` at its schema ID and include that ID in `default.custom.yaml`'s
   `patch.schema_list`. Changing the Lua option alone does not edit that list. For Pure, merge this into
   your existing patch rather than overwriting the whole file:

   ```yaml
   patch:
     schema_list:
       - schema: wanxiang_pure
   ```
3. Keep personal `*.custom.yaml` patches and learned `*.userdb` data. Do not copy
   old `build/` caches or lock files as installation inputs. Custom schemes may
   need a compatible system Lua extension; Pure does not.
4. Run `:RimeDeploy`, inspect `:RimeInfo` / `:RimeCheck`, then verify actual typed
   candidates. The plugin does not rewrite source configuration or supply missing
   scheme components. A schema-list check does not certify arbitrary schemes.

Before updates, stop input and the worker (`:RimeStop`, or exit Neovim), wait for
worker exit/flush and ensure no other writer is using the directory. Back up the
**whole dedicated directory**, including custom patches and learned databases.
Download new upstream resources into a separate staging directory, review/diff
changes, then merge only intended upstream files. Never unpack a release over
personal data or blindly delete `*.userdb`, patches or locks. Explicitly redeploy
and test input after the merge. To roll back, stop all writers again and restore
the complete backup, not just old caches. Source/patch preservation across repeated
explicit deployment is covered by the runtime tests; userdb learning/persistence
is covered by the worker protocol tests.

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
(
set -eu
data="$HOME/.local/share/nvim/rime-bridge"
test ! -e "$data" || { echo "Refusing to replace existing data"; exit 1; }
download="$(mktemp -d)"
curl --fail --location --retry 3 -o "$download/pure.zip" \
  https://github.com/amzxyz/rime-wanxiang/releases/download/v18.0.15/rime-wanxiang-pure.zip
echo "582b6842ea6d4aebb5f6863df309f550a7104eb01fcfa6ae8d4dea88c3c2b31b  $download/pure.zip" | sha256sum --check
mkdir -p "$(dirname "$data")"
mkdir "$data" # Fail if another process created it while downloading; never merge implicitly.
unzip -q "$download/pure.zip" -d "$data"
)
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
