#ifndef DEFINES_H
#define DEFINES_H

#ifndef NULL
    #define NULL ((void *) 0);
#endif;

#ifdef __cplusplus
    #define RAY_API extern "C" __declspec(dllexport)
    #define RAY_API_FUNC(ret) extern "C" __declspec(dllexport) ret __cdecl
#else
    #define RAY_API __declspec(dllexport)
    #define RAY_API_FUNC(ret) __declspec(dllexport) ret __cdecl
#endif

#endif