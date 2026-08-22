#ifndef C_LAUNCH_SHIM_H
#define C_LAUNCH_SHIM_H

#include <launch.h>

static inline int webkitui_launch_activate_socket(
    const char *name, int * _Nullable * _Nonnull descriptors, size_t *count) {
  return launch_activate_socket(name, descriptors, count);
}

#endif
