/*
-----------------------------------------------
  APPTRAP LICENSE

  "Do what you want to do,
  and go where you're going to
  Think for yourself,
  'cause I won't be there with you"

  You are completely free to do anything with
  this source code, but if you try to make
  money on it you will be beaten up with a
  large stick. I take no responsibility for
  anything, and this license text must
  always be included.

  Markus Amalthea Magnuson <markus.magnuson@gmail.com>
-----------------------------------------------
*/

#import "ATPreferencePane.h"
#import "ATNotifications.h"
#import "ATVariables.h"

#import <unistd.h>

static NSString *const AppTrapBackgroundBundleIdentifier = @"se.diivious.AppTrap";
static NSString *const AppTrapBackgroundBundleIdentifierIntel = @"com.KumaranVijayan.AppTrap";
static NSString *const AppTrapBackgroundBundleIdentifierOriginal = @"se.konstochvanligasaker.AppTrap";
static NSString *const AppTrapLaunchAgentLabel = @"se.diivious.AppTrap";
static NSString *const AppTrapLaunchAgentFileName = @"se.diivious.AppTrap.plist";
static NSString *const AppTrapLaunchAgentFileNameIntel = @"com.KumaranVijayan.AppTrap.plist";
static NSString *const AppTrapLaunchAgentFileNameOriginal = @"se.konstochvanligasaker.AppTrap.plist";

@interface ATPreferencePane ()
- (void)refreshStartOnLoginButton;
- (BOOL)isStartOnLoginEnabled;
- (void)migrateLegacyLaunchAgentIfNeeded;
- (BOOL)writeLaunchAgentPlist;
- (void)removeLaunchAgentPlist;
- (void)bootstrapLaunchAgentIfPossible;
- (void)bootoutLaunchAgentIfPossible;
- (BOOL)runLaunchCtlWithArguments:(NSArray<NSString *> *)arguments;
- (NSString *)launchAgentPlistPath;
- (NSString *)launchctlGuiDomain;
@end

@implementation ATPreferencePane

