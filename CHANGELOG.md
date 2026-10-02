# Changelog

## Unreleased

- Discover the plugin-local worker before PATH, preserve explicit overrides and
  default to a dedicated Neovim data directory; add a tested Lazy/Blink example.
- Add passive scheme/deployment hints, explicit RimeCheck and RimeStop commands,
  verified deployment completion and protection against concurrent activation.
- Add buffer-aware status/statusline fields and actionable health/recovery advice,
  retaining opt-in input, explicit deployment and privacy-safe diagnostics.

- Run native Linux x86_64 and ARM64 build/install checks on Ubuntu 22.04/24.04
  and full editor/protocol regressions on Ubuntu 22.04 for both architectures.
- Explicitly install make in clean build CI containers; CMake alone does not
  provide the default Unix Makefiles build tool.

- Add an independent Ubuntu 22.04/24.04 worker build CI gate covering fetched and
  disconnected-source builds, isolated installation and protocol startup/shutdown.

- Organize C++ targets under src/ and dependency declarations under cmake/.
- Fetch pinned nlohmann-json 3.12.0 with SHA256 verification instead of requiring
  a system JSON package; retain system librime and the build-root worker path.
  Install the JSON license without installing its headers or CMake package.
- Remove an unused Rime API requirement and share engine/session and schema-list cleanup.
- Reject malformed protocol input without echoing JSON payloads; validate the
  Lua requirement before initialization side effects.

- Remove inline pinyin preedit rendering; retain engine composition state,
  candidate menus, cancellation and commit behavior.

## 0.1.0 — 2026-10-01

- System-linked C++ worker with CMake build/install and versioned stdio protocol.
- Opt-in ordinary-buffer input, preedit/candidates, exactly-once commit and
  cancellation/recovery across editor transitions and worker failures.
- Optional Blink candidate integration and Minuet virtual-text isolation,
  including late streaming responses and provider preset switches.
- Explicit user-data deployment, single-writer protection and bounded,
  privacy-safe diagnostic categories.
- Tested Linux x86_64 / Ubuntu 22.04 / librime 1.7.3 baseline, Wanxiang Pure
  v18.0.15 actual-key acceptance, real LazyVim/native-snippet integration,
  and pinned CI fixtures on Neovim 0.11.5.
- MIT-licensed source distribution; users install system dependencies and schemes.

ARM64 validation, broad scheme support, model effectiveness and cross-distribution
prebuilt binaries are not included. Chinese input remains off until explicitly
enabled.
