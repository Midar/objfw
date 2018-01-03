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

#include <string.h>

#import "OFApplication.h"
#import "OFArray.h"
#import "OFFile.h"
#import "OFFileManager.h"
#import "OFLocalization.h"
#import "OFOptionsParser.h"
#import "OFSandbox.h"
#import "OFStdIOStream.h"
#import "OFURL.h"

#import "OFZIP.h"
#import "GZIPArchive.h"
#import "TarArchive.h"
#import "ZIPArchive.h"

#import "OFCreateDirectoryFailedException.h"
#import "OFInvalidArgumentException.h"
#import "OFInvalidFormatException.h"
#import "OFNotImplementedException.h"
#import "OFOpenItemFailedException.h"
#import "OFReadFailedException.h"
#import "OFSeekFailedException.h"
#import "OFWriteFailedException.h"

#define BUFFER_SIZE 4096

OF_APPLICATION_DELEGATE(OFZIP)

static void
help(OFStream *stream, bool full, int status)
{
	[stream writeLine: OF_LOCALIZED(@"usage",
	    @"Usage: %[prog] -[acCfhlnpqtvx] archive.zip [file1 file2 ...]",
	    @"prog", [OFApplication programName])];

	if (full) {
		[stream writeString: @"\n"];
		[stream writeLine: OF_LOCALIZED(@"full_usage",
		    @"Options:\n"
		    @"    -a  --append      Append to archive\n"
		    @"    -c  --create      Create archive\n"
		    @"    -C  --directory   Extract into the specified "
		    @"directory\n"
		    @"    -f  --force       Force / overwrite files\n"
		    @"    -h  --help        Show this help\n"
		    @"    -l  --list        List all files in the archive\n"
		    @"    -n  --no-clobber  Never overwrite files\n"
		    @"    -p  --print       Print one or more files from the "
		    @"archive\n"
		    @"    -q  --quiet       Quiet mode (no output, except "
		    @"errors)\n"
		    @"    -t  --type        Archive type (gz, tar, tgz, zip)\n"
		    @"    -v  --verbose     Verbose output for file list\n"
		    @"    -x  --extract     Extract files")];
	}

	[OFApplication terminateWithStatus: status];
}

static void
mutuallyExclusiveError(of_unichar_t shortOption1, OFString *longOption1,
    of_unichar_t shortOption2, OFString *longOption2)
{
	OFString *shortOption1Str = [OFString stringWithFormat: @"%C",
								shortOption1];
	OFString *shortOption2Str = [OFString stringWithFormat: @"%C",
								shortOption2];

	[of_stderr writeLine: OF_LOCALIZED(@"2_options_mutually_exclusive",
	    @"Error: -%[shortopt1] / --%[longopt1] and "
	    @"-%[shortopt2] / --%[longopt2] "
	    @"are mutually exclusive!",
	    @"shortopt1", shortOption1Str,
	    @"longopt1", longOption1,
	    @"shortopt2", shortOption2Str,
	    @"longopt2", longOption2)];
	[OFApplication terminateWithStatus: 1];
}

static void
mutuallyExclusiveError5(of_unichar_t shortOption1, OFString *longOption1,
    of_unichar_t shortOption2, OFString *longOption2,
    of_unichar_t shortOption3, OFString *longOption3,
    of_unichar_t shortOption4, OFString *longOption4,
    of_unichar_t shortOption5, OFString *longOption5)
{
	OFString *shortOption1Str = [OFString stringWithFormat: @"%C",
								shortOption1];
	OFString *shortOption2Str = [OFString stringWithFormat: @"%C",
								shortOption2];
	OFString *shortOption3Str = [OFString stringWithFormat: @"%C",
								shortOption3];
	OFString *shortOption4Str = [OFString stringWithFormat: @"%C",
								shortOption4];
	OFString *shortOption5Str = [OFString stringWithFormat: @"%C",
								shortOption5];

	[of_stderr writeLine: OF_LOCALIZED(@"5_options_mutually_exclusive",
	    @"Error: -%[shortopt1] / --%[longopt1], "
	    @"-%[shortopt2] / --%[longopt2], -%[shortopt3] / --%[longopt3], "
	    @"-%[shortopt4] / --%[longopt4] and\n"
	    @"       -%[shortopt5] / --%[longopt5] are mutually exclusive!",
	    @"shortopt1", shortOption1Str,
	    @"longopt1", longOption1,
	    @"shortopt2", shortOption2Str,
	    @"longopt2", longOption2,
	    @"shortopt3", shortOption3Str,
	    @"longopt3", longOption3,
	    @"shortopt4", shortOption4Str,
	    @"longopt4", longOption4,
	    @"shortopt5", shortOption5Str,
	    @"longopt5", longOption5)];
	[OFApplication terminateWithStatus: 1];
}

