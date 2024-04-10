enum TermState {
	NONE,
	ESC,
	SCRTITLE, // Screen title setting
	OSC,			// Operating System Command
	OSCTITLE,
	OSC_WAIT_END,
	OSC_ESC		// End of OSC or SCRTITLE
};
enum TermState state = NONE;
char scrTitleBuf[32];
char* scrTitle = scrTitleBuf;
char osc;
char titleBuf[32];
char* title = titleBuf;
void processBuf(char *p, int len) {
	do {
		if (state == NONE) {
			if (*p == 0x1b) {
				state = ESC;
				continue;
			}
			continue;
		}
		if (state == ESC) {
			if (*p == 'k') {
				state = SCRTITLE;
				scrTitle = scrTitleBuf;
				continue;
			}
			if (*p == ']') {
				state = OSC;
				osc = 0;
				continue;
			}
			state = NONE;
			continue;
		}
		if (state == SCRTITLE) {
			if (*p == 0x1b) {
				state = OSC_ESC;
				//printf("Screen title set to %s\n", scrTitleBuf);
				continue;
			}
			if (scrTitle == scrTitleBuf + sizeof(scrTitleBuf) - 1) continue;
			*scrTitle++ = *p;
			*scrTitle = 0;
			continue;
		}
		if (state == OSC) {
			if (*p == ';') {
				if (osc == '0' || osc == '2') {
					state = OSCTITLE;
					title = titleBuf;
					continue;
				}
				state = OSC_WAIT_END;
				continue;
			}
			if (osc) {
				state = OSC_WAIT_END;
				continue;
			}
			osc = *p;
			continue;
		}
		if (state == OSCTITLE) {
			if (*p == 0x07) state = NONE; else
			if (*p == 0x1b) state = OSC_ESC; else {
				if (title == titleBuf + sizeof(titleBuf) - 1) continue;
				*title++ = *p;
				*title = 0;
				continue;
			}
			//printf("Title set to %s\n", titleBuf);
			continue;
		}
		if (state == OSC_WAIT_END) {
			if (*p == 0x1b) state = OSC_ESC;
			continue;
		}
		if (state == OSC_ESC) {
			// *p should be '\'
			state = NONE;
			continue;
		}
	} while (++p, --len);
}

