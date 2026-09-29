#include "window_channel_handler.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>
#include <fstream>
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>

#include "quick_search_panel.h"

namespace {

constexpr const char kChannelName[] = "lumenpass/window";

GtkWindow* GetTopLevelWindow(FlView* view) {
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

WindowChannelHandler::WindowChannelHandler(FlView* view)
    : view_(view), channel_(nullptr) {}

WindowChannelHandler::~WindowChannelHandler() {
  if (system_tray_) {
    system_tray_->Destroy();
  }
  if (channel_ != nullptr) {
    g_object_unref(channel_);
    channel_ = nullptr;
  }
}

void WindowChannelHandler::Register() {
  if (view_ == nullptr) {
    return;
  }
  FlEngine* engine = fl_view_get_engine(view_);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, kChannelName,
                                   FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, &OnMethodCall, this,
                                            nullptr);

  InitSystemTray();
}

void WindowChannelHandler::OnMethodCall(FlMethodChannel* /*channel*/,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  auto* self = static_cast<WindowChannelHandler*>(user_data);
  FlMethodResponse* response = nullptr;
  self->HandleMethodCall(method_call, &response);
  if (response == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to lumenpass/window call: %s",
              error != nullptr ? error->message : "unknown");
  }
  g_object_unref(response);
}

