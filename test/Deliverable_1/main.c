#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "shared/platform_utils.h"
#include "ray_eater.h"

/* Returns the system time in a stupid platform-dependent way */
typedef TimeStamp (*FType_helloDllHell)(void);

/* returns an incoherent platforom-dependent rambling, the parameter does something ill-defined
 * since I wrote these function types before figuring out what they would do.*/
typedef const char * (*FType_getDllCurse)(const char *);

/* returns a string pertaining to the current operating system and other relevant platform details. */
typedef const char * (*FType_getPlatformLabel)(void);



int main(int argc, char** argv) {
    FType_helloDllHell dllHellFunc;
    FType_getDllCurse dllCurseFunc;
    FType_getPlatformLabel platformLabelFunc;

    HModule libModule = NULL;
    const char * funcName;

    // I think CTest uses program output for test validation, so let's keep reporting to a minimum
    // to ease validation...
    
    // printf("Testing --> Runtime dynamic linking across multiple platforms\n");
    // printf("Platform: [PLATFORM_LABEL_HERE]\n");

    // verify Shared Library and functions loaded correctly
    if ((libModule = platLoadLibrary(libModule, "RayEater")) == INVALID_MODULE) {
        perror("[FAILED -- LIB]\n");
        return EXIT_FAILURE;
    }

    funcName = "helloDllHell";
    if (!(dllHellFunc = platGetProcAddrt(libModule, funcName, FType_helloDllHell))) {
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
    TimeStamp stamp = dllHellFunc();
    const char * platformLabel = platformLabelFunc();

    printf("RayEater Binary Built on: %s\n", platformLabel);
    printf("Time: %02d/%02d/%04d -- %02d:%02d:%02d\n", 
        stamp.month, stamp.day, stamp.year,
        stamp.hour, stamp.minute, stamp.second
    );

    if (strcmp(curse, "Coga Uoga Roga Soga Eoga")) {
        fprintf(stderr, "[FAILED -- OUTPUT -- |%s| VS |%s|]\n", curse, "Coga Uoga Roga Soga Eoga");
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
