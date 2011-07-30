/*
 * Copyright (c) 2008, 2009, 2010, 2011
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

#include "config.h"

#define __NO_EXT_QNX

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>

#include <assert.h>

#import "OFObject.h"
#import "OFArray.h"
#import "OFSet.h"
#import "OFIntrospection.h"
#import "OFAutoreleasePool.h"

#import "OFAllocFailedException.h"
#import "OFEnumerationMutationException.h"
#import "OFInitializationFailedException.h"
#import "OFInvalidArgumentException.h"
#import "OFMemoryNotPartOfObjectException.h"
#import "OFNotImplementedException.h"
#import "OFOutOfMemoryException.h"
#import "OFOutOfRangeException.h"

#import "macros.h"

#if defined(OF_OBJFW_RUNTIME)
# import <objfw-rt.h>
#elif defined(OF_OLD_GNU_RUNTIME)
# import <objc/sarray.h>
# import <objc/Protocol.h>
#endif

#ifdef _WIN32
# include <windows.h>
#endif

#import "OFString.h"

#if defined(OF_ATOMIC_OPS)
# import "atomic.h"
#elif defined(OF_THREADS)
# import "threading.h"
#endif

struct pre_ivar {
	void	      **memoryChunks;
	unsigned int  memoryChunksSize;
	int32_t	      retainCount;
#if !defined(OF_ATOMIC_OPS)
	of_spinlock_t retainCountSpinlock;
#endif
};

/* Hopefully no arch needs more than 16 bytes padding */
#ifndef __BIGGEST_ALIGNMENT__
# define __BIGGEST_ALIGNMENT__ 16
#endif

#define PRE_IVAR_ALIGN ((sizeof(struct pre_ivar) + \
	(__BIGGEST_ALIGNMENT__ - 1)) & ~(__BIGGEST_ALIGNMENT__ - 1))
#define PRE_IVAR ((struct pre_ivar*)(void*)((char*)self - PRE_IVAR_ALIGN))

static struct {
	Class isa;
} alloc_failed_exception;
static Class autoreleasePool = Nil;

static SEL cxx_construct = NULL;
static SEL cxx_destruct = NULL;

size_t of_pagesize;

#ifdef NEED_OBJC_SYNC_INIT
extern BOOL objc_sync_init();
#endif

#ifdef NEED_OBJC_PROPERTIES_INIT
extern BOOL objc_properties_init();
#endif

static void
enumeration_mutation_handler(id object)
{
	@throw [OFEnumerationMutationException newWithClass: [object class]
						     object: object];
}

#ifndef HAVE_OBJC_ENUMERATIONMUTATION
void
objc_enumerationMutation(id object)
{
	enumeration_mutation_handler(object);
}
#endif

const char*
_NSPrintForDebugger(id object)
{
	return [[object description] cString];
}

/* References for static linking */
void _references_to_categories_of_OFObject(void)
{
	_OFObject_Serialization_reference = 1;
}

@implementation OFObject
+ (void)load
{
#ifdef NEED_OBJC_SYNC_INIT
	if (!objc_sync_init()) {
		fputs("Runtime error: objc_sync_init() failed!\n", stderr);
		abort();
	}
#endif

#ifdef NEED_OBJC_PROPERTIES_INIT
	if (!objc_properties_init()) {
		fputs("Runtime error: objc_properties_init() failed!\n",
		    stderr);
		abort();
	}
#endif

#if defined(OF_APPLE_RUNTIME) || defined(OF_GNU_RUNTIME)
	objc_setEnumerationMutationHandler(enumeration_mutation_handler);
#endif

	cxx_construct = sel_registerName(".cxx_construct");
	cxx_destruct = sel_registerName(".cxx_destruct");

	if (cxx_construct == NULL || cxx_destruct == NULL) {
		fputs("Runtime error: Failed to register selector "
		    ".cxx_construct and/or .cxx_destruct!\n", stderr);
		abort();
	}

#if defined(_WIN32)
	SYSTEM_INFO si;
	GetSystemInfo(&si);
	of_pagesize = si.dwPageSize;
#elif defined(_PSP)
	of_pagesize = 4096;
#else
	if ((of_pagesize = sysconf(_SC_PAGESIZE)) < 1)
		of_pagesize = 4096;
#endif
}

+ (void)initialize
{
}

