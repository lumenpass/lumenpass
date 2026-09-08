#include "my_application.h"

int main(int argc, char** argv) {
  // Align the X11 WM_CLASS / Wayland app_id with the GTK application-id so
  // both display servers map running windows back to lumenpass.desktop. If
  // these identifiers diverge, GNOME / KDE / Xfce cannot match the window
  // to its .desktop file and fall back to their generic application icon
  // in the dock, taskbar, alt-tab switcher and overview.
  g_set_prgname(APPLICATION_ID);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
