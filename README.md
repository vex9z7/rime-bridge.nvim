# rime-input.nvim

**Production implementation in progress, not a released input-method plugin.**
This independent source tree starts with a system-Rime native worker and protocol
regressions. Lua setup, ordinary-buffer input, Blink integration and release
acceptance are pending. It does not create a scratch buffer or enable input in
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

This installs `rime-input-worker` in the selected prefix's bin directory, not
librime or Lua files. Neovim plugin managers will install Lua when that layer is
implemented. Use `-DBUILD_TESTING=OFF` for builds without the Python test runner.
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
