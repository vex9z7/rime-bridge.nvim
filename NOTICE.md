# Dependency and data boundaries

Original rime-bridge.nvim source is licensed under the MIT License in LICENSE,
as approved by the repository owner. The worker/protocol foundation originated
in the owner's earlier PoC; historical source provenance is recorded in README.

Dependencies retain their own licenses. This source repository does not vendor
librime, nlohmann-json, Blink or Minuet. CMake uses user-installed librime development
headers/libraries and fetches pinned nlohmann-json sources into the build tree.
The optional editor integrations load separately installed plugins. A locally compiled worker can contain code from header dependencies;
the plugin's MIT grant does not replace their applicable notices or terms.
The fetched JSON sources retain LICENSE.MIT; installation copies it to
`share/licenses/rime-bridge/nlohmann-json-LICENSE.MIT` inside the install prefix.

Wanxiang scheme files, dictionaries, conversion resources and models are
separate upstream downloads, not part of this source distribution. User custom
patches and learned databases are not shipped. Consult the respective upstream
projects for the terms of their installed/downloaded versions:

- https://github.com/rime/librime
- https://github.com/nlohmann/json
- https://github.com/Saghen/blink.cmp
- https://github.com/vex9z7/minuet-ai.nvim
- https://github.com/amzxyz/rime-wanxiang
- https://github.com/amzxyz/RIME-LMDG

Release artifacts are source-only; no system library bundle, compiled worker,
large dictionary/model or personal input data is published by this project.