+ alloc
{
	OFObject *instance;
	size_t instanceSize = class_getInstanceSize(self);
	Class class;
	void (*last)(id, SEL) = NULL;

	if ((instance = malloc(instanceSize + PRE_IVAR_ALIGN)) == NULL) {
		alloc_failed_exception.isa = [OFAllocFailedException class];
		@throw (OFAllocFailedException*)&alloc_failed_exception;
	}

	((struct pre_ivar*)instance)->memoryChunks = NULL;
	((struct pre_ivar*)instance)->memoryChunksSize = 0;
	((struct pre_ivar*)instance)->retainCount = 1;

#if !defined(OF_ATOMIC_OPS)
	if (!of_spinlock_new(
	    &((struct pre_ivar*)instance)->retainCountSpinlock)) {
		free(instance);
		@throw [OFInitializationFailedException newWithClass: self];
	}
#endif

	instance = (OFObject*)((char*)instance + PRE_IVAR_ALIGN);
	memset(instance, 0, instanceSize);
	instance->isa = self;

	for (class = self; class != Nil; class = class_getSuperclass(class)) {
		void (*construct)(id, SEL);

		if ([class instancesRespondToSelector: cxx_construct]) {
			if ((construct = (void(*)(id, SEL))[class
			    instanceMethodForSelector: cxx_construct]) != last)
				construct(instance, cxx_construct);

			last = construct;
		} else
			break;
	}

	return instance;
}

+ new
{
	return [[self alloc] init];
}

+ (Class)class
{
	return self;
}

+ (OFString*)className
{
	return [OFString stringWithCString: class_getName(self)];
}

+ (BOOL)isSubclassOfClass: (Class)class
{
	Class iter;

	for (iter = self; iter != Nil; iter = class_getSuperclass(iter))
		if (iter == class)
			return YES;

	return NO;
}

+ (Class)superclass
{
	return class_getSuperclass(self);
}

+ (BOOL)instancesRespondToSelector: (SEL)selector
{
#ifdef OF_OLD_GNU_RUNTIME
	return class_get_instance_method(self, selector) != METHOD_NULL;
#else
	return class_respondsToSelector(self, selector);
#endif
}

+ (BOOL)conformsToProtocol: (Protocol*)protocol
{
#ifdef OF_OLD_GNU_RUNTIME
	Class c;
	struct objc_protocol_list *pl;
	size_t i;

	for (c = self; c != Nil; c = class_get_super_class(c))
		for (pl = c->protocols; pl != NULL; pl = pl->next)
			for (i = 0; i < pl->count; i++)
				if ([pl->list[i] conformsTo: protocol])
					return YES;

	return NO;
#else
	Class c;

	for (c = self; c != Nil; c = class_getSuperclass(c))
		if (class_conformsToProtocol(c, protocol))
			return YES;

	return NO;
#endif
}

+ (IMP)instanceMethodForSelector: (SEL)selector
{
#if defined(OF_OBJFW_RUNTIME)
	return objc_get_instance_method(self, selector);
#elif defined(OF_OLD_GNU_RUNTIME)
	return method_get_imp(class_get_instance_method(self, selector));
#else
	return class_getMethodImplementation(self, selector);
#endif
}

+ (const char*)typeEncodingForInstanceSelector: (SEL)selector
{
#if defined(OF_OBJFW_RUNTIME)
	const char *ret;

	if ((ret = objc_get_type_encoding(self, selector)) == NULL)
		@throw [OFNotImplementedException newWithClass: self
						      selector: selector];

	return ret;
#elif defined(OF_OLD_GNU_RUNTIME)
	Method_t m;

	if ((m = class_get_instance_method(self, selector)) == NULL ||
	    m->method_types == NULL)
		@throw [OFNotImplementedException newWithClass: self
						      selector: selector];

	return m->method_types;
#else
	Method m;
	const char *ret;

	if ((m = class_getInstanceMethod(self, selector)) == NULL ||
	    (ret = method_getTypeEncoding(m)) == NULL)
		@throw [OFNotImplementedException newWithClass: self
						      selector: selector];

	return ret;
#endif
}

+ (OFString*)description
{
	return [self className];
}

