#ifndef TEST_PLATFORM_UTILS_H
#define TEST_PLATFORM_UTILS_H

#define INVALID_MODULE 0


struct Module;
typedef struct Module * HModule;

typedef void * FType_Proc;

typedef unsigned int b32;

// TODO: Centralize this next testing suite update please
#if !defined(TRUE) && !defined(FALSE)
    #define TRUE 1
    #define FALSE 0
#endif

HModule platLoadLibrary(HModule mod, const char * name);

b32 platUnloadLibrary(HModule module);

FType_Proc platGetProcAddr(HModule mod, const char * name);

#define platGetProcAddrt(mod, name, type) \
    (type) platGetProcAddr(mod, name)

#endif