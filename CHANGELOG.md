# Changelog

## Unreleased

- Require nlohmann-json >=3.6.0, matching the worker API usage; remove an
  unused Rime API requirement and share engine/session and schema-list cleanup.
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
