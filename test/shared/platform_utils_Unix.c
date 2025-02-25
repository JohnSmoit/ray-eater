#include "shared/platform_utils.h"

#include <stdlib.h>
#include <stdio.h>

#include <unistd.h>
#include <dlfcn.h>

struct Module {
    void * hLib;
};



HModule platLoadLibrary(HModule mod) {
    char buf[512];
    printf("Current working directory: %s\n", getcwd(buf, 512));
    void * handle = dlopen("./libRayEater.so", RTLD_NOW);
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
