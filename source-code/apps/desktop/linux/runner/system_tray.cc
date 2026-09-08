#include "system_tray.h"

#include <gtk/gtk.h>
#include <glib.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>

#include <string>

#ifdef HAVE_APPINDICATOR
#include <libayatana-appindicator/app-indicator.h>
#endif

namespace {

constexpr const char kAppIndicatorId[] = "tranit.lumenpass.linux";

struct MenuActionData {
  SystemTray* tray;
  SystemTray::MenuAction action;
  SystemTray::MenuCallback* callback;
};

GList* g_menu_action_data = nullptr;

MenuActionData* AllocActionData(SystemTray* tray,
                                SystemTray::MenuAction action,
                                SystemTray::MenuCallback* callback) {
  MenuActionData* data = g_new0(MenuActionData, 1);
  data->tray = tray;
  data->action = action;
  data->callback = callback;
  g_menu_action_data = g_list_prepend(g_menu_action_data, data);
  return data;
}

void FreeAllActionData() {
  for (GList* node = g_menu_action_data; node != nullptr; node = node->next) {
    g_free(node->data);
  }
  g_list_free(g_menu_action_data);
  g_menu_action_data = nullptr;
}

gchar* ResolveExecutableDir() {
  char buf[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (len <= 0) {
    return nullptr;
  }
  buf[len] = '\0';
  return g_path_get_dirname(buf);
}

gchar* ResolveBundledIconPath() {
  g_autofree gchar* exe_dir = ResolveExecutableDir();
  if (exe_dir == nullptr) {
    return nullptr;
  }
  // Prefer a mid-size icon for the panel.
  const int sizes[] = {64, 48, 32, 128, 256, 16, 512};
  for (size_t i = 0; i < G_N_ELEMENTS(sizes); ++i) {
    g_autofree gchar* size_dir =
        g_strdup_printf("%dx%d", sizes[i], sizes[i]);
    gchar* icon_path = g_build_filename(
        exe_dir, "data", "icons", size_dir, "lumenpass.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      return icon_path;
    }
    g_free(icon_path);
  }
  return nullptr;
}

#ifndef HAVE_APPINDICATOR
struct StatusIconContext {
  SystemTray::MenuCallback* callback;
};

StatusIconContext* g_status_icon_context = nullptr;

void OnStatusIconActivate(GtkStatusIcon* /*icon*/, gpointer user_data) {
  auto* ctx = static_cast<StatusIconContext*>(user_data);
  if (ctx == nullptr || ctx->callback == nullptr || !*ctx->callback) {
    return;
  }
  (*ctx->callback)(SystemTray::MenuAction::kShow);
}

void OnStatusIconPopup(GtkStatusIcon* icon,
                       guint button,
                       guint activate_time,
                       gpointer user_data) {
  GtkWidget* menu = GTK_WIDGET(user_data);
  if (menu == nullptr) {
    return;
  }
  gtk_menu_popup(GTK_MENU(menu), nullptr, nullptr,
                 gtk_status_icon_position_menu, icon, button, activate_time);
}
#endif

#ifdef HAVE_APPINDICATOR
struct SystemTrayBackend {
  AppIndicator* indicator = nullptr;
};
#else
struct SystemTrayBackend {
  GtkStatusIcon* status_icon = nullptr;
};
#endif

SystemTrayBackend g_backend;

}  // namespace

SystemTray::SystemTray() {}

SystemTray::~SystemTray() {
  Destroy();
}

void SystemTray::SetMenuCallback(MenuCallback callback) {
  callback_ = std::move(callback);
}

void SystemTray::OnMenuItemActivated(GtkMenuItem* /*item*/, gpointer user_data) {
  auto* data = static_cast<MenuActionData*>(user_data);
  if (data == nullptr || data->callback == nullptr) {
    return;
  }
  if (*data->callback) {
    (*data->callback)(data->action);
  }
}

void SystemTray::UpdateMenu() {
  if (menu_ != nullptr) {
    gtk_widget_destroy(menu_);
    menu_ = nullptr;
  }
  FreeAllActionData();

  menu_ = gtk_menu_new();
  g_object_ref_sink(menu_);

  auto AppendItem = [&](const char* label, MenuAction action, bool enabled) {
    GtkWidget* item = gtk_menu_item_new_with_label(label);
    gtk_widget_set_sensitive(item, enabled ? TRUE : FALSE);
    MenuActionData* data = AllocActionData(this, action, &callback_);
    g_signal_connect(item, "activate",
                     G_CALLBACK(&SystemTray::OnMenuItemActivated), data);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu_), item);
  };

  auto AppendSeparator = [&]() {
    GtkWidget* sep = gtk_separator_menu_item_new();
    gtk_menu_shell_append(GTK_MENU_SHELL(menu_), sep);
  };

  AppendItem("Open LumenPass", MenuAction::kShow, true);
  AppendSeparator();
  AppendItem("Quick Search", MenuAction::kQuickSearch, true);
  AppendItem("Generate Password", MenuAction::kGeneratePassword, true);
  AppendItem("Switch Vaults", MenuAction::kSwitchVaults, true);
  AppendSeparator();
  AppendItem("Lock Vault", MenuAction::kLock, !vault_locked_);
  AppendSeparator();
  AppendItem("Settings", MenuAction::kSettings, true);
  AppendItem("About", MenuAction::kAbout, true);
  AppendSeparator();
  AppendItem("Quit", MenuAction::kQuit, true);

  gtk_widget_show_all(menu_);

