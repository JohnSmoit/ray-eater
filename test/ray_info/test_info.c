#include <string.h>
#include "ray_eater.h"
#include "info.h"
#include "types.h"

#include "shared/test_utils.h"

int ray_info_test_info(int argc, char ** argv) {
    const char * label = get_platform_label();

    u32 version_major = get_version_major();
    u32 version_minor = get_version_minor();

    ray_assert(!strncmp(label, RAY_PLATFORM_LABEL, strlen(RAY_PLATFORM_LABEL)),
        "platform label");

    ray_assert(version_major == RAY_VERSION_MAJOR,
        "major version");
    ray_assert(version_minor == RAY_VERSION_MINOR, 
        "minor version");

    return 0;
}
