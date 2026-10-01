cmake_minimum_required(VERSION 3.16)
project(rime_input VERSION 0.1.0 LANGUAGES CXX)

include(GNUInstallDirs)
include(CTest)

find_path(RIME_INCLUDE_DIR NAMES rime_api.h)
find_library(RIME_LIBRARY NAMES rime)
if(NOT RIME_INCLUDE_DIR OR NOT RIME_LIBRARY)
  message(FATAL_ERROR "System librime development files missing. Install the Rime development package (Ubuntu: librime-dev); no dependencies are downloaded.")
endif()
find_package(nlohmann_json 3.2.0 CONFIG REQUIRED)

add_executable(rime-input-worker native/worker.cpp)
target_compile_features(rime-input-worker PRIVATE cxx_std_17)
set_target_properties(rime-input-worker PROPERTIES CXX_EXTENSIONS OFF)
target_compile_definitions(rime-input-worker PRIVATE RIME_INPUT_VERSION="${PROJECT_VERSION}")
target_include_directories(rime-input-worker PRIVATE "${RIME_INCLUDE_DIR}")
target_link_libraries(rime-input-worker PRIVATE "${RIME_LIBRARY}" nlohmann_json::nlohmann_json ${CMAKE_DL_LIBS})
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(rime-input-worker PRIVATE -Wall -Wextra -Wpedantic)
endif()
install(TARGETS rime-input-worker RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")

if(BUILD_TESTING)
  find_package(Python3 COMPONENTS Interpreter REQUIRED)
  add_test(NAME worker.protocol COMMAND "${Python3_EXECUTABLE}"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_protocol.py" "$<TARGET_FILE:rime-input-worker>" --no-lua)
  set_tests_properties(worker.protocol PROPERTIES TIMEOUT 120)
endif()

if(BUILD_TESTING)
  find_program(NVIM_EXECUTABLE NAMES nvim)
  if(NVIM_EXECUTABLE)
    add_test(NAME lua.foundation COMMAND "${CMAKE_COMMAND}" -E env
      "RIME_INPUT_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}"
      "RIME_INPUT_WORKER=$<TARGET_FILE:rime-input-worker>"
      "${NVIM_EXECUTABLE}" --headless -u NONE -i NONE
      -c "lua dofile('${CMAKE_CURRENT_SOURCE_DIR}/tests/test_lua.lua')")
    set_tests_properties(lua.foundation PROPERTIES TIMEOUT 30)
  else()
    message(STATUS "Neovim not found: lua.foundation test unavailable; only native tests will run")
  endif()
endif()