static void
writingNotSupported(OFString *type)
{
	[of_stderr writeLine: OF_LOCALIZED(
	    @"writing_not_supported",
	    @"Writing archives of type %[type] is not (yet) supported!",
	    @"type", type)];
}

@implementation OFZIP
- (void)applicationDidFinishLaunching
{
	OFString *outputDir = nil, *type = nil;
	const of_options_parser_option_t options[] = {
		{ 'a', @"append", 0, NULL, NULL },
		{ 'c', @"create", 0, NULL, NULL },
		{ 'C', @"directory", 1, NULL, &outputDir },
		{ 'f', @"force", 0, NULL, NULL },
		{ 'h', @"help", 0, NULL, NULL },
		{ 'l', @"list", 0, NULL, NULL },
		{ 'n', @"no-clobber", 0, NULL, NULL },
		{ 'p', @"print", 0, NULL, NULL },
		{ 'q', @"quiet", 0, NULL, NULL },
		{ 't', @"type", 1, NULL, &type },
		{ 'v', @"verbose", 0, NULL, NULL },
		{ 'x', @"extract", 0, NULL, NULL },
		{ '\0', nil, 0, NULL, NULL }
	};
	OFOptionsParser *optionsParser;
	of_unichar_t option, mode = '\0';
	OFArray OF_GENERIC(OFString *) *remainingArguments, *files;
	id <Archive> archive;

#ifdef OF_HAVE_SANDBOX
	OFSandbox *sandbox = [[OFSandbox alloc] init];
	@try {
		[sandbox setAllowsStdIO: true];
		[sandbox setAllowsReadingFiles: true];
		[sandbox setAllowsWritingFiles: true];
		[sandbox setAllowsCreatingFiles: true];
		[sandbox setAllowsChangingFileAttributes: true];
		[sandbox setAllowsUserDatabaseReading: true];

		[OFApplication activateSandbox: sandbox];
	} @finally {
		[sandbox release];
	}
#endif

#ifndef OF_MORPHOS
	[OFLocalization addLanguageDirectory: @LANGUAGE_DIR];
#else
	[OFLocalization addLanguageDirectory: @"PROGDIR:/share/ofzip/lang"];
#endif

	optionsParser = [OFOptionsParser parserWithOptions: options];
	while ((option = [optionsParser nextOption]) != '\0') {
		switch (option) {
		case 'f':
			if (_overwrite < 0)
				mutuallyExclusiveError(
				    'f', @"force", 'n', @"no-clobber");

			_overwrite = 1;
			break;
		case 'n':
			if (_overwrite > 0)
				mutuallyExclusiveError(
				    'f', @"force", 'n', @"no-clobber");

			_overwrite = -1;
			break;
		case 'v':
			if (_outputLevel < 0)
				mutuallyExclusiveError(
				    'q', @"quiet", 'v', @"verbose");

			_outputLevel++;
			break;
		case 'q':
			if (_outputLevel > 0)
				mutuallyExclusiveError(
				    'q', @"quiet", 'v', @"verbose");

			_outputLevel--;
			break;
		case 'a':
		case 'c':
		case 'l':
		case 'p':
		case 'x':
			if (mode != '\0')
				mutuallyExclusiveError5(
				    'a', @"append",
				    'c', @"create",
				    'l', @"list",
				    'p', @"print",
				    'x', @"extract");

			mode = option;
			break;
		case 'h':
			help(of_stdout, true, 0);
			break;
		case '=':
			[of_stderr writeLine: OF_LOCALIZED(
			    @"option_takes_no_argument",
			    @"%[prog]: Option --%[opt] takes no argument",
			    @"prog", [OFApplication programName],
			    @"opt", [optionsParser lastLongOption])];

			[OFApplication terminateWithStatus: 1];
			break;
		case '?':
			if ([optionsParser lastLongOption] != nil)
				[of_stderr writeLine: OF_LOCALIZED(
				    @"unknown_long_option",
				    @"%[prog]: Unknown option: --%[opt]",
				    @"prog", [OFApplication programName],
				    @"opt", [optionsParser lastLongOption])];
			else {
				OFString *optStr = [OFString
				    stringWithFormat: @"%c",
				    [optionsParser lastOption]];
				[of_stderr writeLine: OF_LOCALIZED(
				    @"unknown_option",
				    @"%[prog]: Unknown option: -%[opt]",
				    @"prog", [OFApplication programName],
				    @"opt", optStr)];
			}

			[OFApplication terminateWithStatus: 1];
		}
	}

	remainingArguments = [optionsParser remainingArguments];
	archive = [self openArchiveWithPath: [remainingArguments firstObject]
				       type: type
				       mode: mode];

	if (outputDir != nil)
		[[OFFileManager defaultManager]
		    changeCurrentDirectoryPath: outputDir];

	switch (mode) {
	case 'a':
	case 'c':
		if ([remainingArguments count] < 1)
			help(of_stderr, false, 1);

		files = [remainingArguments objectsInRange:
		    of_range(1, [remainingArguments count] - 1)];

		[archive addFiles: files];
		break;
	case 'l':
		if ([remainingArguments count] != 1)
			help(of_stderr, false, 1);

		[archive listFiles];
		break;
	case 'p':
		if ([remainingArguments count] < 1)
			help(of_stderr, false, 1);

		files = [remainingArguments objectsInRange:
		    of_range(1, [remainingArguments count] - 1)];

		[archive printFiles: files];
		break;
	case 'x':
		if ([remainingArguments count] < 1)
			help(of_stderr, false, 1);

		files = [remainingArguments objectsInRange:
		    of_range(1, [remainingArguments count] - 1)];

		@try {
			[archive extractFiles: files];
		} @catch (OFCreateDirectoryFailedException *e) {
			OFString *error = [OFString
			    stringWithCString: strerror([e errNo])
				     encoding: [OFLocalization encoding]];
			[of_stderr writeString: @"\r"];
			[of_stderr writeLine: OF_LOCALIZED(
			    @"failed_to_create_directory",
			    @"Failed to create directory %[dir]: %[error]",
			    @"dir", [[e URL] fileSystemRepresentation],
			    @"error", error)];
			_exitStatus = 1;
		} @catch (OFOpenItemFailedException *e) {
			OFString *error = [OFString
			    stringWithCString: strerror([e errNo])
				     encoding: [OFLocalization encoding]];
			[of_stderr writeString: @"\r"];
			[of_stderr writeLine: OF_LOCALIZED(
			    @"failed_to_open_file",
			    @"Failed to open file %[file]: %[error]",
			    @"file", [e path],
			    @"error", error)];
			_exitStatus = 1;
		}

		break;
	default:
		help(of_stderr, true, 1);
		break;
	}

	[OFApplication terminateWithStatus: _exitStatus];
}

