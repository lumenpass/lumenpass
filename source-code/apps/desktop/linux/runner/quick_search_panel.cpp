#include "quick_search_panel.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr const char kQuickSearchChannel[] = "lumenpass/quick_search";

// Sentinel Dart entrypoint argument. The GTK embedder cannot launch a custom
// entrypoint, so `main()` inspects this flag and delegates to
// `quickSearchMain()`. Keep in sync with lib/main.dart.
constexpr const char kQuickSearchPanelArg[] = "--quick-search-panel";

GtkWindow* ToplevelOf(FlView* view) {
  if (view == nullptr) {
    return nullptr;
  }
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (toplevel == nullptr || !gtk_widget_is_toplevel(toplevel)) {
    return nullptr;
  }
  return GTK_WINDOW(toplevel);
}

}  // namespace

QuickSearchPanel::QuickSearchPanel(FlView* main_view,
                                   FlMethodChannel* main_channel)
    : main_view_(main_view), main_channel_(main_channel) {}

QuickSearchPanel::~QuickSearchPanel() {
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }
  if (window_ != nullptr) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
  }
}

bool QuickSearchPanel::EnsureCreated() {
  if (window_ != nullptr) {
    return true;
  }

  // Borderless, always-on-top, off the taskbar/pager — mirrors the macOS
  // NSPanel (.borderless, .nonactivatingPanel, .floating) and the Windows
  // WS_POPUP | WS_EX_TOOLWINDOW | WS_EX_TOPMOST popup.
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
  gtk_window_set_type_hint(GTK_WINDOW(window_), GDK_WINDOW_TYPE_HINT_UTILITY);
  gtk_window_set_resizable(GTK_WINDOW(window_), FALSE);
  gtk_widget_set_app_paintable(window_, TRUE);

  const int w = ResolvedLogicalWidth();
  const int h = static_cast<int>(std::lround(content_height_));
  gtk_window_set_default_size(GTK_WINDOW(window_), w, h);

  // Second Flutter engine running `quickSearchMain` (via the sentinel arg —
  // see the class docs and lib/main.dart).
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  const char* args[] = {kQuickSearchPanelArg, nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(
      project, const_cast<char**>(args));

  view_ = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view_));
  gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(view_));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view_));

  FlEngine* engine = fl_view_get_engine(view_);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, kQuickSearchChannel,
                                   FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, &OnQuickSearchCall, this,
                                            nullptr);

  // Dismiss when focus leaves the panel (click outside) and on Escape.
  gtk_widget_add_events(window_, GDK_FOCUS_CHANGE_MASK);
  g_signal_connect(window_, "focus-out-event", G_CALLBACK(&OnFocusOut), this);
  g_signal_connect(window_, "key-press-event", G_CALLBACK(&OnKeyPress), this);

  return true;
}

// static
void QuickSearchPanel::OnQuickSearchCall(FlMethodChannel* /*channel*/,
                                         FlMethodCall* method_call,
                                         gpointer user_data) {
  auto* self = static_cast<QuickSearchPanel*>(user_data);
  FlMethodResponse* response = nullptr;
  self->HandleQuickSearchCall(method_call, &response);
  if (response == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to lumenpass/quick_search call: %s",
              error != nullptr ? error->message : "unknown");
  }
  g_object_unref(response);
}

void QuickSearchPanel::HandleQuickSearchCall(FlMethodCall* method_call,
                                             FlMethodResponse** response) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (g_strcmp0(method, "ready") == 0) {
    // Engine booted; snapshot pulled fresh on each open. Nothing to do.
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "close") == 0) {
    Hide();
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "openEntry") == 0) {
    Hide();
    if (main_channel_ != nullptr && args != nullptr &&
        fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      g_autoptr(FlValue) uuid = fl_value_new_string(fl_value_get_string(args));
      fl_method_channel_invoke_method(main_channel_, "quickSearchOpenEntry",
                                      uuid, nullptr, nullptr, nullptr);
    }
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "editEntry") == 0) {
    Hide();
    if (main_channel_ != nullptr && args != nullptr &&
        fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      g_autoptr(FlValue) uuid = fl_value_new_string(fl_value_get_string(args));
      fl_method_channel_invoke_method(main_channel_, "quickSearchEditEntry",
                                      uuid, nullptr, nullptr, nullptr);
    }
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "createItem") == 0) {
    Hide();
    if (main_channel_ != nullptr) {
      fl_method_channel_invoke_method(main_channel_, "quickSearchCreateItem",
                                      nullptr, nullptr, nullptr, nullptr);
    }
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "heightChanged") == 0) {
    double height = content_height_;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* h = fl_value_lookup_string(args, "height");
      if (h != nullptr && fl_value_get_type(h) == FL_VALUE_TYPE_FLOAT) {
        height = fl_value_get_float(h);
      }
    }
    SetContentHeight(height);
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    *response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
}

void QuickSearchPanel::Toggle() {
  if (visible_) {
    Hide();
  } else {
    Show(false);
  }
}

