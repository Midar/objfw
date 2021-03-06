/*
 * Copyright (c) 2008-2021 Jonathan Schleifer <js@nil.im>
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

#import "OFException.h"

OF_ASSUME_NONNULL_BEGIN

/**
 * @class OFEnumerationMutationException \
 *	  OFEnumerationMutationException.h \
 *	  ObjFW/OFEnumerationMutationException.h
 *
 * @brief An exception indicating that a mutation was detected during
 *        enumeration.
 */
@interface OFEnumerationMutationException: OFException
{
	id _object;
}

/**
 * @brief The object which was mutated during enumeration.
 */
@property (readonly, nonatomic) id object;

+ (instancetype)exception OF_UNAVAILABLE;

/**
 * @brief Creates a new, autoreleased enumeration mutation exception.
 *
 * @param object The object which was mutated during enumeration
 * @return A new, autoreleased enumeration mutation exception
 */
+ (instancetype)exceptionWithObject: (id)object;

- (instancetype)init OF_UNAVAILABLE;

/**
 * @brief Initializes an already allocated enumeration mutation exception.
 *
 * @param object The object which was mutated during enumeration
 * @return An initialized enumeration mutation exception
 */
- (instancetype)initWithObject: (id)object OF_DESIGNATED_INITIALIZER;
@end

OF_ASSUME_NONNULL_END