- (id <Archive>)openArchiveWithPath: (OFString *)path
			       type: (OFString *)type
			       mode: (char)mode
{
	OFString *modeString, *fileModeString;
	OFFile *file = nil;
	id <Archive> archive = nil;

	[_archivePath release];
	_archivePath = [path copy];

	if (path == nil)
		return nil;

	switch (mode) {
	case 'a':
		modeString = @"a";
		fileModeString = @"r+";
		break;
	case 'c':
		modeString = fileModeString = @"w";
		break;
	case 'l':
	case 'p':
	case 'x':
		modeString = fileModeString = @"r";
		break;
	default:
		@throw [OFInvalidArgumentException exception];
	}

	@try {
		file = [OFFile fileWithPath: path
				       mode: fileModeString];
	} @catch (OFOpenItemFailedException *e) {
		OFString *error = [OFString
		    stringWithCString: strerror([e errNo])
			     encoding: [OFLocalization encoding]];
		[of_stderr writeString: @"\r"];
		[of_stderr writeLine: OF_LOCALIZED(
		    @"failed_to_open_file",
		    @"Failed to open file %[file]: %[error]",
		    @"file", [e path],
		    @"error", error)];
		[OFApplication terminateWithStatus: 1];
	}

	if (type == nil || [type isEqual: @"auto"]) {
		/* This one has to be first for obvious reasons */
		if ([path hasSuffix: @".tar.gz"] || [path hasSuffix: @".tgz"] ||
		    [path hasSuffix: @".TAR.GZ"] || [path hasSuffix: @".TGZ"])
			type = @"tgz";
		else if ([path hasSuffix: @".gz"] || [path hasSuffix: @".GZ"])
			type = @"gz";
		else if ([path hasSuffix: @".tar"] || [path hasSuffix: @".TAR"])
			type = @"tar";
		else
			type = @"zip";
	}

	@try {
		if ([type isEqual: @"gz"])
			archive = [GZIPArchive archiveWithStream: file
							    mode: modeString];
		else if ([type isEqual: @"tar"])
			archive = [TarArchive archiveWithStream: file
							   mode: modeString];
		else if ([type isEqual: @"tgz"]) {
			OFStream *GZIPStream = [OFGZIPStream
			    streamWithStream: file
					mode: modeString];
			archive = [TarArchive archiveWithStream: GZIPStream
							   mode: modeString];
		} else if ([type isEqual: @"zip"])
			archive = [ZIPArchive archiveWithStream: file
							   mode: modeString];
		else {
			[of_stderr writeLine: OF_LOCALIZED(
			    @"unknown_archive_type",
			    @"Unknown archive type: %[type]",
			    @"type", type)];
			goto error;
		}
	} @catch (OFNotImplementedException *e) {
		if ((mode == 'a' || mode == 'c') &&
		    sel_isEqual([e selector],
		    @selector(initWithStream:mode:))) {
			writingNotSupported(type);
			goto error;
		}

		@throw e;
	} @catch (OFReadFailedException *e) {
		OFString *error = [OFString
		    stringWithCString: strerror([e errNo])
			     encoding: [OFLocalization encoding]];
		[of_stderr writeLine: OF_LOCALIZED(@"failed_to_read_file",
		    @"Failed to read file %[file]: %[error]",
		    @"file", path,
		    @"error", error)];
		goto error;
	} @catch (OFSeekFailedException *e) {
		OFString *error = [OFString
		    stringWithCString: strerror([e errNo])
			     encoding: [OFLocalization encoding]];
		[of_stderr writeLine: OF_LOCALIZED(@"failed_to_seek_in_file",
		    @"Failed to seek in file %[file]: %[error]",
		    @"file", path,
		    @"error", error)];
		goto error;
	} @catch (OFInvalidFormatException *e) {
		[of_stderr writeLine: OF_LOCALIZED(
		    @"file_is_not_a_valid_archive",
		    @"File %[file] is not a valid archive!",
		    @"file", path)];
		goto error;
	}

	if ((mode == 'a' || mode == 'c') &&
	    ![archive respondsToSelector: @selector(addFiles:)]) {
		writingNotSupported(type);
		goto error;
	}

	return archive;

error:
	if (mode == 'c')
		[[OFFileManager defaultManager] removeItemAtPath: path];

	[OFApplication terminateWithStatus: 1];
	return nil;
}

