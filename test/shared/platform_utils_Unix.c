#include "shared/platform_utils.h"

#include <stdlib.h>
#include <dlfcn.h>

struct Module {
    void * hLib;
};

HModule platLoadLibrary(HModule mod, const char * name) {
    void * handle = dlopen("RayEater.so", RTLD_LAZY);
    if (!handle) {
        return NULL;
    }

    mod = (HModule) malloc(sizeof(struct Module));
    mod->hLib = handle;

    return mod;
}

b32 platUnloadLibrary(HModule module) {
    if (!module) {
        return FALSE;
    }

    dlclose(module->hLib);

    free(module);
    return TRUE;
}

FType_Proc platGetProcAddr(HModule mod, const char * name) {
    if (!mod) {
        return NULL;
    }

    return dlsym(mod->hLib, name);
}