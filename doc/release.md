# Source-release readiness

This is a source-only Linux x86_64 release path. Do not publish a worker binary
as portable across distributions: users compile against their installed librime.
Version Lua and the worker together; protocol mismatch fails closed.

## Measured baseline

| Component | Measured |
| --- | --- |
| Host | Ubuntu 22.04.5, x86_64, glibc 2.35 |
| Compiler / build | GCC 11.4, CMake, Release build and isolated-prefix install |
| Engine | system librime 1.7.3+dfsg3-2build2 |
| JSON build dependency | nlohmann-json 3.10.5 |
| Neovim | 0.12.5 host; official 0.11.5 Linux x86_64 archive |
| Blink | v1.10.2 / 78336bc89ee5365633bcf754d93df01678b5c08f, Lua matcher |
| Minuet (optional) | vex9z7 fork / c2740cd0aef0319c5720c9fd03cedcdff7faa2c1 |
| Scheme | Wanxiang Pure v18.0.15, user-installed, not bundled |

Neovim 0.11.5 passes all six CTest suites, the dependency's 66 tests and its
real-key virtual-text cancellation test. This was reproduced on the actual host
without changing system packages. The separate host 0.12.5/Pure evidence is in
README. No ARM64 execution, arbitrary scheme compatibility or language-model
effectiveness is claimed. Pure uses native components; this baseline does not
require librime-lua. A user scheme with Lua components requires a compatible
system Lua extension and may require an explicit lua_plugin path.

## CI

.github/workflows/ci.yml builds on Ubuntu 22.04 x86_64, installing system
packages **on the ephemeral CI runner only**. Action/dependency commits and the
Neovim download digest are fixed. It runs six fixed-fixture editor/protocol tests,
Minuet's tests and isolated-prefix install, retaining CTest output for seven days.
AI network calls are replaced only in tests. There are no user data or model
downloads in CI. CMake itself never installs/downloads dependencies.

A local reproduction is not a hosted CI result. Record the hosted run URL and
conclusion before tagging. Large Pure integration remains an explicit, isolated
manual release gate; deterministic CI fixtures do not substitute for that test.

## Checklist before tagging v0.1.0

- [x] Native CMake build/test/install against system dependencies.
- [x] Fixed fixtures and real-key tests, including faults, cancellation and AI races.
- [x] Pinned Pure real-key baseline on host x86_64.
- [x] Document data ownership, explicit deploy and source-only distribution.
- [x] Hosted CI green at ee4f6bd: [run 36837255994](https://github.com/vex9z7/rime-bridge.nvim/actions/runs/36837255994).
      Re-run at the final release commit before tagging.
- [x] Actual LazyVim configuration with Pure, shared Blink/Minuet keys, AI preset
      switching, late responses and native snippet coexistence passes headlessly.
      Live-session visible typing is not claimed.
- [x] Owner approved MIT for the original plugin source on 2026-10-01.
- [x] Added MIT LICENSE and dependency/data NOTICE.md; source archive excludes scheme,
      dictionary/model, system libraries or learned user data in source archive.
- [x] README and CHANGELOG describe v0.1.0 and its measured scope.

Publishing procedure: verify hosted CI succeeds at the exact final source commit,
then create and push the annotated v0.1.0 source tag. Record that commit, CI run
and remote tag verification in the parent implementation evidence; do not advance
a tag to another commit after publishing it.

MIT was explicitly selected by the owner; see LICENSE and NOTICE.md.
The project links user-installed librime and nlohmann-json; their own licenses
still apply. Wanxiang dictionaries/models remain separate upstream downloads
under their upstream terms, not assets redistributed by this plugin. Blink and
Minuet are optional dependencies, not copied into the source distribution.
