/*
   STPrivilegedTask - NSTask-like wrapper around AuthorizationExecuteWithPrivileges
   Copyright (C) 2008-2021 Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
   
   BSD License
   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are met:
       * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
       * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
       * Neither the name of the copyright holder nor that of any other
       contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
   
   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
   DISCLAIMED. IN NO EVENT SHALL  BE LIABLE FOR ANY
   DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
   (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
   ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "STPrivilegedTask.h"

#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>
#import <stdio.h>
#import <unistd.h>
#import <dlfcn.h>

// New error code denoting that AuthorizationExecuteWithPrivileges no longer exists
OSStatus const errAuthorizationFnNoLongerExists = -70001;

// Create fn pointer to AuthorizationExecuteWithPrivileges
// in case it doesn't exist in this version of macOS
static OSStatus (*_AuthExecuteWithPrivsFn)(AuthorizationRef authorization, const char *pathToTool, AuthorizationFlags options,
                                           char * const *arguments, FILE **communicationsPipe) = NULL;


@implementation STPrivilegedTask
{
    NSTimer *_checkStatusTimer;
}

+ (void)initialize {
    // On 10.7, AuthorizationExecuteWithPrivileges is deprecated. We want
    // to still use it since there's no good alternative (without requiring
    // code signing). We'll look up the function through dyld and fail if
    // it is no longer accessible. If Apple removes the function entirely
    // this will fail gracefully. If they keep the function and throw some
    // sort of exception, this won't fail gracefully, but that's a risk
    // we'll have to take for now.
    // Pattern by Andy Kim from Potion Factory LLC
#pragma GCC diagnostic ignored "-Wpedantic" // stop the pedantry!
#pragma clang diagnostic push
    _AuthExecuteWithPrivsFn = dlsym(RTLD_DEFAULT, "AuthorizationExecuteWithPrivileges");
#pragma clang diagnostic pop
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _launchPath = nil;
        _arguments = nil;
        _freeAuthorizationWhenDone = YES;
        _isRunning = NO;
        _outputFileHandle = nil;
        _terminationHandler = nil;
        _authorization = nil;
        _currentDirectoryPath = [[NSFileManager defaultManager] currentDirectoryPath];
    }
    return self;
}

- (instancetype)initWithLaunchPath:(NSString *)path {
    self = [self init];
    if (self) {
        self.launchPath = path;
    }
    return self;
}

- (instancetype)initWithLaunchPath:(NSString *)path
                         arguments:(NSArray *)args {
    self = [self initWithLaunchPath:path];
    if (self)  {
        self.arguments = args;
    }
    return self;
}

- (instancetype)initWithLaunchPath:(NSString *)path
                         arguments:(NSArray *)args
                  currentDirectory:(NSString *)cwd {
    self = [self initWithLaunchPath:path arguments:args];
    if (self) {
        self.currentDirectoryPath = cwd;
    }
    return self;
}

- (void)dealloc
{
    if (_freeAuthorizationWhenDone && _authorization != nil) {
        // free the auth ref
        AuthorizationFree(_authorization, kAuthorizationFlagDefaults);
    }
}

#pragma mark -

+ (STPrivilegedTask *)launchedPrivilegedTaskWithLaunchPath:(NSString *)path {
    STPrivilegedTask *task = [[STPrivilegedTask alloc] initWithLaunchPath:path];
    [task launch];
    [task waitUntilExit];
    return task;
}

+ (STPrivilegedTask *)launchedPrivilegedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)args {
    STPrivilegedTask *task = [[STPrivilegedTask alloc] initWithLaunchPath:path arguments:args];
    [task launch];
    [task waitUntilExit];
    return task;
}

+ (STPrivilegedTask *)launchedPrivilegedTaskWithLaunchPath:(NSString *)path
                                                 arguments:(NSArray *)args
                                          currentDirectory:(NSString *)cwd {
    STPrivilegedTask *task = [[STPrivilegedTask alloc] initWithLaunchPath:path arguments:args currentDirectory:cwd];
    [task launch];
    [task waitUntilExit];
    return task;
}

+ (STPrivilegedTask *)launchedPrivilegedTaskWithLaunchPath:(NSString *)path
                                                 arguments:(NSArray *)args
                                          currentDirectory:(NSString *)cwd
                                             authorization:(AuthorizationRef)authorization {
    STPrivilegedTask *task = [[STPrivilegedTask alloc] initWithLaunchPath:path arguments:args currentDirectory:cwd];
    [task launchWithAuthorization:authorization];
    [task waitUntilExit];
    return task;
}

# pragma mark -

// return 0 for success
- (OSStatus)launch {
    if (_isRunning) {
        NSLog(@"Task already running: %@", [self description]);
        return 0;
    }
    
    if ([STPrivilegedTask authorizationFunctionAvailable] == NO) {
        NSLog(@"AuthorizationExecuteWithPrivileges() function not available on this system");
        return errAuthorizationFnNoLongerExists;
    }
    
    OSStatus err = noErr;
    const char *toolPath = [self.launchPath fileSystemRepresentation];
    
    AuthorizationRef authorizationRef;
    AuthorizationItem myItems = { kAuthorizationRightExecute, strlen(toolPath), &toolPath, 0 };
    AuthorizationRights myRights = { 1, &myItems };
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
    
    // Use Apple's Authentication Manager API to create an Authorization Reference
    err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorizationRef);
    if (err != errAuthorizationSuccess) {
        return err;
    }
    
    // Pre-authorize the privileged operation
    err = AuthorizationCopyRights(authorizationRef, &myRights, kAuthorizationEmptyEnvironment, flags, NULL);
    if (err != errAuthorizationSuccess) {
        return err;
    }
    
    // OK, at this point we have received authorization for the task so we launch it.
    err = [self launchWithAuthorization:authorizationRef];
        
    return err;
}

- (OSStatus)launchWithAuthorization:(AuthorizationRef)authorization
{
    _authorization = authorization;
    
    if (_isRunning) {
        NSLog(@"Task already running: %@", [self description]);
        return 0;
    }
    
    if ([STPrivilegedTask authorizationFunctionAvailable] == NO) {
        NSLog(@"AuthorizationExecuteWithPrivileges() function not available on this system");
        return errAuthorizationFnNoLongerExists;
    }
    
    // Assuming the authorization is valid for the task.
    // Let's prepare to launch it.
    NSArray *arguments = self.arguments;
    NSUInteger numArgs = [arguments count];
    char *args[numArgs + 1];
    FILE *outputFile;
    
    const char *toolPath = [self.launchPath fileSystemRepresentation];
    
    // First, construct an array of C strings w. all the arguments from NSArray
    // This is the format required by AuthorizationExecuteWithPrivileges function
    for (int i = 0; i < numArgs; i++) {
        NSString *argString = arguments[i];
        const char *fsrep = [argString fileSystemRepresentation];
        NSUInteger stringLength = strlen(fsrep);
        args[i] = calloc((stringLength + 1), sizeof(char));
        snprintf(args[i], stringLength + 1, "%s", fsrep);
    }
    args[numArgs] = NULL;
    
    // Change to the specified current working directory
    // NB: This is process-wide and could interfere with the behaviour of concurrent tasks
    char *prevCwd = (char *)getcwd(nil, 0);
    chdir([self.currentDirectoryPath fileSystemRepresentation]);
    
    // Use Authorization Reference to execute script with privileges.
    // This is where the magic happens.
    OSStatus err = _AuthExecuteWithPrivsFn(authorization, toolPath, kAuthorizationFlagDefaults, args, &outputFile);
    
    // OK, now we're done executing, let's change back to old dir
    chdir(prevCwd);
    
    // Free the alloc'd argument strings
    for (int i = 0; i < numArgs; i++) {
        free(args[i]);
    }
    
    // We return err if execution failed
    if (err != errAuthorizationSuccess) {
        return err;
    } else {
        _isRunning = YES;
    }
    
    // Get file handle for the command output
    _outputFileHandle = [[NSFileHandle alloc] initWithFileDescriptor:fileno(outputFile) closeOnDealloc:YES];
    _processIdentifier = fcntl(fileno(outputFile), F_GETOWN, 0);
    
    // Start monitoring task
    _checkStatusTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(checkTaskStatus) userInfo:nil repeats:YES];
    
    return err;
}

- (void)terminate {
    // This doesn't work without a PID, and we can't get one. Stupid Security API.
//    int ret = kill(pid, SIGKILL);
//     
//    if (ret != 0) {
//        NSLog(@"Error %d", errno);
//    }
}

// Hang until task is done
- (void)waitUntilExit {
    if (!_isRunning) {
        NSLog(@"Task %@ is not running", [super description]);
        return;
    }
    
    [_checkStatusTimer invalidate];
    
    int status;
    pid_t pid = 0;
    while ((pid = waitpid(_processIdentifier, &status, WNOHANG)) == 0) {
        // Do nothing
    }
    _isRunning = NO;
    _terminationStatus = WEXITSTATUS(status);
}

// Check if task has terminated
- (void)checkTaskStatus {
    int status;
    pid_t pid = waitpid(_processIdentifier, &status, WNOHANG);
    if (pid != 0) {
        _isRunning = NO;
        _terminationStatus = WEXITSTATUS(status);
        [_checkStatusTimer invalidate];
        [[NSNotificationCenter defaultCenter] postNotificationName:STPrivilegedTaskDidTerminateNotification object:self];
        if (_terminationHandler) {
            _terminationHandler(self);
        }
    }
}

#pragma mark -

+ (BOOL)authorizationFunctionAvailable {
    if (!_AuthExecuteWithPrivsFn) {
        // This version of macOS has finally removed this function.
        return NO;
    }
    return YES;
}

#pragma mark -

// Nice description for debugging purposes
- (NSString *)description {
    NSString *commandDescription = [NSString stringWithString:self.launchPath];
    
    for (NSString *arg in self.arguments) {
        commandDescription = [commandDescription stringByAppendingFormat:@" '%@'", arg];
    }
    [commandDescription stringByAppendingFormat:@" (CWD:%@)", self.currentDirectoryPath];
    
    return [[super description] stringByAppendingFormat:@" %@", commandDescription];
}

@end
