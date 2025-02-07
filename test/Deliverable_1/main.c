#include <stdio.h>

#include "shared/platform_utils.h"

/* Returns the system time in a stupid platform-dependent way */
typedef double (*FType_helloDllHell1)(void);

/* returns an incoherent platforom-dependent rambling, the parameter does something ill-defined
 * since I wrote these function types before figuring out what they would do.*/
typedef const char * (*FType_getDllCurse)(const char *);

/* returns a string pertaining to the current operating system and other relevant platform details. */
typedef const char * (*FType_getPlatformLabel)(void);


int main(int argc, char** argv) {
    FType_helloDllHell1 dllHellFunc;
    FType_getDllCurse dllCurseFunc;
    FType_getPlatformLabel platformLabelFunc;

    printf("Testing --> Runtime dynamic linking across multiple platforms\n");
    printf("Platform: [PLATFORM_LABEL_HERE]\n");

    // verify Shared Library and functions loaded correctly
    // verify output of functions
    // verify Shared Library unloaded correctly

    return 0;
}