+ (IMP)setImplementation: (IMP)newImp
	  forClassMethod: (SEL)selector
{
#if defined(OF_OBJFW_RUNTIME)
	if (newImp == (IMP)0 || !class_respondsToSelector(self->isa, selector))
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	return objc_replace_class_method(self, selector, newImp);
#elif defined(OF_OLD_GNU_RUNTIME)
	Method_t method;
	IMP oldImp;

	/* The class method is the instance method of the meta class */
	if ((method = class_get_instance_method(self->class_pointer,
	    selector)) == NULL)
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	if ((oldImp = method_get_imp(method)) == (IMP)0 || newImp == (IMP)0)
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	method->method_imp = newImp;

	/* Update the dtable if necessary */
	if (sarray_get_safe(((Class)self->class_pointer)->dtable,
	    (sidx)method->method_name->sel_id))
		sarray_at_put_safe(((Class)self->class_pointer)->dtable,
		    (sidx)method->method_name->sel_id, method->method_imp);

	return oldImp;
#else
	Method method;

	if (newImp == (IMP)0 ||
	    (method = class_getClassMethod(self, selector)) == NULL)
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	/*
	 * Cast needed because it's isa in the Apple runtime, but class_pointer
	 * in the GNU runtime.
	 */
	return class_replaceMethod(((OFObject*)self)->isa, selector, newImp,
	    method_getTypeEncoding(method));
#endif
}

+ (IMP)replaceClassMethod: (SEL)selector
      withMethodFromClass: (Class)class
{
	IMP newImp;

	if (![class isSubclassOfClass: self])
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	newImp = [class methodForSelector: selector];

	return [self setImplementation: newImp
			forClassMethod: selector];
}

+ (IMP)setImplementation: (IMP)newImp
       forInstanceMethod: (SEL)selector
{
#if defined(OF_OBJFW_RUNTIME)
	if (newImp == (IMP)0 || !class_respondsToSelector(self, selector))
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	return objc_replace_instance_method(self, selector, newImp);
#elif defined(OF_OLD_GNU_RUNTIME)
	Method_t method = class_get_instance_method(self, selector);
	IMP oldImp;

	if (method == NULL)
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	if ((oldImp = method_get_imp(method)) == (IMP)0 || newImp == (IMP)0)
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	method->method_imp = newImp;

	/* Update the dtable if necessary */
	if (sarray_get_safe(((Class)self)->dtable,
	    (sidx)method->method_name->sel_id))
		sarray_at_put_safe(((Class)self)->dtable,
		    (sidx)method->method_name->sel_id, method->method_imp);

	return oldImp;
#else
	Method method;

	if (newImp == (IMP)0 ||
	    (method = class_getInstanceMethod(self, selector)) == NULL)
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	return class_replaceMethod(self, selector, newImp,
	    method_getTypeEncoding(method));
#endif
}

+ (IMP)replaceInstanceMethod: (SEL)selector
	 withMethodFromClass: (Class)class
{
	IMP newImp;

	if (![class isSubclassOfClass: self])
		@throw [OFInvalidArgumentException newWithClass: self
						       selector: _cmd];

	newImp = [class instanceMethodForSelector: selector];

	return [self setImplementation: newImp
		     forInstanceMethod: selector];
}

+ (BOOL)addInstanceMethod: (SEL)selector
	 withTypeEncoding: (const char*)typeEncoding
	   implementation: (IMP)implementation
{
#if defined(OF_APPLE_RUNTIME) || defined(OF_GNU_RUNTIME)
	return class_addMethod(self, selector, implementation, typeEncoding);
#elif defined(OF_OLD_GNU_RUNTIME)
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
#endif
}

+ (void)inheritInstanceMethodsFromClass: (Class)class
{
	OFAutoreleasePool *pool = [[OFAutoreleasePool alloc] init];
	OFMutableSet *set = [OFMutableSet set];
	OFIntrospection *introspection;
	OFMethod **cArray;
	size_t i, count;

	introspection = [OFIntrospection introspectionWithClass: self];
	cArray = [[introspection instanceMethods] cArray];
	count = [[introspection instanceMethods] count];

	for (i = 0; i < count; i++)
		[set addObject: [cArray[i] name]];

	introspection = [OFIntrospection introspectionWithClass: class];
	cArray = [[introspection instanceMethods] cArray];
	count = [[introspection instanceMethods] count];

	for (i = 0; i < count; i++) {
		SEL selector;
		IMP implementation;

		if ([set containsObject: [cArray[i] name]])
			continue;

		selector = [cArray[i] selector];
		implementation = [class instanceMethodForSelector: selector];

		if ([self respondsToSelector: selector])
			[self setImplementation: implementation
			      forInstanceMethod: selector];
		else
			[self addInstanceMethod: selector
			       withTypeEncoding: [cArray[i] typeEncoding]
				 implementation: implementation];
	}

	[pool release];
}

