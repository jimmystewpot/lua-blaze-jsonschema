cmake_minimum_required(VERSION 3.23)

project(luablaze)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(LUABLAZE_INIT_SUBMODULES "Initialize git submodules during CMake configure" ON)
option(LUABLAZE_REQUIRE_TEST_SUITE "Require the JSON-Schema-Test-Suite submodule to be present" ON)

if(LUABLAZE_INIT_SUBMODULES)
  find_package(Git QUIET)
  if(GIT_FOUND)
    execute_process(
      COMMAND ${GIT_EXECUTABLE} submodule update --init --recursive
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
      RESULT_VARIABLE LUABLAZE_GIT_SUBMOD_RESULT
    )
    if(NOT LUABLAZE_GIT_SUBMOD_RESULT EQUAL 0)
      message(FATAL_ERROR "git submodule update --init --recursive failed with exit code ${LUABLAZE_GIT_SUBMOD_RESULT}")
    endif()
  endif()
endif()

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/deps/blaze/CMakeLists.txt")
  message(FATAL_ERROR "Blaze submodule not present at deps/blaze. Run: git submodule update --init --recursive")
endif()

if(LUABLAZE_REQUIRE_TEST_SUITE AND NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/deps/json-schema-test-suite/tests/draft7")
  message(FATAL_ERROR "JSON-Schema-Test-Suite submodule not present at deps/json-schema-test-suite. Run: git submodule update --init --recursive")
endif()

add_subdirectory(deps/blaze)

if(DEFINED LUA_INCLUDE_DIR AND DEFINED LUA_LIBRARY)
  set(LUA_LIBRARIES ${LUA_LIBRARY})
else()
  find_package(Lua 5.2 REQUIRED)
  if(DEFINED LUA_VERSION_STRING AND LUA_VERSION_STRING VERSION_LESS "5.2")
    message(FATAL_ERROR "Lua >= 5.2 is required, but found ${LUA_VERSION_STRING}")
  endif()
endif()

# Allow override with cache variable or environment variable
set(LUA_INCDIR_OVERRIDE " " CACHE STRING "Override for Lua include directory")
if(NOT "$ENV{LUA_INCDIR}" STREQUAL "")
  set(LUA_INCLUDE_DIR $ENV{LUA_INCDIR})
elseif(NOT "${LUA_INCDIR_OVERRIDE}" STREQUAL " ")
  set(LUA_INCLUDE_DIR ${LUA_INCDIR_OVERRIDE})
else()
  # Prefer CMake's discovered include dir, but ensure it contains lua.hpp.
  # If it does not, fall back to a versioned include directory.
  if(DEFINED LUA_INCLUDE_DIR AND EXISTS "${LUA_INCLUDE_DIR}/lua.hpp")
    # Keep the discovered include directory.
  elseif(DEFINED LUA_VERSION_MAJOR AND DEFINED LUA_VERSION_MINOR)
    set(LUA_INCLUDE_DIR "/usr/include/lua${LUA_VERSION_MAJOR}.${LUA_VERSION_MINOR}")
  else()
    set(LUA_INCLUDE_DIR "/usr/include/lua5.2") # Fallback to min version, adjustable
  endif()
endif()

# Ensure the include dir is set and exists
if(NOT EXISTS "${LUA_INCLUDE_DIR}/lua.hpp")
  message(FATAL_ERROR "Lua header not found in ${LUA_INCLUDE_DIR}. Set LUA_INCDIR or LUA_INCDIR_OVERRIDE.")
endif()

add_library(blaze MODULE
  src/luablaze.cpp
  src/luablaze.h
)

set_target_properties(blaze PROPERTIES
  PREFIX ""
  OUTPUT_NAME "luablaze"
)

# Platform-specific settings
if(WIN32)
  # Windows: Lua C modules use .dll extension
  set_target_properties(blaze PROPERTIES SUFFIX ".dll")
  # MSVC-specific flags
  if(MSVC)
    target_compile_options(blaze PRIVATE /utf-8)
    # MSVC optimizations for Release builds
    target_compile_options(blaze PRIVATE
      $<$<CONFIG:Release>:/O2> # Full optimization
      $<$<CONFIG:Release>:/Ob2> # Inline any suitable function
      $<$<CONFIG:Release>:/Oi> # Enable intrinsic functions
      $<$<CONFIG:Release>:/Ot> # Favor fast code
      $<$<CONFIG:Release>:/GL> # Whole program optimization
      $<$<CONFIG:Release>:/DNDEBUG> # Disable assertions
    )
    target_link_options(blaze PRIVATE
      $<$<CONFIG:Release>:/LTCG> # Link-time code generation
    )
  endif()
elseif(APPLE)
  # macOS: Lua C modules use .so extension (not .dylib)
  set_target_properties(blaze PROPERTIES SUFFIX ".so")
else()
  # Linux: .so is the default, but be explicit
  set_target_properties(blaze PROPERTIES SUFFIX ".so")
endif()

# GCC/Clang optimizations (Linux, macOS, MinGW)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(blaze PRIVATE
    $<$<CONFIG:Release>:-O2> # Aggressive optimization
    $<$<CONFIG:Release>:-DNDEBUG> # Disable assertions
    $<$<CONFIG:Release>:-flto=auto> # Link-time optimization
    $<$<CONFIG:Release>:-fomit-frame-pointer> # Free up a register
  )
  target_link_options(blaze PRIVATE
    $<$<CONFIG:Release>:-flto=auto> # LTO at link time
  )
endif()

# Symbol visibility for shared library exports
set_target_properties(blaze PROPERTIES
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

target_include_directories(blaze PRIVATE ${LUA_INCLUDE_DIR})

target_link_libraries(blaze PRIVATE
  ${LUA_LIBRARIES}
  sourcemeta::blaze::compiler
  sourcemeta::blaze::evaluator
  sourcemeta::blaze::output
  sourcemeta::blaze::linter
)
