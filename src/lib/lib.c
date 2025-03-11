#include "ray_eater.h"
#include "info.h"

const char * get_platform_label(void) {
	return RAY_PLATFORM_LABEL; 
}

u32 get_version_major(void) {
    return RAY_VERSION_MAJOR;
}

u32 get_version_minor(void) {
    return RAY_VERSION_MINOR;
}