- init
{
	return self;
}

- (Class)class
{
	return isa;
}

- (OFString*)className
{
	return [OFString stringWithCString: class_getName(isa)];
}

- (BOOL)isKindOfClass: (Class)class
{
	Class iter;

	for (iter = isa; iter != Nil; iter = class_getSuperclass(iter))
		if (iter == class)
			return YES;

	return NO;
}

- (BOOL)respondsToSelector: (SEL)selector
{
#ifdef OF_OLD_GNU_RUNTIME
	if (object_is_instance(self))
		return class_get_instance_method(isa, selector) != METHOD_NULL;
	else
		return class_get_class_method(isa, selector) != METHOD_NULL;
#else
	return class_respondsToSelector(isa, selector);
#endif
}

- (BOOL)conformsToProtocol: (Protocol*)protocol
{
	return [isa conformsToProtocol: protocol];
}

- (IMP)methodForSelector: (SEL)selector
{
#if defined(OF_OBJFW_RUNTIME) || defined(OF_OLD_GNU_RUNTIME)
	return objc_msg_lookup(self, selector);
#else
	return class_getMethodImplementation(isa, selector);
#endif
}

- (id)performSelector: (SEL)selector
{
	id (*imp)(id, SEL) = (id(*)(id, SEL))[self methodForSelector: selector];

	return imp(self, selector);
}

- (id)performSelector: (SEL)selector
	   withObject: (id)object
{
	id (*imp)(id, SEL, id) =
	    (id(*)(id, SEL, id))[self methodForSelector: selector];

	return imp(self, selector, object);
}

- (id)performSelector: (SEL)selector
	   withObject: (id)object
	   withObject: (id)otherObject
{
	id (*imp)(id, SEL, id, id) =
	    (id(*)(id, SEL, id, id))[self methodForSelector: selector];

	return imp(self, selector, object, otherObject);
}

- (const char*)typeEncodingForSelector: (SEL)selector
{
#if defined(OF_OBJFW_RUNTIME)
	const char *ret;

	if ((ret = objc_get_type_encoding(isa, selector)) == NULL)
		@throw [OFNotImplementedException newWithClass: isa
						      selector: selector];

	return ret;
#elif defined(OF_OLD_GNU_RUNTIME)
	Method_t m;

	if ((m = class_get_instance_method(isa, selector)) == NULL ||
	    m->method_types == NULL)
		@throw [OFNotImplementedException newWithClass: isa
						      selector: selector];

	return m->method_types;
#else
	Method m;
	const char *ret;

	if ((m = class_getInstanceMethod(isa, selector)) == NULL ||
	    (ret = method_getTypeEncoding(m)) == NULL)
		@throw [OFNotImplementedException newWithClass: isa
						      selector: selector];

	return ret;
#endif
}

- (BOOL)isEqual: (id)object
{
	/* Classes containing data should reimplement this! */
	return (self == object);
}

- (uint32_t)hash
{
	/* Classes containing data should reimplement this! */
	return (uint32_t)(uintptr_t)self;
}

- (OFString*)description
{
	/* Classes containing data should reimplement this! */
	return [OFString stringWithFormat: @"<%@: %p>", [self className], self];
}

- (void)addMemoryToPool: (void*)pointer
{
	void **memoryChunks;
	unsigned int memoryChunksSize;

	memoryChunksSize = PRE_IVAR->memoryChunksSize + 1;

	if (UINT_MAX - PRE_IVAR->memoryChunksSize < 1 ||
	    memoryChunksSize > UINT_MAX / sizeof(void*))
		@throw [OFOutOfRangeException newWithClass: isa];

	if ((memoryChunks = realloc(PRE_IVAR->memoryChunks,
	    memoryChunksSize * sizeof(void*))) == NULL)
		@throw [OFOutOfMemoryException newWithClass: isa
					      requestedSize: memoryChunksSize];

	PRE_IVAR->memoryChunks = memoryChunks;
	PRE_IVAR->memoryChunks[PRE_IVAR->memoryChunksSize] = pointer;
	PRE_IVAR->memoryChunksSize = memoryChunksSize;
}

