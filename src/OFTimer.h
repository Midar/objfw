/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012
 *   Jonathan Schleifer <js@webkeks.org>
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

#import "OFObject.h"

@class OFDate;

/**
 * \brief A class for creating and firing timers.
 */
@interface OFTimer: OFObject <OFComparing>
{
	OFDate *fireDate;
	double interval;
	id target, object1, object2;
	SEL selector;
	uint8_t arguments;
	BOOL repeats;
}

/**
 * \brief Creates and schedules a new timer with the specified time interval.
 *
 * \param interval The time interval after which the timer should be executed
 *		   when fired
 * \param target The target on which to call the selector
 * \param selector The selector to call on the target
 * \param repeats Whether the timer repeats after it has been executed
 * \return A new, autoreleased timer
 */
+ scheduledTimerWithTimeInterval: (double)interval
			  target: (id)target
			selector: (SEL)selector
			 repeats: (BOOL)repeats;

/**
 * \brief Creates and schedules a new timer with the specified time interval.
 *
 * \param interval The time interval after which the timer should be executed
 *		   when fired
 * \param target The target on which to call the selector
 * \param selector The selector to call on the target
 * \param object An object to pass when calling the selector on the target
 * \param repeats Whether the timer repeats after it has been executed
 * \return A new, autoreleased timer
 */
+ scheduledTimerWithTimeInterval: (double)interval
			  target: (id)target
			selector: (SEL)selector
			  object: (id)object
			 repeats: (BOOL)repeats;

/**
 * \brief Creates and schedules a new timer with the specified time interval.
 *
 * \param interval The time interval after which the timer should be executed
 *		   when fired
 * \param target The target on which to call the selector
 * \param selector The selector to call on the target
 * \param object1 The first object to pass when calling the selector on the
 *		  target
 * \param object2 The second object to pass when calling the selector on the
 *		  target
 * \param repeats Whether the timer repeats after it has been executed
 * \return A new, autoreleased timer
 */
+ scheduledTimerWithTimeInterval: (double)interval
			  target: (id)target
			selector: (SEL)selector
			  object: (id)object1
			  object: (id)object2
			 repeats: (BOOL)repeats;

/**
 * \brief Creates a new timer with the specified time interval.
 *
 * \param interval The time interval after which the timer should be executed
 *		   when fired
 * \param target The target on which to call the selector
 * \param selector The selector to call on the target
 * \param repeats Whether the timer repeats after it has been executed
 * \return A new, autoreleased timer
 */
+ timerWithTimeInterval: (double)interval
		 target: (id)target
	       selector: (SEL)selector
		repeats: (BOOL)repeats;

/**
 * \brief Creates a new timer with the specified time interval.
 *
 * \param interval The time interval after which the timer should be executed
 *		   when fired
 * \param target The target on which to call the selector
 * \param selector The selector to call on the target
 * \param object An object to pass when calling the selector on the target
 * \param repeats Whether the timer repeats after it has been executed
 * \return A new, autoreleased timer
 */
+ timerWithTimeInterval: (double)interval
		 target: (id)target
	       selector: (SEL)selector
		 object: (id)object
		repeats: (BOOL)repeats;

/**
 * \brief Creates a new timer with the specified time interval.
 *
 * \param interval The time interval after which the timer should be executed
 *		   when fired
 * \param target The target on which to call the selector
 * \param selector The selector to call on the target
 * \param object1 The first object to pass when calling the selector on the
 *		  target
 * \param object2 The second object to pass when calling the selector on the
 *		  target
 * \param repeats Whether the timer repeats after it has been executed
 * \return A new, autoreleased timer
 */
+ timerWithTimeInterval: (double)interval
		 target: (id)target
	       selector: (SEL)selector
		 object: (id)object1
		 object: (id)object2
		repeats: (BOOL)repeats;

/**
 * \brief Initializes an already allocated timer with the specified time
 *	  interval.
 *
 * \param fireDate The date at which the timer should fire
 * \param interval The time interval after which to repeat the timer, if it is
 *		   a repeating timer
 * \param target The target on which to call the selector
 * \param selector The selector to call on the target
 * \param repeats Whether the timer repeats after it has been executed
 * \return An initialized timer
 */
- initWithFireDate: (OFDate*)fireDate
	  interval: (double)interval
	    target: (id)target
	  selector: (SEL)selector
	   repeats: (BOOL)repeats;

/**
 * \brief Initializes an already allocated timer with the specified time
 *	  interval.
 *
 * \param fireDate The date at which the timer should fire
 * \param interval The time interval after which to repeat the timer, if it is
 *		   a repeating timer
 * \param target The target on which to call the selector
 * \param selector The selector to call on the target
 * \param object An object to pass when calling the selector on the target
 * \param repeats Whether the timer repeats after it has been executed
 * \return An initialized timer
 */
- initWithFireDate: (OFDate*)fireDate
	  interval: (double)interval
	    target: (id)target
	  selector: (SEL)selector
	    object: (id)object1
	   repeats: (BOOL)repeats;

/**
 * \brief Initializes an already allocated timer with the specified time
 *	  interval.
 *
 * \param fireDate The date at which the timer should fire
 * \param interval The time interval after which to repeat the timer, if it is
 *		   a repeating timer
 * \param target The target on which to call the selector
 * \param selector The selector to call on the target
 * \param repeats Whether the timer repeats after it has been executed
 * \return An initialized timer
 */
- initWithFireDate: (OFDate*)fireDate
	  interval: (double)interval
	    target: (id)target
	  selector: (SEL)selector
	    object: (id)object1
	    object: (id)object2
	   repeats: (BOOL)repeats;

/**
 * \brief Fires the timer, meaning it will execute the specified selector on the
 *	  target.
 */
- (void)fire;

/**
 * \brief Returns the next date at which the timer will fire.
 *
 * \return The next date at which the timer will fire
 */
- (OFDate*)fireDate;
@end
