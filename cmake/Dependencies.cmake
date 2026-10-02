# The engine remains a user-managed system dependency.
find_path(RIME_INCLUDE_DIR NAMES rime_api.h)
find_library(RIME_LIBRARY NAMES rime)
if(NOT RIME_INCLUDE_DIR OR NOT RIME_LIBRARY)
  message(FATAL_ERROR "System librime development files missing. Install the Rime development package (Ubuntu: librime-dev); librime is never downloaded or built here.")
endif()
add_library(Rime::Rime UNKNOWN IMPORTED)
set_target_properties(Rime::Rime PROPERTIES
  IMPORTED_LOCATION "${RIME_LIBRARY}"
  INTERFACE_INCLUDE_DIRECTORIES "${RIME_INCLUDE_DIR}")
mark_as_advanced(RIME_INCLUDE_DIR RIME_LIBRARY)

include(FetchContent)
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()
set(JSON_BuildTests OFF)
set(JSON_Install OFF)
FetchContent_Declare(nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
  URL_HASH SHA256=42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa
  TLS_VERIFY TRUE)
FetchContent_MakeAvailable(nlohmann_json)

# Header-only code is compiled into the worker; preserve its license on install.
install(FILES "${nlohmann_json_SOURCE_DIR}/LICENSE.MIT"
  DESTINATION "${CMAKE_INSTALL_DATADIR}/licenses/rime-bridge"
  RENAME nlohmann-json-LICENSE.MIT)
