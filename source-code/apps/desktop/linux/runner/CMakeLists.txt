cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "system_tray.cc"
  "window_channel_handler.cc"
  "quick_search_panel.cc"
  "ssh_agent_server.cc"
  "ssh_agent_ed25519.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
target_compile_definitions(${BINARY_NAME} PRIVATE "APPLICATION_ID=\"${APPLICATION_ID}\"")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# OpenSSL provides Ed25519 + ECDSA-P256 signing for the SSH agent. libcrypto
# is part of the base install on every supported distro. We use the CMake
# bundled FindOpenSSL module instead of pkg-config so the build also works
# under the Flutter snap, whose pkg-config path doesn't include the host's
# /usr/lib/.../pkgconfig.
find_package(OpenSSL REQUIRED)
target_link_libraries(${BINARY_NAME} PRIVATE OpenSSL::Crypto)

# Optional Ayatana AppIndicator support for the system tray. When the host
# system provides libayatana-appindicator3, link against it and define
# HAVE_APPINDICATOR so SystemTray uses the modern indicator API. Otherwise
# fall back to GtkStatusIcon, which still works on most desktops.
pkg_check_modules(AYATANA_APPINDICATOR IMPORTED_TARGET ayatana-appindicator3-0.1)
if(AYATANA_APPINDICATOR_FOUND)
  target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::AYATANA_APPINDICATOR)
  target_compile_definitions(${BINARY_NAME} PRIVATE "HAVE_APPINDICATOR")
endif()

# Workaround for the Flutter snap shipping an older GLib than the host system.
# Some host shared libraries (libsecret, libayatana-*) reference newer GLib
# symbols (e.g. g_task_set_static_name) that the snap's bundled GLib does not
# expose. They resolve correctly at runtime against the system loader, so we
# only need to relax the link-time check.
target_link_options(${BINARY_NAME} PRIVATE "-Wl,--unresolved-symbols=ignore-in-shared-libs")

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)
