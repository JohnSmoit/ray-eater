#ifndef RAY_TEST_UTILS_H
#define RAY_TEST_UTILS_H

#include <stdio.h>
#include <stdlib.h>

#include "shared/platform_utils.h"

// NOTE: Make macro if conversion to b32 makes compiler complain
inline void ray_assert(b32 expr, const char * label) {
    if (!expr) {
        fprintf(stderr, "Test assertion failed: \n%s\n", label);

        exit(EXIT_FAILURE);
    }

    printf("Test assertion succeeded!\n");
}

#endif
