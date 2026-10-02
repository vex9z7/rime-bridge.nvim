cmake_minimum_required(VERSION 3.16)
project(rime_bridge VERSION 0.1.0 LANGUAGES CXX)

include(GNUInstallDirs)
include(CTest)

include(cmake/Dependencies.cmake)
add_subdirectory(src)

if(BUILD_TESTING)
  find_package(Python3 COMPONENTS Interpreter REQUIRED)
  add_test(NAME worker.protocol COMMAND "${Python3_EXECUTABLE}"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_protocol.py" "$<TARGET_FILE:rime-bridge-worker>" --no-lua)
  set_tests_properties(worker.protocol PROPERTIES TIMEOUT 120)
endif()

if(BUILD_TESTING)
  find_program(NVIM_EXECUTABLE NAMES nvim)
  if(NVIM_EXECUTABLE)
    add_test(NAME lua.foundation COMMAND "${CMAKE_COMMAND}" -E env
      "RIME_BRIDGE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}"
      "RIME_BRIDGE_WORKER=$<TARGET_FILE:rime-bridge-worker>"
      "${NVIM_EXECUTABLE}" --headless -u NONE -i NONE
      -c "lua dofile('${CMAKE_CURRENT_SOURCE_DIR}/tests/test_lua.lua')")
    set_tests_properties(lua.foundation PROPERTIES TIMEOUT 30)
  else()
    message(STATUS "Neovim not found: lua.foundation test unavailable; only native tests will run")
  endif()
endif()

if(BUILD_TESTING AND NVIM_EXECUTABLE)
  add_test(NAME lua.input COMMAND "${CMAKE_COMMAND}" -E env
    "RIME_BRIDGE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}"
    "RIME_BRIDGE_WORKER=$<TARGET_FILE:rime-bridge-worker>"
    "${NVIM_EXECUTABLE}" --headless -u NONE -i NONE
    -c "lua dofile('${CMAKE_CURRENT_SOURCE_DIR}/tests/test_input.lua')")
  set_tests_properties(lua.input PROPERTIES TIMEOUT 60)
endif()

set(RIME_BRIDGE_BLINK_DIR "" CACHE PATH "Existing blink.cmp checkout for optional integration tests (never downloaded)")
if(BUILD_TESTING AND NVIM_EXECUTABLE AND RIME_BRIDGE_BLINK_DIR)
  if(NOT EXISTS "${RIME_BRIDGE_BLINK_DIR}/lua/blink/cmp/init.lua")
    message(FATAL_ERROR "RIME_BRIDGE_BLINK_DIR must point to an existing blink.cmp checkout")
  endif()
  foreach(suite IN ITEMS input isolation)
    set(test_file test_input.lua)
    if(suite STREQUAL "isolation")
      set(test_file test_blink.lua)
    endif()
    add_test(NAME lua.blink_${suite} COMMAND "${CMAKE_COMMAND}" -E env
      "RIME_BRIDGE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}"
      "RIME_BRIDGE_WORKER=$<TARGET_FILE:rime-bridge-worker>"
      "RIME_TEST_BLINK=${RIME_BRIDGE_BLINK_DIR}"
      "${NVIM_EXECUTABLE}" --headless -u NONE -i NONE
      -c "lua dofile('${CMAKE_CURRENT_SOURCE_DIR}/tests/${test_file}')")
    set_tests_properties(lua.blink_${suite} PROPERTIES TIMEOUT 60)
  endforeach()
endif()

set(RIME_BRIDGE_MINUET_DIR "" CACHE PATH "Existing Minuet checkout for optional AI isolation test (never downloaded)")
if(BUILD_TESTING AND NVIM_EXECUTABLE AND RIME_BRIDGE_MINUET_DIR)
  if(NOT EXISTS "${RIME_BRIDGE_MINUET_DIR}/lua/minuet/virtualtext.lua")
    message(FATAL_ERROR "RIME_BRIDGE_MINUET_DIR must point to an existing minuet-ai.nvim checkout")
  endif()
  add_test(NAME lua.minuet_isolation COMMAND "${CMAKE_COMMAND}" -E env
    "RIME_BRIDGE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}"
    "RIME_BRIDGE_WORKER=$<TARGET_FILE:rime-bridge-worker>"
    "RIME_TEST_MINUET=${RIME_BRIDGE_MINUET_DIR}"
    "${NVIM_EXECUTABLE}" --headless -u NONE -i NONE
    -c "lua dofile('${CMAKE_CURRENT_SOURCE_DIR}/tests/test_minuet.lua')")
  set_tests_properties(lua.minuet_isolation PROPERTIES TIMEOUT 30)
endif()
