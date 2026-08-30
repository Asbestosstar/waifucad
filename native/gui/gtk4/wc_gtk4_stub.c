#include "wc_gtk4.h"

int wc_gtk4_native_available(void)
{
    return 0;
}

int wc_gtk4_run(const WcGtk4WindowConfig *config,
                const WcGtk4Callbacks *callbacks,
                void *user_data)
{
    (void)config;
    (void)callbacks;
    (void)user_data;
    return 78;
}
