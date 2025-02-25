#ifndef PLATFORM_UTILS_H
#define PLATFORM_UTILS_H

#include "types.h"

typedef struct TimeStamp {
    u16 day;
    u16 weekDay;
    u16 second;
    u16 hour;
    u16 millisecond;
    u16 minute;
    u16 month;
    u16 year;
} TimeStamp;

TimeStamp systemTimeStamp(void);

#endif
