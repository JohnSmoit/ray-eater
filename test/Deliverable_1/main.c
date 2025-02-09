#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

    HModule libModule;
    const char * funcName;

    // I think CTest uses program output for test validation, so let's keep reporting to a minimum
    // to ease validation...
    
    // printf("Testing --> Runtime dynamic linking across multiple platforms\n");
    // printf("Platform: [PLATFORM_LABEL_HERE]\n");

    // verify Shared Library and functions loaded correctly
    if ((libModule = platLoadLibrary("RayEater")) == INVALID_MODULE) {
        perror("[FAILED -- LIB]\n");
        return EXIT_FAILURE;
    }

    funcName = "helloDllHell";
    if (!(dllHellFunc = platGetProcAddrt(libModule, funcName, FType_helloDllHell1))) {
        fprintf(stderr, "[FAILED -- FUNC -- %s]\n", funcName);
        return EXIT_FAILURE;
    }


    funcName = "getDllCurse";
    if (!(dllCurseFunc = platGetProcAddrt(libModule, funcName, FType_getDllCurse))) {
        fprintf(stderr, "[FAILED -- FUNC -- %s]\n", funcName);
        return EXIT_FAILURE;
    }

    funcName = "getPlatformLabel";
    if (!(platformLabelFunc = platGetProcAddrt(libModule, funcName, FType_getPlatformLabel))) {
        fprintf(stderr, "[FAILED -- FUNC -- %s]\n", funcName);
        return EXIT_FAILURE;
    }
    // verify output of functions
    const char * curse = dllCurseFunc("CURSE");

    // these are kind of not worth output testing...
    double timeStamp = dllHellFunc();
    const char * platformLabel = platformLabelFunc();

    if (strcmp(curse, "Curse Unholy Retribution Sacrilege Evil")) {
        fprintf(stderr, "[FAILED -- OUTPUT -- %s]\n", funcName);
        return EXIT_FAILURE;
    }



    // verify Shared Library unloaded correctly
    if (!platUnloadLibrary(libModule)) {
        fprintf(stderr, "[FAILED -- UNLOAD]\n");
        return EXIT_FAILURE;
    }

    libModule = NULL;

    return 0;
}
