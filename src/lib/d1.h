#ifndef D1_H
#define D1_H

#include "platform/utils.h"
#include "defines.h"

/**
 * Despite it's name, gets the platform-dependent timestamp for
 * some reason.
 */
RAY_API_FUNC(TimeStamp) helloDllHell();

/**
 * Platform independent per-character word substitutor
 * This mallocs so make sure to free it
 */
RAY_API_FUNC(const char *) getDllCurse(const char * message);

/* Returns a pre-built platform label string
Intended to test CMAKE project generation
*/
RAY_API_FUNC(const char *) getPlatformLabel();

__declspec(dllexport) const char * __cdecl daily_word(time_t time);

#endif