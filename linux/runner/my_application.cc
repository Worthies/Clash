#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <glib.h>
#include <limits.h>
#include <unistd.h>
#include <string>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// Message handler to suppress GTK warnings about invalid screens
// This can happen during initialization before screens are fully set up
static void suppress_gtk_screen_warning(const gchar *log_domain,
                                        GLogLevelFlags log_level,
                                        const gchar *message,
                                        gpointer user_data) {
  // Suppress the gtk_icon_theme_get_for_screen assertion failure
  // This is a known GTK issue during early initialization
  if (log_level == G_LOG_LEVEL_CRITICAL &&
      log_domain && g_str_has_prefix(log_domain, "Gtk") &&
      message && g_strstr_len(message, -1, "gtk_icon_theme_get_for_screen") != NULL) {
    return;  // Don't print this message
  }
  // Print all other messages normally by calling the default handler
  g_log_default_handler(log_domain, log_level, message, user_data);
}

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView *view)
{
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
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
  if (screen && GDK_IS_SCREEN(screen) && GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Clash");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Clash");
  }

  gtk_window_set_default_size(window, 1280, 720);

  // Set window icon (taskbar) explicitly.
  // Cinnamon can display an empty/transparent taskbar icon if the icon is
  // looked up via theme/WMClass mapping. Prefer a known-good, non-alpha PNG
  // bundled with Flutter assets.
  {
    std::string exe_dir;
    char exe_buf[PATH_MAX + 1];
    const ssize_t len = readlink("/proc/self/exe", exe_buf, PATH_MAX);
    if (len > 0) {
      exe_buf[len] = '\0';
      g_autofree gchar* dir = g_path_get_dirname(exe_buf);
      if (dir != nullptr) {
        exe_dir = dir;
      }
    }

    const std::string candidate1 =
        exe_dir.empty() ? "" : (exe_dir + "/data/flutter_assets/assets/taskbar_icon_noalpha.png");
    const std::string candidate2 =
        exe_dir.empty() ? "" : (exe_dir + "/data/flutter_assets/icon.png");
    const char* fallback1 = "runner/icon.png";
    const char* fallback2 = "icon.png";

    GError* error = nullptr;
    bool set_ok = false;
    if (!candidate1.empty() && g_file_test(candidate1.c_str(), G_FILE_TEST_EXISTS)) {
      set_ok = gtk_window_set_icon_from_file(window, candidate1.c_str(), &error);
    } else if (!candidate2.empty() && g_file_test(candidate2.c_str(), G_FILE_TEST_EXISTS)) {
      set_ok = gtk_window_set_icon_from_file(window, candidate2.c_str(), &error);
    } else if (g_file_test(fallback1, G_FILE_TEST_EXISTS)) {
      set_ok = gtk_window_set_icon_from_file(window, fallback1, &error);
    } else if (g_file_test(fallback2, G_FILE_TEST_EXISTS)) {
      set_ok = gtk_window_set_icon_from_file(window, fallback2, &error);
    }

    if (!set_ok) {
      if (error) {
        g_warning("Failed to set window icon: %s", error->message);
        g_clear_error(&error);
      } else {
        g_warning("Failed to set window icon: no usable icon file found");
      }
    } else if (error) {
      // Some GTK paths can return true but still set an error.
      g_clear_error(&error);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000 for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

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

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
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

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Suppress GTK warnings about invalid screens during initialization
  // This is a known GTK 3.22+ issue that occurs before screens are fully set up
  g_log_set_handler("Gtk", G_LOG_LEVEL_CRITICAL, suppress_gtk_screen_warning, NULL);

  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // Set application default icon from system theme
  // This ensures the icon shows in the application menu and system indicators
  // Use gtk_icon_theme_get_default() which is safer than get_for_screen()
  GError* error = nullptr;
  GtkIconTheme* icon_theme = gtk_icon_theme_get_default();
  if (icon_theme) {
    GdkPixbuf* app_icon = gtk_icon_theme_load_icon(icon_theme, APPLICATION_ID, 256,
                                                     GTK_ICON_LOOKUP_GENERIC_FALLBACK, &error);
    if (app_icon) {
      gtk_window_set_default_icon(app_icon);
      g_object_unref(app_icon);
    }
    if (error) {
      g_clear_error(&error);
    }
  }

  // Fallback: try to load from file if theme lookup fails
  if (!icon_theme) {
    GdkPixbuf* fallback_icon = nullptr;

    if (g_file_test("runner/icon.png", G_FILE_TEST_EXISTS)) {
      fallback_icon = gdk_pixbuf_new_from_file("runner/icon.png", nullptr);
    } else if (g_file_test("icon.png", G_FILE_TEST_EXISTS)) {
      fallback_icon = gdk_pixbuf_new_from_file("icon.png", nullptr);
    }

    if (fallback_icon) {
      gtk_window_set_default_icon(fallback_icon);
      g_object_unref(fallback_icon);
    }
  }

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
