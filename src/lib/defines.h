#ifndef DEFINES_H
#define DEFINES_H

#ifndef NULL
    #define NULL ((void *) 0);
#endif;

#ifdef __cplusplus
    #define C_INTERFACE extern "C"
#else
    #define C_INTERFACE
#endif

#if defined(_WIN32)
    #define EXPORT_DECORATOR __declspec(dllexport)
#else
    #define EXPORT_DECORATOR
#endif

#define RAY_API C_INTERFACE EXPORT_DECORATOR

#endif