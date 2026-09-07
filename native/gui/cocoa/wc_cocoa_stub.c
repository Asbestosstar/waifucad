#include "wc_cocoa.h"

/* Scaffold stub. The functional bridge is wc_cocoa.m (Objective-C, AppKit +
   Metal) and is compiled instead of this file on a macOS host once it lands.
   Keeping the stub C11 lets every host build and link the macOS GUI target
   without GTK4 or any Apple framework present. */

int wc_cocoa_native_available(void)
{
    return 0;
}

int wc_cocoa_run(const WcCocoaWindowConfig *config,
                 const WcCocoaCallbacks *callbacks,
                 void *user_data)
{
    (void)config;
    (void)callbacks;
    (void)user_data;
    return 78;
}