- (void*)allocMemoryWithSize: (size_t)size
{
	void *pointer, **memoryChunks;
	unsigned int memoryChunksSize;

	if (size == 0)
		return NULL;

	memoryChunksSize = PRE_IVAR->memoryChunksSize + 1;

	if (UINT_MAX - PRE_IVAR->memoryChunksSize == 0 ||
	    memoryChunksSize > UINT_MAX / sizeof(void*))
		@throw [OFOutOfRangeException newWithClass: isa];

	if ((pointer = malloc(size)) == NULL)
		@throw [OFOutOfMemoryException newWithClass: isa
					      requestedSize: size];

	if ((memoryChunks = realloc(PRE_IVAR->memoryChunks,
	    memoryChunksSize * sizeof(void*))) == NULL) {
		free(pointer);
		@throw [OFOutOfMemoryException newWithClass: isa
					      requestedSize: memoryChunksSize];
	}

	PRE_IVAR->memoryChunks = memoryChunks;
	PRE_IVAR->memoryChunks[PRE_IVAR->memoryChunksSize] = pointer;
	PRE_IVAR->memoryChunksSize = memoryChunksSize;

	return pointer;
}

- (void*)allocMemoryForNItems: (size_t)nItems
		     withSize: (size_t)size
{
	if (nItems == 0 || size == 0)
		return NULL;

	if (nItems > SIZE_MAX / size)
		@throw [OFOutOfRangeException newWithClass: isa];

	return [self allocMemoryWithSize: nItems * size];
}

- (void*)resizeMemory: (void*)pointer
	       toSize: (size_t)size
{
	void **iter;

	if (pointer == NULL)
		return [self allocMemoryWithSize: size];

	if (size == 0) {
		[self freeMemory: pointer];
		return NULL;
	}

	iter = PRE_IVAR->memoryChunks + PRE_IVAR->memoryChunksSize;

	while (iter-- > PRE_IVAR->memoryChunks) {
		if (OF_UNLIKELY(*iter == pointer)) {
			if (OF_UNLIKELY((pointer = realloc(pointer,
			    size)) == NULL))
				@throw [OFOutOfMemoryException
				     newWithClass: isa
				    requestedSize: size];

			*iter = pointer;
			return pointer;
		}
	}

	@throw [OFMemoryNotPartOfObjectException newWithClass: isa
						      pointer: pointer];
}

- (void*)resizeMemory: (void*)pointer
	     toNItems: (size_t)nItems
	     withSize: (size_t)size
{
	if (pointer == NULL)
		return [self allocMemoryForNItems: nItems
					 withSize: size];

	if (nItems == 0 || size == 0) {
		[self freeMemory: pointer];
		return NULL;
	}

	if (nItems > SIZE_MAX / size)
		@throw [OFOutOfRangeException newWithClass: isa];

	return [self resizeMemory: pointer
			   toSize: nItems * size];
}

- (void)freeMemory: (void*)pointer
{
	void **iter, *last, **memoryChunks;
	unsigned int i, memoryChunksSize;

	if (pointer == NULL)
		return;

	iter = PRE_IVAR->memoryChunks + PRE_IVAR->memoryChunksSize;
	i = PRE_IVAR->memoryChunksSize;

	while (iter-- > PRE_IVAR->memoryChunks) {
		i--;

		if (OF_UNLIKELY(*iter == pointer)) {
			memoryChunksSize = PRE_IVAR->memoryChunksSize - 1;
			last = PRE_IVAR->memoryChunks[memoryChunksSize];

			assert(PRE_IVAR->memoryChunksSize != 0 &&
			    memoryChunksSize <= UINT_MAX / sizeof(void*));

			if (OF_UNLIKELY(memoryChunksSize == 0)) {
				free(pointer);
				free(PRE_IVAR->memoryChunks);

				PRE_IVAR->memoryChunks = NULL;
				PRE_IVAR->memoryChunksSize = 0;

				return;
			}

			free(pointer);
			PRE_IVAR->memoryChunks[i] = last;
			PRE_IVAR->memoryChunksSize = memoryChunksSize;

			if (OF_UNLIKELY((memoryChunks = realloc(
			    PRE_IVAR->memoryChunks, memoryChunksSize *
			    sizeof(void*))) == NULL))
				return;

			PRE_IVAR->memoryChunks = memoryChunks;

			return;
		}
	}

	@throw [OFMemoryNotPartOfObjectException newWithClass: isa
						      pointer: pointer];
}

