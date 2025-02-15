#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "d1.h"



#include "info.h"

/**
 * Despite it's name, gets the platform-dependent timestamp for
 * some reason.
 */
TimeStamp helloDllHell() {
	return systemTimeStamp();
}


const char * map[] = {
	"Aoga",
	"Boga",
	"Coga",
	"Doga",
	"Eoga",
	"Foga",
	"Goga",
	"Hoga",
	"Ioga",
	"Joga",
	"Koga",
	"Loga",
	"Moga",
	"Noga",
	"Ooga",
	"Poga",
	"Qoga",
	"Roga",
	"Soga",
	"Toga",
	"Uoga",
	"Voga",
	"Woga",
	"Xoga",
	"Yoga",
	"Zoga"
};

/**
 * Platform independent per-character word substitutor
 * This mallocs so make sure to free it
 */
const char * getDllCurse(const char * message) {
	if (!message) return "";

	size_t msgLen = strlen(message);
	size_t bufSize = msgLen * 4 + msgLen;

	char * buf = (char * )malloc(bufSize);
	memset(buf, 0, bufSize);

	char * eBuf = buf;
	for (size_t i = 0; i < msgLen; i++) {
		const char * word = map[tolower(message[i]) - 'a'];

		strncpy(eBuf, word, 4);
		eBuf[4] = ' ';
		eBuf += 5;
	}

	buf[bufSize - 1] = '\0';
	return buf;
}

/* Returns a pre-built platform label string
Intended to test CMAKE project generation
*/
const char * getPlatformLabel() {
	return RAY_PLATFORM_LABEL; 
}

const char * daily_word(time_t time) {
	if (time % 2 == 0) {
		return "Fuck";
	} else {
		return "Shit";
	}
}