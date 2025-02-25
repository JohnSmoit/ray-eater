#include "utils.h"

#include <time.h>
#include <sys/time.h>

TimeStamp systemTimeStamp() {
    struct timeval tv;
    time_t t = time(NULL);

    struct tm * stamp = localtime(&t);
    gettimeofday(&tv, NULL);


    TimeStamp pStamp = {
        .day = stamp->tm_mday,
        .weekDay = stamp->tm_wday,
        .hour = stamp->tm_hour,
        .millisecond = (((long long)tv.tv_sec)*1000) + (tv.tv_usec/1000),
        .minute = stamp->tm_min,
        .month = stamp->tm_mon,
        .second = stamp->tm_sec,
        .year = stamp->tm_year
    };

    return pStamp;
}
