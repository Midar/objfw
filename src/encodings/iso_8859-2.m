/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017,
 *               2018
 *   Jonathan Schleifer <js@heap.zone>
 *
 * All rights reserved.
 *
 * This file is part of ObjFW. It may be distributed under the terms of the
 * Q Public License 1.0, which can be found in the file LICENSE.QPL included in
 * the packaging of this file.
 *
 * Alternatively, it may be distributed under the terms of the GNU General
 * Public License, either version 2 or 3, which can be found in the file
 * LICENSE.GPLv2 or LICENSE.GPLv3 respectively included in the packaging of this
 * file.
 */

#include "config.h"

#import "OFString.h"

#import "common.h"

const char16_t of_iso_8859_2_table[] = {
	0x00A0, 0x0104, 0x02D8, 0x0141, 0x00A4, 0x013D, 0x015A, 0x00A7,
	0x00A8, 0x0160, 0x015E, 0x0164, 0x0179, 0x00AD, 0x017D, 0x017B,
	0x00B0, 0x0105, 0x02DB, 0x0142, 0x00B4, 0x013E, 0x015B, 0x02C7,
	0x00B8, 0x0161, 0x015F, 0x0165, 0x017A, 0x02DD, 0x017E, 0x017C,
	0x0154, 0x00C1, 0x00C2, 0x0102, 0x00C4, 0x0139, 0x0106, 0x00C7,
	0x010C, 0x00C9, 0x0118, 0x00CB, 0x011A, 0x00CD, 0x00CE, 0x010E,
	0x0110, 0x0143, 0x0147, 0x00D3, 0x00D4, 0x0150, 0x00D6, 0x00D7,
	0x0158, 0x016E, 0x00DA, 0x0170, 0x00DC, 0x00DD, 0x0162, 0x00DF,
	0x0155, 0x00E1, 0x00E2, 0x0103, 0x00E4, 0x013A, 0x0107, 0x00E7,
	0x010D, 0x00E9, 0x0119, 0x00EB, 0x011B, 0x00ED, 0x00EE, 0x010F,
	0x0111, 0x0144, 0x0148, 0x00F3, 0x00F4, 0x0151, 0x00F6, 0x00F7,
	0x0159, 0x016F, 0x00FA, 0x0171, 0x00FC, 0x00FD, 0x0163, 0x02D9
};
const size_t of_iso_8859_2_table_offset =
    256 - (sizeof(of_iso_8859_2_table) / sizeof(*of_iso_8859_2_table));

static const unsigned char page0[] = {
	0xA0, 0x00, 0x00, 0x00, 0xA4, 0x00, 0x00, 0xA7,
	0xA8, 0x00, 0x00, 0x00, 0x00, 0xAD, 0x00, 0x00,
	0xB0, 0x00, 0x00, 0x00, 0xB4, 0x00, 0x00, 0x00,
	0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0xC1, 0xC2, 0x00, 0xC4, 0x00, 0x00, 0xC7,
	0x00, 0xC9, 0x00, 0xCB, 0x00, 0xCD, 0xCE, 0x00,
	0x00, 0x00, 0x00, 0xD3, 0xD4, 0x00, 0xD6, 0xD7,
	0x00, 0x00, 0xDA, 0x00, 0xDC, 0xDD, 0x00, 0xDF,
	0x00, 0xE1, 0xE2, 0x00, 0xE4, 0x00, 0x00, 0xE7,
	0x00, 0xE9, 0x00, 0xEB, 0x00, 0xED, 0xEE, 0x00,
	0x00, 0x00, 0x00, 0xF3, 0xF4, 0x00, 0xF6, 0xF7,
	0x00, 0x00, 0xFA, 0x00, 0xFC, 0xFD, 0x00, 0x00
};
static const uint8_t page0Start = 0xA0;

static const unsigned char page1[] = {
	0xC3, 0xE3, 0xA1, 0xB1, 0xC6, 0xE6, 0x00, 0x00,
	0x00, 0x00, 0xC8, 0xE8, 0xCF, 0xEF, 0xD0, 0xF0,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xCA, 0xEA,
	0xCC, 0xEC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC5,
	0xE5, 0x00, 0x00, 0xA5, 0xB5, 0x00, 0x00, 0xA3,
	0xB3, 0xD1, 0xF1, 0x00, 0x00, 0xD2, 0xF2, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xD5, 0xF5,
	0x00, 0x00, 0xC0, 0xE0, 0x00, 0x00, 0xD8, 0xF8,
	0xA6, 0xB6, 0x00, 0x00, 0xAA, 0xBA, 0xA9, 0xB9,
	0xDE, 0xFE, 0xAB, 0xBB, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0xD9, 0xF9, 0xDB, 0xFB,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAC,
	0xBC, 0xAF, 0xBF, 0xAE, 0xBE
};
static const uint8_t page1Start = 0x02;

static const unsigned char page2[] = {
	0xB7, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0xA2, 0xFF, 0x00, 0xB2, 0x00, 0xBD
};
static const uint8_t page2Start = 0xC7;

bool
of_unicode_to_iso_8859_2(const of_unichar_t *input, unsigned char *output,
    size_t length, bool lossy)
{
	for (size_t i = 0; i < length; i++) {
		of_unichar_t c = input[i];

		if OF_UNLIKELY (c > 0x7F) {
			uint8_t idx;

			if OF_UNLIKELY (c > 0xFFFF) {
				if (lossy) {
					output[i] = '?';
					continue;
				} else
					return false;
			}

			switch (c >> 8) {
			CASE_MISSING_IS_KEEP(0)
			CASE_MISSING_IS_ERROR(1)
			CASE_MISSING_IS_ERROR(2)
			default:
				if (lossy) {
					output[i] = '?';
					continue;
				} else
					return false;
			}
		} else
			output[i] = (unsigned char)c;
	}

	return true;
}
