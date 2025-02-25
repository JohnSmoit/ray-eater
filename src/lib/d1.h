#ifndef D1_H
#define D1_H

#include "platform/utils.h"
#include "defines.h"

/**
 * Despite it's name, gets the platform-dependent timestamp for
 * some reason.
 */
RAY_API TimeStamp helloDllHell(void);

/**
 * Platform independent per-character word substitutor
 * This mallocs so make sure to free it
 */
RAY_API const char * getDllCurse(const char * message);

/* Returns a pre-built platform label string
Intended to test CMAKE project generation
*/
RAY_API const char * getPlatformLabel(void);

RAY_API const char * daily_word(time_t time);

#endif
