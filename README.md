# rime-bridge.nvim

**Production implementation in progress, not a released input-method plugin.**
This independent source tree starts with a system-Rime native worker and protocol
regressions, Lua lifecycle/health checks and opt-in ordinary-buffer input. Blink
integration and full release acceptance are pending. It does not create a scratch buffer or enable input in
any existing Neovim configuration.

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
A license has not yet been selected; no new license grant is implied by extraction.

## Foundation verification

On 2026-10-01, configure, compile, CTest (worker.protocol) and installation to an
isolated local prefix passed on Ubuntu 22.04 x86_64 with GCC 11.4, system librime
1.7.3 and nlohmann-json 3.10.5. No system packages were installed/upgraded.
The development container without librime-dev separately exercises the actionable
configure-time missing-dependency error. Normal-buffer/real-key production tests
have not yet run; historical scratch results are not substituted for those gates.


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
It does not yet cooperate with Blink, snippets or AI completions; use an isolated
configuration with those disabled for this stage. No default F6 or global input
mapping is installed. Do not enable by default in the normal configuration yet.

start() initializes only the backend, without selecting/deploying a schema or
capturing keys. stop() detaches input and closes the backend; disable() keeps the
worker available. Exiting Neovim closes it. `:checkhealth rime_bridge` checks
configuration/runtime without starting it. Worker errors/timeouts restore maps,
remove UI and notify; inspect `:RimeInfo` and explicitly re-enable after fixing the
cause. Uncertain pending input is not replayed after failure to avoid duplication.
Engine stderr is not retained by default; complete component diagnostics remain pending.

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
validate Blink/AI coexistence, ARM64 or language-model effectiveness.
