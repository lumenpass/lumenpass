#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <libgen.h>
#include <string.h>

#include "flutter/generated_plugin_registrant.h"
#include "quick_search_panel.h"
#include "ssh_agent_server.h"
#include "window_channel_handler.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  WindowChannelHandler* window_channel_handler;
  QuickSearchPanel* quick_search_panel;
  gboolean start_hidden;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gchar* my_application_get_executable_dir() {
  char buf[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (len <= 0) {
    return nullptr;
  }
  buf[len] = '\0';
  return g_path_get_dirname(buf);
}

static GList* my_application_load_bundled_icons() {
  g_autofree gchar* exe_dir = my_application_get_executable_dir();
  if (exe_dir == nullptr) {
    return nullptr;
  }

  const int sizes[] = {16, 32, 48, 64, 128, 256, 512};
  GList* icons = nullptr;
  for (size_t i = 0; i < G_N_ELEMENTS(sizes); ++i) {
    g_autofree gchar* size_dir =
        g_strdup_printf("%dx%d", sizes[i], sizes[i]);
    g_autofree gchar* icon_path = g_build_filename(
        exe_dir, "data", "icons", size_dir, "lumenpass.png", nullptr);
    if (!g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      continue;
    }
    g_autoptr(GError) error = nullptr;
    GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file(icon_path, &error);
    if (pixbuf == nullptr) {
      g_warning("Failed to load icon %s: %s", icon_path,
                error != nullptr ? error->message : "unknown error");
      continue;
    }
    icons = g_list_prepend(icons, pixbuf);
  }
  return icons;
}

static void my_application_apply_window_icon(GtkWindow* window) {
  // Prefer the themed icon when present (this is what installed builds
  // pick up via /usr/share/icons/hicolor/.../lumenpass.png).
  gtk_window_set_icon_name(window, "lumenpass");

  // For dev runs (`flutter run -d linux`) and bundles that don't install
  // into the freedesktop theme, fall back to icons shipped next to the
  // executable in data/icons/.
  GtkIconTheme* theme = gtk_icon_theme_get_default();
  if (theme != nullptr && gtk_icon_theme_has_icon(theme, "lumenpass")) {
    return;
  }

  GList* icons = my_application_load_bundled_icons();
  if (icons == nullptr) {
    return;
  }
  gtk_window_set_icon_list(window, icons);
  gtk_window_set_default_icon_list(icons);
  g_list_free_full(icons, g_object_unref);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "LumenPass - Password Manager");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "LumenPass - Password Manager");
  }

  gtk_window_set_default_size(window, 1280, 800);
  my_application_apply_window_icon(window);

  g_signal_connect(window, "delete-event",
                   G_CALLBACK(+[](GtkWidget* widget, GdkEvent*, gpointer) -> gboolean {
                     gtk_widget_hide(widget);
                     return TRUE;
                   }),
                   nullptr);

  if (!self->start_hidden) {
    gtk_widget_show(GTK_WIDGET(window));
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  if (self->window_channel_handler == nullptr) {
    self->window_channel_handler = new WindowChannelHandler(view);
    self->window_channel_handler->Register();

    // Boot the isolated Quick Search panel (second Flutter engine on the
    // `quickSearchMain` entrypoint via the sentinel argument) up front so the
    // first tray-triggered open is instant. It brokers vault-backed intents
    // through the main engine's lumenpass/window channel.
    self->quick_search_panel = new QuickSearchPanel(
        view, self->window_channel_handler->channel());
    self->window_channel_handler->SetQuickSearchPanel(
        self->quick_search_panel);
  }

  // Bind the SSH agent control channel onto the same Flutter engine. The
  // agent's listening socket is created lazily when Dart calls startAgent.
  lumenpass::SshAgentServer::Instance().Register(view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Acquires a cross-process exclusive lockfile and returns the fd (>= 0) on
// success, or -1 if another instance already holds the lock. The file is
// kept open for the lifetime of the process; closing it releases the lock.
static int acquire_single_instance_lock() {
  // Resolve the runtime directory: prefer XDG_RUNTIME_DIR, fall back to
  // ~/.local/share/lumenpass.
  const gchar* runtime_dir = g_get_user_runtime_dir();
  if (runtime_dir == nullptr || runtime_dir[0] == '\0') {
    runtime_dir = g_get_user_data_dir();
  }

  g_autofree gchar* lock_dir =
      g_build_filename(runtime_dir, "lumenpass", nullptr);
  g_mkdir_with_parents(lock_dir, 0700);

  g_autofree gchar* lock_path =
      g_build_filename(lock_dir, "single-instance.lock", nullptr);

  int fd = open(lock_path, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
  if (fd < 0) {
    return -1;  // Can't create lockfile; allow launch.
  }

  if (flock(fd, LOCK_EX | LOCK_NB) < 0) {
    close(fd);
    return -1;  // Another instance holds the lock.
  }

  return fd;  // Caller must keep this fd open.
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  // Single-instance guard. Skip for the isolated Quick Search child process
  // (launched with the sentinel flag by the main process itself).
  gboolean is_quick_search = FALSE;
  if (self->dart_entrypoint_arguments != nullptr) {
    for (int i = 0; self->dart_entrypoint_arguments[i] != nullptr; ++i) {
      if (g_strcmp0(self->dart_entrypoint_arguments[i],
                    "--quick-search-panel") == 0) {
        is_quick_search = TRUE;
        break;
      }
    }
  }

  if (!is_quick_search) {
    int lock_fd = acquire_single_instance_lock();
    if (lock_fd < 0) {
      // Another instance is running. Try to raise its window via wmctrl or
      // xdotool (best-effort; not fatal if unavailable), then notify the user.
      g_spawn_command_line_async(
          "sh -c 'wmctrl -a \"LumenPass\" || "
          "xdotool search --name \"LumenPass\" windowactivate 2>/dev/null'",
          nullptr);

      // Show a GTK dialog without a parent window (pre-Flutter).
      gtk_init(nullptr, nullptr);
      GtkWidget* dialog = gtk_message_dialog_new(
          nullptr, GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_OK,
          "LumenPass is already running.");
      gtk_message_dialog_format_secondary_text(
          GTK_MESSAGE_DIALOG(dialog),
          "The existing window has been brought to the front.");
      gtk_window_set_title(GTK_WINDOW(dialog), "LumenPass");
      gtk_dialog_run(GTK_DIALOG(dialog));
      gtk_widget_destroy(dialog);

      *exit_status = 0;
      return TRUE;
    }
    // lock_fd is intentionally kept open. It is released automatically
    // when the process exits (normal or crash).
    (void)lock_fd;
  }

  gboolean has_autostart = FALSE;
  if (self->dart_entrypoint_arguments != nullptr) {
    for (int i = 0; self->dart_entrypoint_arguments[i] != nullptr; ++i) {
      if (g_strcmp0(self->dart_entrypoint_arguments[i], "--autostart") == 0) {
        has_autostart = TRUE;
        break;
      }
    }
  }

  if (has_autostart && WindowChannelHandler::ReadStartMinimizedFlag()) {
    self->start_hidden = TRUE;
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Tear the SSH agent down so we never leave the AF_UNIX socket on disk
  // after a clean exit.
  lumenpass::SshAgentServer::Instance().Shutdown();

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->window_channel_handler != nullptr) {
    self->window_channel_handler->SetQuickSearchPanel(nullptr);
  }
  if (self->quick_search_panel != nullptr) {
    delete self->quick_search_panel;
    self->quick_search_panel = nullptr;
  }
  if (self->window_channel_handler != nullptr) {
    delete self->window_channel_handler;
    self->window_channel_handler = nullptr;
  }
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window_channel_handler = nullptr;
  self->quick_search_panel = nullptr;
  self->start_hidden = FALSE;
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
