# rime-bridge.nvim

**Production implementation in progress, not a released input-method plugin.**
This independent source tree starts with a system-Rime native worker and protocol
regressions and a Lua lifecycle/health foundation. Ordinary-buffer input, Blink
integration and release acceptance are pending. It does not create a scratch buffer or enable input in
any existing Neovim configuration.

## Build the worker

Linux, a C++17 compiler, CMake >=3.16, system librime development files and
nlohmann-json headers/CMake package are required. Tests additionally need Python3
and a Rime shared-data directory at /usr/share/rime-data. Ubuntu package names:
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


## Lua foundation (not input activation yet)

Neovim >=0.10 is required; the actual tested host is Neovim 0.12.5.
Put this repository on runtimepath through your plugin manager, then:

```lua
require("rime_bridge").setup({
  worker = "/absolute/path/to/rime-bridge-worker", -- defaults to PATH lookup
  user_dir = "/absolute/path/to/dedicated-rime-data",
  schema = "wanxiang",
})
```

setup does not spawn a process, create buffers, deploy data or install mappings.
For backend diagnostics only, call `require("rime_bridge").start()` explicitly;
this initializes the engine, checks protocol 1 and reports `initialized`, not
input-ready. It does not select/deploy a schema. `:RimeInfo` reports state;
`:checkhealth rime_bridge` inspects configuration/runtime without launching a worker.
Use `require("rime_bridge").stop()` to close it; editor exit closes it as well.
Engine stderr is discarded by the default Lua client to avoid retaining input
content; more actionable privacy-safe engine diagnostics remain a future task.

CTest adds lua.foundation when Neovim is found (or specified with
-DNVIM_EXECUTABLE=/path/to/nvim); absence is reported, not counted as a pass.
Both worker.protocol and lua.foundation passed on the actual host. The latter
checks setup isolation, incompatible protocol rejection, real worker handshake,
shutdown, configuration isolation and missing-executable errors. This is not an
editor key/normal-buffer acceptance test.

Repeatability check: after making edited test-fixture mtimes distinct for the old
engine's deployment cache, `ctest --repeat until-fail:5` passed both suites five
times on the host (exit 0). An earlier rapid-edit run missed the newly added
schema; this fixture correction does not claim a production deployment-cache fix.
