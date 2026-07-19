cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "quick_blue_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

find_program(NUGET_EXE NAMES nuget)
if(NOT NUGET_EXE)
	message("NUGET.EXE not found.")
	message(FATAL_ERROR "Please install this executable, and run CMake again.")
endif()

exec_program(${NUGET_EXE}
    ARGS install "Microsoft.Windows.CppWinRT" -Version 2.0.250303.1 -ExcludeVersion -OutputDirectory ${CMAKE_BINARY_DIR}/packages)

add_library(${PLUGIN_NAME} SHARED
  "messages.g.cpp"
  "messages.g.h"
  "${PLUGIN_NAME}.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  VS_PROJECT_IMPORT ${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.CppWinRT/build/native/Microsoft.Windows.CppWinRT.props
)

target_link_libraries(${PLUGIN_NAME} PRIVATE ${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.CppWinRT/build/native/Microsoft.Windows.CppWinRT.targets)

target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL
  _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

if(include_quick_blue_tests)
  enable_testing()
  add_executable(${PROJECT_NAME}_connection_ownership_test
    "test/connection_ownership_test.cpp"
  )
  apply_standard_settings(${PROJECT_NAME}_connection_ownership_test)
  add_test(
    NAME ${PROJECT_NAME}_connection_ownership_test
    COMMAND ${PROJECT_NAME}_connection_ownership_test
  )
endif()

# List of absolute paths to libraries that should be bundled with the plugin
set(quick_blue_windows_bundled_libraries
  ""
  PARENT_SCOPE
)
