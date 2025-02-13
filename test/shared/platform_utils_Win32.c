#include "shared/platform_utils.h"

#include <windows.h>
#include <stdlib.h>
#include <stdio.h>

struct Module {
    HMODULE module;
};

HModule platLoadLibrary(HModule mod, const char * name) {
    HMODULE w32Module = LoadLibraryA(name);
    if (!w32Module) {
        return NULL;
    }

    mod = (HModule) malloc(sizeof(struct Module));
    mod->module = w32Module;

    return mod;
}

b32 platUnloadLibrary(HModule module) {
    if (!module) {
        return FALSE;
    }

    b32 res = FreeLibrary(module->module);

    free(module);
    return res;
}

FType_Proc platGetProcAddr(HModule mod, const char * name) {
    if (!mod) return NULL;
    FARPROC prc = GetProcAddress(mod->module, name);

    return prc;
}