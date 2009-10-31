/*
 * Copyright (c) 2008 - 2009
 *   Jonathan Schleifer <js@webkeks.org>
 *
 * All rights reserved.
 *
 * This file is part of libobjfw. It may be distributed under the terms of the
 * Q Public License 1.0, which can be found in the file LICENSE included in
 * the packaging of this file.
 */

#import "OFString.h"

@interface CaseFoldingGenerator: OFObject
{
	of_unichar_t table[0x110000];
	size_t size;
}

- (void)fillTableFromFile: (OFString*)file;
- (void)writeTableToFile: (OFString*)file;
- (void)appendHeaderToFile: (OFString*)file;
@end