- (void)mainViewDidLoad
{
    appPath = [[self bundle] pathForResource:@"AppTrap" ofType:@"app"];
    NSLog(@"appPath: %@", appPath);

    [automaticallyCheckForUpdate setState:NSControlStateValueOff];
    [automaticallyCheckForUpdate setEnabled:NO];

    [self migrateLegacyLaunchAgentIfNeeded];
    [self refreshStartOnLoginButton];

    [aboutView readRTFDFromFile:[[self bundle] pathForResource:@"Read Me" ofType:@"rtf"]];
    NSRange versionSymbolRange = [[aboutView string] rangeOfString:@"{APPTRAP_VERSION}"];
    if (versionSymbolRange.location != NSNotFound) {
        [[aboutView textStorage] replaceCharactersInRange:versionSymbolRange
                                                withString:[[self bundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    }

    NSDistributedNotificationCenter *nc = [NSDistributedNotificationCenter defaultCenter];

    [nc addObserver:self
           selector:@selector(updateStatus)
               name:ATApplicationFinishedLaunchingNotification
             object:nil
 suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];

    [nc addObserver:self
           selector:@selector(updateStatus)
               name:ATApplicationTerminatedNotification
             object:nil
 suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];

    [nc addObserver:self
           selector:@selector(checkBackgroundProcessVersion:)
               name:ATApplicationGetVersionData
             object:nil
 suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];

    [nc postNotificationName:ATApplicationSendVersionData
                      object:nil
                    userInfo:nil
          deliverImmediately:YES];
}

- (void)didSelect
{
    [self refreshStartOnLoginButton];
    [self updateStatus];
    [self checkBackgroundProcessVersion];
}

- (void)checkBackgroundProcessVersion:(NSNotification*)notification
{
    NSString *backgroundProcessVersion = notification.userInfo[ATBackgroundProcessVersion];
    NSString *prefpaneVersion = [[self bundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

    if (!backgroundProcessVersion || !prefpaneVersion) {
        return;
    }

    if (backgroundProcessVersion.integerValue == prefpaneVersion.integerValue) {
        return;
    }

    NSAlert *alert = [NSAlert new];
    alert.messageText = @"AppTrap";
    alert.informativeText = NSLocalizedStringFromTableInBundle(@"The background process is an older version. Would you like to restart it with the newer version?", nil, [self bundle], @"");
    [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Restart AppTrap", nil, [self bundle], @"")];
    [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Don't restart AppTrap", nil, [self bundle], @"")];

    [alert beginSheetModalForWindow:[startStopButton window]
                  completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [startStopButton setEnabled:NO];
            [restartingAppTrapIndicator startAnimation:nil];
            [restartingAppTrapTextField setHidden:NO];
            [self terminateAppTrap];
            [self performSelector:@selector(restartWithNewVersion) withObject:nil afterDelay:5];
        }
    }];
}

- (void)checkBackgroundProcessVersion
{
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:ATApplicationSendVersionData
                                                                   object:nil
                                                                 userInfo:nil
                                                       deliverImmediately:YES];
}

- (void)restartWithNewVersion
{
    [self launchAppTrap];
    [restartingAppTrapIndicator stopAnimation:nil];
    [restartingAppTrapTextField setHidden:YES];
    [startStopButton setEnabled:YES];
}

- (void)updateStatus
{
    if ([self appTrapIsRunning]) {
        [statusText setStringValue:NSLocalizedStringFromTableInBundle(@"Active", nil, [self bundle], @"")];
        [statusText setTextColor:[NSColor labelColor]];
        [startStopButton setTitle:NSLocalizedStringFromTableInBundle(@"Stop AppTrap", nil, [self bundle], @"")];
    } else {
        [statusText setStringValue:NSLocalizedStringFromTableInBundle(@"Inactive", nil, [self bundle], @"")];
        [statusText setTextColor:[NSColor secondaryLabelColor]];
        [startStopButton setTitle:NSLocalizedStringFromTableInBundle(@"Start AppTrap", nil, [self bundle], @"")];
    }

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateStatus) object:nil];
    [self performSelector:@selector(updateStatus) withObject:nil afterDelay:5.0];
}

- (void)launchAppTrap
{
    NSLog(@"launching AppTrap");

    if (appPath.length == 0) {
        NSLog(@"Couldn't launch AppTrap: app path is missing");
        return;
    }

    NSURL *appURL = [NSURL fileURLWithPath:appPath];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO;
    configuration.addsToRecentItems = NO;

    [[NSWorkspace sharedWorkspace] openApplicationAtURL:appURL
                                          configuration:configuration
                                      completionHandler:^(NSRunningApplication * _Nullable app, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Couldn't launch AppTrap: %@", error);
        }
    }];
}

- (void)terminateAppTrap
{
    NSLog(@"terminating AppTrap");
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:ATApplicationShouldTerminateNotification
                                                                   object:nil
                                                                 userInfo:nil
                                                       deliverImmediately:YES];
}

- (BOOL)appTrapIsRunning
{
    NSArray<NSString *> *bundleIdentifiers = @[AppTrapBackgroundBundleIdentifier, AppTrapBackgroundBundleIdentifierIntel, AppTrapBackgroundBundleIdentifierOriginal];
    for (NSString *bundleIdentifier in bundleIdentifiers) {
        if ([NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier].count > 0) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Update check

- (IBAction)automaticallyCheckForUpdate:(id)sender
{
    if ([sender respondsToSelector:@selector(setState:)]) {
        [sender setState:NSControlStateValueOff];
    }
}

- (IBAction)checkForUpdate:(id)sender
{
    NSBeep();
}

#pragma mark - Login item via LaunchAgent

- (void)migrateLegacyLaunchAgentIfNeeded
{
    NSString *currentPath = [self launchAgentPlistPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:currentPath]) {
        return;
    }

    NSArray<NSURL *> *urls = [fileManager URLsForDirectory:NSLibraryDirectory
                                                 inDomains:NSUserDomainMask];
    NSURL *launchAgentsURL = [urls.firstObject URLByAppendingPathComponent:@"LaunchAgents"
                                                               isDirectory:YES];

    NSArray<NSString *> *legacyFileNames = @[
        AppTrapLaunchAgentFileNameIntel,
        AppTrapLaunchAgentFileNameOriginal
    ];

    for (NSString *fileName in legacyFileNames) {
        NSString *legacyPath = [launchAgentsURL URLByAppendingPathComponent:fileName].path;
        if (![fileManager fileExistsAtPath:legacyPath]) {
            continue;
        }

        NSDictionary *legacyPlist = [NSDictionary dictionaryWithContentsOfFile:legacyPath];
        NSArray *programArguments = legacyPlist[@"ProgramArguments"];
        if (programArguments.count == 0) {
            continue;
        }

        [self runLaunchCtlWithArguments:@[@"bootout", [self launchctlGuiDomain], legacyPath]];

        NSError *removeError = nil;
        if (![fileManager removeItemAtPath:legacyPath error:&removeError]) {
            NSLog(@"Couldn't remove legacy AppTrap LaunchAgent %@: %@", legacyPath, removeError);
            return;
        }

        if ([self writeLaunchAgentPlist]) {
            [self bootstrapLaunchAgentIfPossible];
        }
        return;
    }
}

- (NSString *)launchAgentPlistPath
{
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory
                                                                    inDomains:NSUserDomainMask];
    NSURL *libraryURL = urls.firstObject;
    return [[libraryURL URLByAppendingPathComponent:@"LaunchAgents" isDirectory:YES]
            URLByAppendingPathComponent:AppTrapLaunchAgentFileName].path;
}

