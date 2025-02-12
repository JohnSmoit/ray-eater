#include "utils.h"

#include <windows.h>


TimeStamp systemTimeStamp() {
    SYSTEMTIME time;
    GetSystemTime(&time);

    TimeStamp stamp = {
        .day = time.wDay,
        .weekDay = time.wDayOfWeek,
        .hour = time.wHour,
        .millisecond = time.wMilliseconds,
        .minute = time.wMinute,
        .month = time.wMonth,
        .second = time.wSecond,
        .year = time.wYear
    };

    return stamp;
}