void WindowChannelHandler::HandleMethodCall(FlMethodCall* method_call,
                                            FlMethodResponse** response) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (g_strcmp0(method, "bringToFront") == 0) {
    BringToFront();
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "quit") == 0) {
    Quit();
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "hideWindow") == 0) {
    GtkWindow* window = GetTopLevelWindow(view_);
    if (window != nullptr) {
      gtk_widget_hide(GTK_WIDGET(window));
    }
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "setTrayVaultLocked") == 0) {
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
        system_tray_) {
      system_tray_->SetVaultLocked(fl_value_get_bool(args));
    }
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "setAutostart") == 0) {
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_BOOL) {
      *response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "Expected boolean argument", nullptr));
    } else {
      bool enabled = fl_value_get_bool(args);
      if (SetAutostart(enabled)) {
        *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      } else {
        *response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "AUTOSTART_FAILED", "Could not update autostart desktop file",
            nullptr));
      }
    }

  } else if (g_strcmp0(method, "getAutostart") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(GetAutostart());
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (g_strcmp0(method, "setStartMinimized") == 0) {
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_BOOL) {
      *response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "Expected boolean argument", nullptr));
    } else {
      SetStartMinimized(fl_value_get_bool(args));
      *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }

  } else if (g_strcmp0(method, "showQuickSearchPanel") == 0) {
    bool open_generator = false;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* g = fl_value_lookup_string(args, "openGenerator");
      if (g != nullptr && fl_value_get_type(g) == FL_VALUE_TYPE_BOOL) {
        open_generator = fl_value_get_bool(g);
      }
    }
    if (quick_search_panel_ != nullptr) {
      quick_search_panel_->Show(open_generator);
    } else {
      BringToFront();
    }
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "hideQuickSearchPanel") == 0) {
    if (quick_search_panel_ != nullptr) {
      quick_search_panel_->Hide();
    }
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (g_strcmp0(method, "clearQuickSearchData") == 0) {
    if (quick_search_panel_ != nullptr) {
      quick_search_panel_->Hide();
    }
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    *response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
}

void WindowChannelHandler::BringToFront() {
  GtkWindow* window = GetTopLevelWindow(view_);
  if (window == nullptr) {
    return;
  }
  gtk_widget_show(GTK_WIDGET(window));
  gtk_window_deiconify(window);
  gtk_window_present(window);
}

void WindowChannelHandler::Quit() {
  GtkWindow* window = GetTopLevelWindow(view_);
  if (system_tray_) {
    system_tray_->Destroy();
  }
  if (window != nullptr) {
    GtkApplication* app = gtk_window_get_application(window);
    gtk_widget_destroy(GTK_WIDGET(window));
    if (app != nullptr) {
      g_application_quit(G_APPLICATION(app));
    }
  }
}

void WindowChannelHandler::InitSystemTray() {
  system_tray_ = std::make_unique<SystemTray>();
  system_tray_->SetMenuCallback(
      [this](SystemTray::MenuAction action) { OnTrayAction(action); });
  system_tray_->Create();
}

void WindowChannelHandler::OnTrayAction(SystemTray::MenuAction action) {
  using MA = SystemTray::MenuAction;

  auto Notify = [&](const char* tray_action) {
    if (channel_ == nullptr || tray_action == nullptr) {
      return;
    }
    g_autoptr(FlValue) value = fl_value_new_string(tray_action);
    fl_method_channel_invoke_method(channel_, "trayActionTriggered", value,
                                    nullptr, nullptr, nullptr);
  };

  switch (action) {
    case MA::kShow:
      BringToFront();
      Notify("openDashboard");
      break;
    case MA::kQuickSearch:
      // Prefer the isolated panel (second engine); it pulls a fresh snapshot
      // from the main engine and shows on the pointer's monitor without
      // disturbing the main window. Fall back to surfacing the main window's
      // in-window overlay if the panel isn't available.
      if (quick_search_panel_ != nullptr) {
        quick_search_panel_->Show(false);
      } else {
        BringToFront();
        Notify("quickSearch");
      }
      break;
    case MA::kGeneratePassword:
      if (quick_search_panel_ != nullptr) {
        quick_search_panel_->Show(true);
      } else {
        BringToFront();
        Notify("generatePassword");
      }
      break;
    case MA::kSwitchVaults:
      BringToFront();
      Notify("switchVaults");
      break;
    case MA::kLock:
      Notify("lockVault");
      break;
    case MA::kSettings:
      BringToFront();
      break;
    case MA::kAbout:
      BringToFront();
      break;
    case MA::kQuit:
      Quit();
      break;
  }
}

std::string WindowChannelHandler::GetExecutablePath() {
  char buf[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (len <= 0) {
    return std::string();
  }
  buf[len] = '\0';
  return std::string(buf);
}

std::string WindowChannelHandler::GetConfigDir() {
  const char* xdg = g_get_user_config_dir();
  if (xdg != nullptr) {
    return std::string(xdg);
  }
  const char* home = g_get_home_dir();
  if (home != nullptr) {
    return std::string(home) + "/.config";
  }
  return std::string();
}

std::string WindowChannelHandler::GetAutostartDesktopPath() {
  std::string config = GetConfigDir();
  if (config.empty()) return std::string();
  return config + "/autostart/lumenpass.desktop";
}

std::string WindowChannelHandler::GetStartMinimizedPath() {
  std::string config = GetConfigDir();
  if (config.empty()) return std::string();
  std::string dir = config + "/lumenpass";
  mkdir(dir.c_str(), 0755);
  return dir + "/start_minimized";
}

bool WindowChannelHandler::SetAutostart(bool enabled) {
  std::string path = GetAutostartDesktopPath();
  if (path.empty()) return false;

  if (!enabled) {
    unlink(path.c_str());
    return true;
  }

  std::string autostart_dir = GetConfigDir() + "/autostart";
  mkdir(autostart_dir.c_str(), 0755);

  std::string exe = GetExecutablePath();
  if (exe.empty()) return false;

  std::ofstream ofs(path);
  if (!ofs.is_open()) return false;

  ofs << "[Desktop Entry]\n"
      << "Name=LumenPass\n"
      << "GenericName=Password Manager\n"
      << "Comment=KeePass-compatible password manager\n"
      << "Exec=" << exe << " --autostart %U\n"
      << "Icon=lumenpass\n"
      << "Terminal=false\n"
      << "Type=Application\n"
      << "StartupNotify=false\n"
      << "X-GNOME-Autostart-enabled=true\n";
  ofs.close();
  return ofs.good() || !ofs.fail();
}

bool WindowChannelHandler::GetAutostart() {
  std::string path = GetAutostartDesktopPath();
  if (path.empty()) return false;
  return access(path.c_str(), F_OK) == 0;
}

void WindowChannelHandler::SetStartMinimized(bool enabled) {
  std::string path = GetStartMinimizedPath();
  if (path.empty()) return;

  if (!enabled) {
    unlink(path.c_str());
    return;
  }

  std::ofstream ofs(path);
  if (ofs.is_open()) {
    ofs << "1";
    ofs.close();
  }
}

bool WindowChannelHandler::ReadStartMinimizedFlag() {
  std::string config;
  const char* xdg = g_get_user_config_dir();
  if (xdg != nullptr) {
    config = std::string(xdg);
  } else {
    const char* home = g_get_home_dir();
    if (home != nullptr) {
      config = std::string(home) + "/.config";
    }
  }
  if (config.empty()) return false;

  std::string path = config + "/lumenpass/start_minimized";
  std::ifstream ifs(path);
  if (!ifs.is_open()) return false;
  std::string content;
  std::getline(ifs, content);
  return content == "1";
}