- retain
{
#if defined(OF_ATOMIC_OPS)
	of_atomic_inc_32(&PRE_IVAR->retainCount);
#else
	assert(of_spinlock_lock(&PRE_IVAR->retainCountSpinlock));
	PRE_IVAR->retainCount++;
	assert(of_spinlock_unlock(&PRE_IVAR->retainCountSspinlock));
#endif

	return self;
}

- (unsigned int)retainCount
{
	assert(PRE_IVAR->retainCount >= 0);
	return PRE_IVAR->retainCount;
}

- (void)release
{
#if defined(OF_ATOMIC_OPS)
	if (of_atomic_dec_32(&PRE_IVAR->retainCount) <= 0)
		[self dealloc];
#else
	size_t c;

	assert(of_spinlock_lock(&PRE_IVAR->retainCountSpinlock));
	c = --PRE_IVAR->retainCount;
	assert(of_spinlock_unlock(&PRE_IVAR->retainCountSpinlock));

	if (!c)
		[self dealloc];
#endif
}

- autorelease
{
	/*
	 * Cache OFAutoreleasePool since class lookups are expensive with the
	 * GNU runtime.
	 */
	if (autoreleasePool == Nil)
		autoreleasePool = [OFAutoreleasePool class];

	[autoreleasePool addObject: self];

	return self;
}

- self
{
	return self;
}

- (void)dealloc
{
	Class class;
	void (*last)(id, SEL) = NULL;
	void **iter;

	for (class = isa; class != Nil; class = class_getSuperclass(class)) {
		void (*destruct)(id, SEL);

		if ([class instancesRespondToSelector: cxx_destruct]) {
			if ((destruct = (void(*)(id, SEL))[class
			    instanceMethodForSelector: cxx_destruct]) != last)
				destruct(self, cxx_destruct);

			last = destruct;
		} else
			break;
	}

	iter = PRE_IVAR->memoryChunks + PRE_IVAR->memoryChunksSize;
	while (iter-- > PRE_IVAR->memoryChunks)
		free(*iter);

	if (PRE_IVAR->memoryChunks != NULL)
		free(PRE_IVAR->memoryChunks);

	free((char*)self - PRE_IVAR_ALIGN);
}

- (void)finalize
{
	Class class;
	void (*last)(id, SEL) = NULL;
	void **iter;

	for (class = isa; class != Nil; class = class_getSuperclass(class)) {
		void (*destruct)(id, SEL);

		if ([class instancesRespondToSelector: cxx_destruct]) {
			if ((destruct = (void(*)(id, SEL))[class
			    instanceMethodForSelector: cxx_destruct]) != last)
				destruct(self, cxx_destruct);

			last = destruct;
		} else
			break;
	}

	iter = PRE_IVAR->memoryChunks + PRE_IVAR->memoryChunksSize;
	while (iter-- > PRE_IVAR->memoryChunks)
		free(*iter);

	if (PRE_IVAR->memoryChunks != NULL)
		free(PRE_IVAR->memoryChunks);
}

/* Required to use properties with the Apple runtime */
- copyWithZone: (void*)zone
{
	if (zone != NULL)
		@throw [OFNotImplementedException newWithClass: isa
						      selector: _cmd];

	return [(id)self copy];
}

- mutableCopyWithZone: (void*)zone
{
	if (zone != NULL)
		@throw [OFNotImplementedException newWithClass: isa
						      selector: _cmd];

	return [(id)self mutableCopy];
}

/*
 * Those are needed as the root class is the superclass of the root class's
 * metaclass and thus instance methods can be sent to class objects as well.
 */
+ (void)addMemoryToPool: (void*)pointer
{
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
}

+ (void*)allocMemoryWithSize: (size_t)size
{
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
}

+ (void*)allocMemoryForNItems: (size_t)nItems
		     withSize: (size_t)size
{
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
}

+ (void*)resizeMemory: (void*)pointer
	       toSize: (size_t)size
{
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
}

+ (void*)resizeMemory: (void*)pointer
	     toNItems: (size_t)nItems
	     withSize: (size_t)size
{
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
}

+ (void)freeMemory: (void*)pointer
{
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
}

+ retain
{
	return self;
}

+ autorelease
{
	return self;
}

+ (unsigned int)retainCount
{
	return OF_RETAIN_COUNT_MAX;
}

+ (void)release
{
}

+ (void)dealloc
{
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
}

+ copyWithZone: (void*)zone
{
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
}

+ mutableCopyWithZone: (void*)zone
{
	@throw [OFNotImplementedException newWithClass: self
					      selector: _cmd];
}
@end
