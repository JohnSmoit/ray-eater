#define INVALID_MODULE 0


struct Module;
typedef struct Module * HModule;

typedef void * FType_Proc;

typedef unsigned int b32;


HModule platLoadLibrary(const char * name);

b32 platUnloadLibrary(HModule module);

FType_Proc platGetProcAddr(HModule mod, const char * name);

#define platGetProcAddrt(mod, name, type) \
    (type) platGetProcAddr(mod, name)