void QuickSearchPanel::Show(bool open_generator) {
  if (!EnsureCreated()) {
    return;
  }
  if (main_channel_ == nullptr) {
    Reveal();
    return;
  }

  // Pull a fresh snapshot from the main engine, then reveal the panel from the
  // async reply callback.
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "openGenerator",
                           fl_value_new_bool(open_generator));
  fl_method_channel_invoke_method(main_channel_, "quickSearchRequestSnapshot",
                                  args, nullptr, &OnSnapshotReply, this);
}

// static
void QuickSearchPanel::OnSnapshotReply(GObject* source, GAsyncResult* result,
                                       gpointer user_data) {
  auto* self = static_cast<QuickSearchPanel*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(source), result, &error);
  if (response != nullptr) {
    FlValue* value = fl_method_response_get_result(response, nullptr);
    if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING &&
        self->channel_ != nullptr) {
      g_autoptr(FlValue) json =
          fl_value_new_string(fl_value_get_string(value));
      fl_method_channel_invoke_method(self->channel_, "setSnapshot", json,
                                      nullptr, nullptr, nullptr);
    }
  }
  // Reveal regardless — an empty panel is still better than a swallowed hotkey.
  self->Reveal();
}

void QuickSearchPanel::Reveal() {
  if (window_ == nullptr) {
    return;
  }
  PositionOnPointerMonitor();
  gtk_widget_show(window_);
  gtk_window_present(GTK_WINDOW(window_));
  gtk_widget_grab_focus(GTK_WIDGET(view_));
  visible_ = true;
}

void QuickSearchPanel::PositionOnPointerMonitor() {
  if (window_ == nullptr) {
    return;
  }
  GdkDisplay* display = gtk_widget_get_display(window_);
  if (display == nullptr) {
    return;
  }

  // Find the monitor containing the pointer so the panel follows the user
  // across multiple monitors (mirrors macOS quickSearchTargetScreen and the
  // Windows MonitorFromPoint(cursor) logic).
  GdkRectangle work{};
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;
  GdkMonitor* monitor = nullptr;
  if (pointer != nullptr) {
    gint px = 0;
    gint py = 0;
    gdk_device_get_position(pointer, nullptr, &px, &py);
    monitor = gdk_display_get_monitor_at_point(display, px, py);
  }
  if (monitor == nullptr) {
    monitor = gdk_display_get_primary_monitor(display);
  }
  if (monitor == nullptr) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor == nullptr) {
    return;
  }
  gdk_monitor_get_workarea(monitor, &work);

  const int panel_w = ResolvedLogicalWidth();
  const int panel_h = static_cast<int>(std::lround(content_height_));
  gtk_window_resize(GTK_WINDOW(window_), panel_w, panel_h);

  const int x = work.x + (work.width - panel_w) / 2;
  // A little above vertical centre (~38% from the top) to match spotlight UX.
  const int y = work.y + static_cast<int>((work.height - panel_h) * 0.38);
  gtk_window_move(GTK_WINDOW(window_), x, y);
}

void QuickSearchPanel::SetContentHeight(double logical_height) {
  content_height_ = std::max(kMinLogicalHeight, logical_height);
  if (window_ == nullptr || !visible_) {
    return;
  }
  PositionOnPointerMonitor();
}

void QuickSearchPanel::Hide() {
  if (!visible_ || window_ == nullptr) {
    return;
  }
  visible_ = false;
  gtk_widget_hide(window_);
  if (main_channel_ != nullptr) {
    fl_method_channel_invoke_method(main_channel_, "quickSearchPanelClosed",
                                    nullptr, nullptr, nullptr, nullptr);
  }
}

int QuickSearchPanel::ResolvedLogicalWidth() const {
  GtkWindow* main = ToplevelOf(main_view_);
  if (main == nullptr) {
    return kDefaultLogicalWidth;
  }
  gint main_w = 0;
  gint main_h = 0;
  gtk_window_get_size(main, &main_w, &main_h);
  if (main_w <= 0) {
    return kDefaultLogicalWidth;
  }
  // 70% of the main window width, clamped — matches macOS/Windows.
  const int target = static_cast<int>(std::floor(main_w * 0.70));
  return std::max(kMinLogicalWidth, std::min(target, kMaxLogicalWidth));
}

// static
gboolean QuickSearchPanel::OnFocusOut(GtkWidget* /*widget*/,
                                      GdkEvent* /*event*/, gpointer user_data) {
  auto* self = static_cast<QuickSearchPanel*>(user_data);
  if (self->visible_) {
    self->Hide();
  }
  return FALSE;
}

// static
gboolean QuickSearchPanel::OnKeyPress(GtkWidget* /*widget*/,
                                      GdkEventKey* event, gpointer user_data) {
  auto* self = static_cast<QuickSearchPanel*>(user_data);
  if (event != nullptr && event->keyval == GDK_KEY_Escape) {
    self->Hide();
    return TRUE;
  }
  return FALSE;  // let Flutter handle all other keys
}
