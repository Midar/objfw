/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017,
 *               2018, 2019, 2020
 *   Jonathan Schleifer <js@nil.im>
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

#define __NO_EXT_QNX

#include "config.h"

#include "platform.h"

#ifdef OF_WINDOWS
/* Win32 has a ridiculous default of 64, even though it supports much more. */
# define FD_SETSIZE 1024
#endif

#include <errno.h>
#include <string.h>

#include <sys/time.h>

#import "OFSelectKernelEventObserver.h"
#import "OFArray.h"

#import "OFInitializationFailedException.h"
#import "OFObserveFailedException.h"
#import "OFOutOfRangeException.h"

#import "socket_helpers.h"

#ifdef OF_AMIGAOS
# include <proto/exec.h>
#endif

@implementation OFSelectKernelEventObserver
- (instancetype)init
{
	self = [super init];

	@try {
#ifdef OF_AMIGAOS
		_maxFD = 0;
#else
# ifndef OF_WINDOWS
		if (_cancelFD[0] >= (int)FD_SETSIZE)
			@throw [OFInitializationFailedException
			    exceptionWithClass: self.class];
# endif

		FD_ZERO(&_readFDs);
		FD_ZERO(&_writeFDs);
		FD_SET(_cancelFD[0], &_readFDs);

		if (_cancelFD[0] > INT_MAX)
			@throw [OFOutOfRangeException exception];

		_maxFD = (int)_cancelFD[0];
#endif
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)addObjectForReading: (id <OFReadyForReadingObserving>)object
{
	int fd = object.fileDescriptorForReading;

	if (fd < 0)
		@throw [OFObserveFailedException exceptionWithObserver: self
								 errNo: EBADF];

	if (fd > INT_MAX - 1)
		@throw [OFOutOfRangeException exception];

#ifndef OF_WINDOWS
	if (fd >= (int)FD_SETSIZE)
		@throw [OFOutOfRangeException exception];
#endif

	if (fd > _maxFD)
		_maxFD = fd;

	FD_SET((of_socket_t)fd, &_readFDs);

	[super addObjectForReading: object];
}

- (void)addObjectForWriting: (id <OFReadyForWritingObserving>)object
{
	int fd = object.fileDescriptorForWriting;

	if (fd < 0)
		@throw [OFObserveFailedException exceptionWithObserver: self
								 errNo: EBADF];

	if (fd > INT_MAX - 1)
		@throw [OFOutOfRangeException exception];

#ifndef OF_WINDOWS
	if (fd >= (int)FD_SETSIZE)
		@throw [OFOutOfRangeException exception];
#endif

	if (fd > _maxFD)
		_maxFD = fd;

	FD_SET((of_socket_t)fd, &_writeFDs);

	[super addObjectForWriting: object];
}

- (void)removeObjectForReading: (id <OFReadyForReadingObserving>)object
{
	/* TODO: Adjust _maxFD */

	int fd = object.fileDescriptorForReading;

	if (fd < 0)
		@throw [OFObserveFailedException exceptionWithObserver: self
								 errNo: EBADF];

#ifndef OF_WINDOWS
	if (fd >= (int)FD_SETSIZE)
		@throw [OFOutOfRangeException exception];
#endif

	FD_CLR((of_socket_t)fd, &_readFDs);

	[super removeObjectForReading: object];
}

- (void)removeObjectForWriting: (id <OFReadyForWritingObserving>)object
{
	/* TODO: Adjust _maxFD */

	int fd = object.fileDescriptorForWriting;

	if (fd < 0)
		@throw [OFObserveFailedException exceptionWithObserver: self
								 errNo: EBADF];


#ifndef OF_WINDOWS
	if (fd >= (int)FD_SETSIZE)
		@throw [OFOutOfRangeException exception];
#endif

	FD_CLR((of_socket_t)fd, &_writeFDs);

	[super removeObjectForWriting: object];
}

- (void)observeForTimeInterval: (of_time_interval_t)timeInterval
{
	id const *objects;
	fd_set readFDs;
	fd_set writeFDs;
	struct timeval timeout;
	int events;
#ifdef OF_AMIGAOS
	ULONG execSignalMask, cancelSignal;
#endif
	size_t count;

	if ([self of_processReadBuffers])
		return;

#ifdef FD_COPY
	FD_COPY(&_readFDs, &readFDs);
	FD_COPY(&_writeFDs, &writeFDs);
#else
	readFDs = _readFDs;
	writeFDs = _writeFDs;
#endif

	/*
	 * We cast to int before assigning to tv_usec in order to avoid a
	 * warning with Apple GCC on PowerPC. POSIX defines this as suseconds_t,
	 * however, this is not available on Win32. As an int should always
	 * satisfy the required range, we just cast to int.
	 */
#ifndef OF_WINDOWS
	timeout.tv_sec = (time_t)timeInterval;
#else
	timeout.tv_sec = (long)timeInterval;
#endif
	timeout.tv_usec = (int)((timeInterval - timeout.tv_sec) * 1000);

#ifdef OF_AMIGAOS
	if ((cancelSignal = AllocSignal(-1)) == (ULONG)-1)
		@throw [OFObserveFailedException exceptionWithObserver: self
								 errNo: EAGAIN];

	execSignalMask = _execSignalMask | (1ul << cancelSignal);

	Forbid();

	_waitingTask = FindTask(NULL);
	_cancelSignal = cancelSignal;

	events = WaitSelect(_maxFD + 1, &readFDs, &writeFDs, NULL,
	    (void *)(timeInterval != -1 ? &timeout : NULL), &execSignalMask);

	execSignalMask &= ~(1ul << cancelSignal);

	_waitingTask = NULL;
	FreeSignal(_cancelSignal);

	Permit();
#else
	events = select(_maxFD + 1, &readFDs, &writeFDs, NULL,
	    (timeInterval != -1 ? &timeout : NULL));
#endif

	if (events < 0)
		@throw [OFObserveFailedException exceptionWithObserver: self
								 errNo: errno];

#ifdef OF_AMIGAOS
	if (execSignalMask != 0 &&
	    [_delegate respondsToSelector: @selector(execSignalWasReceived:)])
		[_delegate execSignalWasReceived: execSignalMask];
#else
	if (FD_ISSET(_cancelFD[0], &readFDs)) {
		char buffer;

# ifdef OF_HAVE_PIPE
		OF_ENSURE(read(_cancelFD[0], &buffer, 1) == 1);
# else
		OF_ENSURE(recvfrom(_cancelFD[0], (void *)&buffer, 1, 0, NULL,
		    NULL) == 1);
# endif
	}
#endif

	objects = _readObjects.objects;
	count = _readObjects.count;

	for (size_t i = 0; i < count; i++) {
		void *pool = objc_autoreleasePoolPush();
		int fd = [objects[i] fileDescriptorForReading];

		if (FD_ISSET((of_socket_t)fd, &readFDs) &&
		    [_delegate respondsToSelector:
		    @selector(objectIsReadyForReading:)])
			[_delegate objectIsReadyForReading: objects[i]];

		objc_autoreleasePoolPop(pool);
	}

	objects = _writeObjects.objects;
	count = _writeObjects.count;

	for (size_t i = 0; i < count; i++) {
		void *pool = objc_autoreleasePoolPush();
		int fd = [objects[i] fileDescriptorForWriting];

		if (FD_ISSET((of_socket_t)fd, &writeFDs) &&
		    [_delegate respondsToSelector:
		    @selector(objectIsReadyForWriting:)])
			[_delegate objectIsReadyForWriting: objects[i]];

		objc_autoreleasePoolPop(pool);
	}
}
@end