- (NSString *)launchctlGuiDomain
{
    return [NSString stringWithFormat:@"gui/%u", getuid()];
}

- (void)refreshStartOnLoginButton
{
    [startOnLoginButton setState:[self isStartOnLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff];
}

- (BOOL)isStartOnLoginEnabled
{
    NSString *plistPath = [self launchAgentPlistPath];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSArray *programArguments = plist[@"ProgramArguments"];
    NSString *configuredPath = programArguments.firstObject;

    return [plist[@"Label"] isEqualToString:AppTrapLaunchAgentLabel]
        && [configuredPath isEqualToString:appPath];
}

- (BOOL)writeLaunchAgentPlist
{
    if (appPath.length == 0) {
        return NO;
    }

    NSString *plistPath = [self launchAgentPlistPath];
    NSString *directoryPath = plistPath.stringByDeletingLastPathComponent;
    NSError *error = nil;

    BOOL createdDirectory = [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                                                      withIntermediateDirectories:YES
                                                                       attributes:nil
                                                                            error:&error];
    if (!createdDirectory) {
        NSLog(@"Couldn't create LaunchAgents directory: %@", error);
        return NO;
    }

    NSDictionary *plist = @{
        @"Label": AppTrapLaunchAgentLabel,
        @"ProgramArguments": @[appPath],
        @"RunAtLoad": @YES,
        @"KeepAlive": @NO
    };

    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (!data) {
        NSLog(@"Couldn't serialize LaunchAgent plist: %@", error);
        return NO;
    }

    BOOL wrotePlist = [data writeToFile:plistPath options:NSDataWritingAtomic error:&error];
    if (!wrotePlist) {
        NSLog(@"Couldn't write LaunchAgent plist: %@", error);
        return NO;
    }

    return YES;
}

- (void)removeLaunchAgentPlist
{
    NSError *error = nil;
    NSString *plistPath = [self launchAgentPlistPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:plistPath error:&error];
        if (!removed) {
            NSLog(@"Couldn't remove LaunchAgent plist: %@", error);
        }
    }
}

- (void)bootstrapLaunchAgentIfPossible
{
    [self bootoutLaunchAgentIfPossible];
    [self runLaunchCtlWithArguments:@[@"bootstrap", [self launchctlGuiDomain], [self launchAgentPlistPath]]];
}

- (void)bootoutLaunchAgentIfPossible
{
    [self runLaunchCtlWithArguments:@[@"bootout", [self launchctlGuiDomain], [self launchAgentPlistPath]]];
}

- (BOOL)runLaunchCtlWithArguments:(NSArray<NSString *> *)arguments
{
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = arguments;

    NSError *error = nil;
    BOOL launched = [task launchAndReturnError:&error];
    if (!launched) {
        NSLog(@"launchctl failed to start: %@", error);
        return NO;
    }

    [task waitUntilExit];
    return task.terminationStatus == 0;
}

#pragma mark - Interface actions

- (IBAction)startStopAppTrap:(id)sender
{
    if ([self appTrapIsRunning]) {
        [self terminateAppTrap];
    } else {
        [self launchAppTrap];
    }
}

- (IBAction)startOnLogin:(id)sender
{
    if ([sender state] == NSControlStateValueOn) {
        if ([self writeLaunchAgentPlist]) {
            [self bootstrapLaunchAgentIfPossible];
        }
    } else {
        [self bootoutLaunchAgentIfPossible];
        [self removeLaunchAgentPlist];
    }

    [self refreshStartOnLoginButton];
}

- (IBAction)visitWebsite:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"https://github.com/diivious/AppTrap"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

@end
