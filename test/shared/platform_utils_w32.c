#include "shared/platform_utils.h"

#include <windows.h>

struct Module {
    HINSTANCE hLibInstance;
};

HModule platLoadLibrary(const char * name) {
    return NULL;
}

b32 platUnloadLibrary(HModule module) {
    return FALSE;
}

FType_Proc platGetProcAddr(HModule mod, const char * name) {
    return NULL;
}