- (bool)shouldExtractFile: (OFString *)fileName
	      outFileName: (OFString *)outFileName
{
	OFString *line;

	if (_overwrite == 1 ||
	    ![[OFFileManager defaultManager] fileExistsAtPath: outFileName])
		return true;

	if (_overwrite == -1) {
		if (_outputLevel >= 0) {
			[of_stdout writeString: @" "];
			[of_stdout writeLine:
			    OF_LOCALIZED(@"file_skipped", @"skipped")];
		}
		return false;
	}

	do {
		[of_stderr writeString: @"\r"];
		[of_stderr writeString: OF_LOCALIZED(@"ask_overwrite",
		    @"Overwrite %[file]? [ynAN?]",
		    @"file", fileName)];
		[of_stderr writeString: @" "];

		line = [of_stdin readLine];

		if ([line isEqual: @"?"])
			[of_stderr writeLine: OF_LOCALIZED(
			    @"ask_overwrite_help",
			    @" y: yes\n"
			    @" n: no\n"
			    @" A: always\n"
			    @" N: never")];
	} while (![line isEqual: @"y"] && ![line isEqual: @"n"] &&
	    ![line isEqual: @"N"] && ![line isEqual: @"A"]);

	if ([line isEqual: @"A"])
		_overwrite = 1;
	else if ([line isEqual: @"N"])
		_overwrite = -1;

	if ([line isEqual: @"n"] || [line isEqual: @"N"]) {
		if (_outputLevel >= 0)
			[of_stdout writeLine: OF_LOCALIZED(@"skipping_file",
			    @"Skipping %[file]...",
			    @"file", fileName)];
			return false;
	}

	if (_outputLevel >= 0)
		[of_stdout writeString: OF_LOCALIZED(@"extracting_file",
		    @"Extracting %[file]...",
		    @"file", fileName)];

	return true;
}

- (ssize_t)copyBlockFromStream: (OFStream *)input
		      toStream: (OFStream *)output
		      fileName: (OFString *)fileName
{
	char buffer[BUFFER_SIZE];
	size_t length;

	@try {
		length = [input readIntoBuffer: buffer
					length: BUFFER_SIZE];
	} @catch (OFReadFailedException *e) {
		OFString *error = [OFString
		    stringWithCString: strerror([e errNo])
			     encoding: [OFLocalization encoding]];
		[of_stdout writeString: @"\r"];
		[of_stderr writeLine: OF_LOCALIZED(@"failed_to_read_file",
		    @"Failed to read file %[file]: %[error]",
		    @"file", fileName,
		    @"error", error)];
		return -1;
	}

	@try {
		[output writeBuffer: buffer
			     length: length];
	} @catch (OFWriteFailedException *e) {
		OFString *error = [OFString
		    stringWithCString: strerror([e errNo])
			     encoding: [OFLocalization encoding]];
		[of_stdout writeString: @"\r"];
		[of_stderr writeLine: OF_LOCALIZED(@"failed_to_write_file",
		    @"Failed to write file %[file]: %[error]",
		    @"file", fileName,
		    @"error", error)];
		return -1;
	}

	return length;
}
@end