#ifdef HAVE_APPINDICATOR
  if (g_backend.indicator != nullptr) {
    app_indicator_set_menu(g_backend.indicator, GTK_MENU(menu_));
  }
#else
  if (g_backend.status_icon != nullptr) {
    g_signal_handlers_disconnect_matched(
        g_backend.status_icon, G_SIGNAL_MATCH_FUNC, 0, 0, nullptr,
        reinterpret_cast<gpointer>(&OnStatusIconPopup), nullptr);
    g_signal_connect(g_backend.status_icon, "popup-menu",
                     G_CALLBACK(OnStatusIconPopup), menu_);
  }
#endif
}

bool SystemTray::Create() {
  if (created_) {
    return true;
  }

  g_autofree gchar* icon_path = ResolveBundledIconPath();

#ifdef HAVE_APPINDICATOR
  g_backend.indicator = app_indicator_new(
      kAppIndicatorId, "lumenpass", APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  if (g_backend.indicator == nullptr) {
    return false;
  }
  app_indicator_set_status(g_backend.indicator, APP_INDICATOR_STATUS_ACTIVE);
  app_indicator_set_title(g_backend.indicator, "LumenPass");
  if (icon_path != nullptr) {
    g_autofree gchar* icon_dir = g_path_get_dirname(icon_path);
    app_indicator_set_icon_theme_path(g_backend.indicator, icon_dir);
  }
  app_indicator_set_icon_full(g_backend.indicator, "lumenpass", "LumenPass");
#else
  if (g_status_icon_context == nullptr) {
    g_status_icon_context = g_new0(StatusIconContext, 1);
  }
  g_status_icon_context->callback = &callback_;

  if (icon_path != nullptr) {
    g_backend.status_icon = gtk_status_icon_new_from_file(icon_path);
  } else {
    g_backend.status_icon = gtk_status_icon_new_from_icon_name("lumenpass");
  }
  if (g_backend.status_icon == nullptr) {
    return false;
  }
  gtk_status_icon_set_tooltip_text(g_backend.status_icon, "LumenPass");
  gtk_status_icon_set_visible(g_backend.status_icon, TRUE);
  g_signal_connect(g_backend.status_icon, "activate",
                   G_CALLBACK(OnStatusIconActivate), g_status_icon_context);
#endif

  created_ = true;
  UpdateMenu();
  return true;
}

void SystemTray::Destroy() {
  if (!created_) {
    return;
  }

#ifdef HAVE_APPINDICATOR
  if (g_backend.indicator != nullptr) {
    app_indicator_set_status(g_backend.indicator, APP_INDICATOR_STATUS_PASSIVE);
    g_object_unref(g_backend.indicator);
    g_backend.indicator = nullptr;
  }
#else
  if (g_backend.status_icon != nullptr) {
    gtk_status_icon_set_visible(g_backend.status_icon, FALSE);
    g_object_unref(g_backend.status_icon);
    g_backend.status_icon = nullptr;
  }
  if (g_status_icon_context != nullptr) {
    g_free(g_status_icon_context);
    g_status_icon_context = nullptr;
  }
#endif

  if (menu_ != nullptr) {
    gtk_widget_destroy(menu_);
    g_object_unref(menu_);
    menu_ = nullptr;
  }
  FreeAllActionData();
  created_ = false;
}

void SystemTray::SetVaultLocked(bool locked) {
  vault_locked_ = locked;
  if (!created_) {
    return;
  }
  UpdateMenu();

#ifdef HAVE_APPINDICATOR
  if (g_backend.indicator != nullptr) {
    const gchar* tooltip = locked ? "LumenPass (Locked)" : "LumenPass";
    app_indicator_set_title(g_backend.indicator, tooltip);
  }
#else
  if (g_backend.status_icon != nullptr) {
    gtk_status_icon_set_tooltip_text(
        g_backend.status_icon,
        locked ? "LumenPass (Locked)" : "LumenPass");
  }
#endif
}
