#include "settings_window.h"

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr const char kSettingsHostChannel[] = "lumenpass/settings_host";
constexpr const char kWindowTitle[] = "LumenPass Settings";

// Sentinel Dart entrypoint argument. The GTK embedder cannot launch a custom
// entrypoint, so `main()` inspects this flag and delegates to
// `settingsMain()`. Keep in sync with lib/main.dart.
constexpr const char kSettingsWindowArg[] = "--settings-window";

}  // namespace

SettingsWindow::SettingsWindow(FlView* main_view) {
  FlEngine* engine = fl_view_get_engine(main_view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  host_channel_ = fl_method_channel_new(messenger, kSettingsHostChannel,
                                        FL_METHOD_CODEC(codec));
}

SettingsWindow::~SettingsWindow() {
  if (window_ != nullptr) {
    // Disconnect first so the destroy handler does not run on a dying object.
    g_signal_handlers_disconnect_by_data(window_, this);
    gtk_widget_destroy(window_);
    window_ = nullptr;
  }
  Teardown();
  g_clear_object(&host_channel_);
}

bool SettingsWindow::Open(const std::string& section) {
  if (!section.empty()) {
    pending_section_ = section;
  }
  const bool existed = window_ != nullptr;
  if (!EnsureCreated()) {
    return false;
  }
  if (existed && engine_ready_) {
    PushSection();
    RequestSnapshotAndPush();
  }
  gtk_widget_show(window_);
  gtk_window_deiconify(GTK_WINDOW(window_));
  gtk_window_present(GTK_WINDOW(window_));
  return true;
}

bool SettingsWindow::EnsureCreated() {
  if (window_ != nullptr) {
    return true;
  }

  // A normal, decorated, resizable top-level window with its own taskbar
  // entry — a sibling of the main window, not a dialog on top of it.
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window_), kWindowTitle);
  // Themed icon for installed builds; dev bundles fall back to the default
  // icon list registered by the main window (my_application.cc).
  GtkIconTheme* theme = gtk_icon_theme_get_default();
  if (theme != nullptr && gtk_icon_theme_has_icon(theme, "lumenpass")) {
    gtk_window_set_icon_name(GTK_WINDOW(window_), "lumenpass");
  }
  gtk_window_set_default_size(GTK_WINDOW(window_), kDefaultWidth,
                              kDefaultHeight);
  GdkGeometry hints{};
  hints.min_width = kMinWidth;
  hints.min_height = kMinHeight;
  gtk_window_set_geometry_hints(GTK_WINDOW(window_), nullptr, &hints,
                                GDK_HINT_MIN_SIZE);
  gtk_window_set_position(GTK_WINDOW(window_), GTK_WIN_POS_CENTER);

  // Second Flutter engine running `settingsMain` (via the sentinel arg).
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  const char* args[] = {kSettingsWindowArg, nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(project,
                                                const_cast<char**>(args));

  view_ = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view_));
  gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(view_));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view_));

  FlEngine* engine = fl_view_get_engine(view_);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  settings_channel_ = fl_method_channel_new(messenger, kSettingsHostChannel,
                                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(settings_channel_,
                                            &OnSettingsCall, this, nullptr);

  // Closing the window destroys it and releases the engine.
  g_signal_connect(window_, "destroy", G_CALLBACK(&OnWindowDestroy), this);

  gtk_widget_grab_focus(GTK_WIDGET(view_));
  return true;
}

void SettingsWindow::Teardown() {
  engine_ready_ = false;
  pending_section_.clear();
  if (settings_channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(settings_channel_, nullptr,
                                              nullptr, nullptr);
    g_clear_object(&settings_channel_);
  }
  // The view is owned by the (destroyed) window.
  view_ = nullptr;
}

// static
void SettingsWindow::OnWindowDestroy(GtkWidget* /*widget*/,
                                     gpointer user_data) {
  auto* self = static_cast<SettingsWindow*>(user_data);
  self->window_ = nullptr;
  self->Teardown();
}

// static
void SettingsWindow::OnSettingsCall(FlMethodChannel* /*channel*/,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  auto* self = static_cast<SettingsWindow*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "ready") == 0) {
    self->engine_ready_ = true;
    self->PushSection();
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_strcmp0(method, "requestSettings") == 0 ||
      g_strcmp0(method, "applySetting") == 0) {
    self->RelayToMainEngine(method_call);
    return;
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

void SettingsWindow::RelayToMainEngine(FlMethodCall* method_call) {
  // The reply arrives asynchronously; keep the call alive until then.
  fl_method_channel_invoke_method(
      host_channel_, fl_method_call_get_name(method_call),
      fl_method_call_get_args(method_call), nullptr, &OnRelayReply,
      g_object_ref(method_call));
}

// static
void SettingsWindow::OnRelayReply(GObject* source, GAsyncResult* result,
                                  gpointer user_data) {
  g_autoptr(FlMethodCall) method_call = FL_METHOD_CALL(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) host_response =
      fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(source), result,
                                             &error);

  // Mirrors macOS: host errors surface as a null snapshot and the Dart side
  // keeps its optimistic state until the next poll reconciles it.
  FlValue* snapshot = nullptr;
  if (host_response != nullptr &&
      FL_IS_METHOD_SUCCESS_RESPONSE(host_response)) {
    FlValue* value = fl_method_success_response_get_result(
        FL_METHOD_SUCCESS_RESPONSE(host_response));
    if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
      snapshot = value;
    }
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(snapshot));
  // Fails harmlessly if the Settings window was closed in the meantime.
  fl_method_call_respond(method_call, response, nullptr);
}

void SettingsWindow::PushSection() {
  if (pending_section_.empty() || settings_channel_ == nullptr) {
    return;
  }
  g_autoptr(FlValue) section = fl_value_new_string(pending_section_.c_str());
  pending_section_.clear();
  fl_method_channel_invoke_method(settings_channel_, "setSection", section,
                                  nullptr, nullptr, nullptr);
}

void SettingsWindow::RequestSnapshotAndPush() {
  // `this` outlives the main engine's reply: SettingsWindow is owned by the
  // application and only destroyed at shutdown.
  fl_method_channel_invoke_method(host_channel_, "requestSettings", nullptr,
                                  nullptr, &OnSnapshotReply, this);
}

// static
void SettingsWindow::OnSnapshotReply(GObject* source, GAsyncResult* result,
                                     gpointer user_data) {
  auto* self = static_cast<SettingsWindow*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(source), result, &error);
  if (response == nullptr || !FL_IS_METHOD_SUCCESS_RESPONSE(response)) {
    return;
  }
  FlValue* value = fl_method_success_response_get_result(
      FL_METHOD_SUCCESS_RESPONSE(response));
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
    self->PushSnapshot(value);
  }
}

void SettingsWindow::PushSnapshot(FlValue* snapshot) {
  if (settings_channel_ == nullptr) {
    return;
  }
  fl_method_channel_invoke_method(settings_channel_, "setSnapshot", snapshot,
                                  nullptr, nullptr, nullptr);
}
