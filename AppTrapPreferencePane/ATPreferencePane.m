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
static NSString *const AppTrapGitHubLatestReleaseURL = @"https://api.github.com/repos/diivious/AppTrap/releases/latest";
static NSString *const AppTrapGitHubReleasesURL = @"https://github.com/diivious/AppTrap/releases";
static NSString *const AppTrapAutomaticallyChecksForUpdatesKey = @"ATAutomaticallyChecksForUpdates";
static NSString *const AppTrapLastUpdateCheckDateKey = @"ATLastUpdateCheckDate";
static NSTimeInterval const AppTrapAutomaticUpdateCheckInterval = 24.0 * 60.0 * 60.0;

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
- (NSUserDefaults *)appTrapDefaults;
- (void)performAutomaticUpdateCheck;
- (void)checkForUpdatesShowingCurrentVersion:(BOOL)showCurrentVersion;
- (void)checkForUpdatesShowingCurrentVersion:(BOOL)showCurrentVersion sender:(NSButton *)sender;
- (void)finishManualUpdateCheckForButton:(NSButton *)button;
- (NSModalResponse)runUpdateAlertWithMessage:(NSString *)message
                             informativeText:(NSString *)informativeText
                                    buttons:(NSArray<NSString *> *)buttons;
- (void)handleGitHubRelease:(NSDictionary *)release showCurrentVersion:(BOOL)showCurrentVersion;
- (NSString *)normalizedVersionString:(NSString *)version;
- (BOOL)version:(NSString *)candidateVersion isNewerThanVersion:(NSString *)currentVersion;
- (NSURL *)downloadURLForRelease:(NSDictionary *)release;
- (void)downloadUpdateFromURL:(NSURL *)url;
- (NSURL *)availableDownloadDestinationForSuggestedFilename:(NSString *)filename;
- (NSString *)launchctlGuiDomain;
@end

@implementation ATPreferencePane

- (void)mainViewDidLoad
{
    appPath = [[self bundle] pathForResource:@"AppTrap" ofType:@"app"];
    NSLog(@"appPath: %@", appPath);

    NSUserDefaults *defaults = [self appTrapDefaults];
    id savedAutomaticCheck = [defaults objectForKey:AppTrapAutomaticallyChecksForUpdatesKey];
    BOOL automaticallyChecks = savedAutomaticCheck ? [defaults boolForKey:AppTrapAutomaticallyChecksForUpdatesKey] : YES;
    [automaticallyCheckForUpdate setState:automaticallyChecks ? NSControlStateValueOn : NSControlStateValueOff];
    [automaticallyCheckForUpdate setEnabled:YES];

    if (automaticallyChecks) {
        NSDate *lastCheck = [defaults objectForKey:AppTrapLastUpdateCheckDateKey];
        NSTimeInterval elapsed = [lastCheck isKindOfClass:[NSDate class]] ? [[NSDate date] timeIntervalSinceDate:lastCheck] : AppTrapAutomaticUpdateCheckInterval;
        if (elapsed >= AppTrapAutomaticUpdateCheckInterval) {
            [self performSelector:@selector(performAutomaticUpdateCheck) withObject:nil afterDelay:1.0];
        }
    }

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

- (NSUserDefaults *)appTrapDefaults
{
    NSString *bundleIdentifier = self.bundle.bundleIdentifier;
    if (bundleIdentifier.length > 0) {
        return [[NSUserDefaults alloc] initWithSuiteName:bundleIdentifier];
    }
    return [NSUserDefaults standardUserDefaults];
}

- (void)performAutomaticUpdateCheck
{
    [self checkForUpdatesShowingCurrentVersion:NO sender:nil];
}

- (IBAction)automaticallyCheckForUpdate:(id)sender
{
    BOOL enabled = [sender state] == NSControlStateValueOn;
    NSUserDefaults *defaults = [self appTrapDefaults];
    [defaults setBool:enabled forKey:AppTrapAutomaticallyChecksForUpdatesKey];

    if (enabled) {
        [self checkForUpdatesShowingCurrentVersion:NO sender:nil];
    }
}

- (IBAction)checkForUpdate:(id)sender
{
    NSButton *button = [sender isKindOfClass:[NSButton class]] ? sender : nil;
    [self checkForUpdatesShowingCurrentVersion:YES sender:button];
}

- (void)checkForUpdatesShowingCurrentVersion:(BOOL)showCurrentVersion
{
    [self checkForUpdatesShowingCurrentVersion:showCurrentVersion sender:nil];
}

- (void)checkForUpdatesShowingCurrentVersion:(BOOL)showCurrentVersion sender:(NSButton *)sender
{
    if (sender) {
        sender.enabled = NO;
        sender.title = @"Checking...";
    }

    NSURL *url = [NSURL URLWithString:AppTrapGitHubLatestReleaseURL];
    if (!url) {
        [self finishManualUpdateCheckForButton:sender];

        if (showCurrentVersion) {
            [self runUpdateAlertWithMessage:@"Couldn't check for updates"
                           informativeText:@"The AppTrap update URL is invalid."
                                  buttons:@[@"OK"]];
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"AppTrap/2.x" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.timeoutInterval = 15.0;

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = 15.0;
    configuration.timeoutIntervalForResource = 20.0;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:request
                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishManualUpdateCheckForButton:sender];

            NSUserDefaults *defaults = [self appTrapDefaults];
            [defaults setObject:[NSDate date] forKey:AppTrapLastUpdateCheckDateKey];

            if (error) {
                if (showCurrentVersion) {
                    NSModalResponse responseCode =
                        [self runUpdateAlertWithMessage:@"Couldn't check for updates"
                                       informativeText:error.localizedDescription ?: @"The GitHub update check failed."
                                              buttons:@[@"Open Releases Page", @"OK"]];

                    if (responseCode == NSAlertFirstButtonReturn) {
                        [[NSWorkspace sharedWorkspace]
                            openURL:[NSURL URLWithString:AppTrapGitHubReleasesURL]];
                    }
                }
                return;
            }

            NSHTTPURLResponse *httpResponse =
                [response isKindOfClass:[NSHTTPURLResponse class]]
                    ? (NSHTTPURLResponse *)response
                    : nil;
            NSInteger statusCode = httpResponse ? httpResponse.statusCode : 0;

            if (statusCode == 404) {
                if (showCurrentVersion) {
                    NSModalResponse responseCode =
                        [self runUpdateAlertWithMessage:@"No AppTrap release is published yet"
                                       informativeText:@"GitHub does not currently have a published release for this repository. Once a release such as v2.0 is published, AppTrap can use it for update checks."
                                              buttons:@[@"Open Releases Page", @"OK"]];

                    if (responseCode == NSAlertFirstButtonReturn) {
                        [[NSWorkspace sharedWorkspace]
                            openURL:[NSURL URLWithString:AppTrapGitHubReleasesURL]];
                    }
                }
                return;
            }

            if (statusCode != 200) {
                if (showCurrentVersion) {
                    NSString *message =
                        [NSString stringWithFormat:@"GitHub returned HTTP %ld.",
                                                   (long)statusCode];

                    NSModalResponse responseCode =
                        [self runUpdateAlertWithMessage:@"Couldn't check for updates"
                                       informativeText:message
                                              buttons:@[@"Open Releases Page", @"OK"]];

                    if (responseCode == NSAlertFirstButtonReturn) {
                        [[NSWorkspace sharedWorkspace]
                            openURL:[NSURL URLWithString:AppTrapGitHubReleasesURL]];
                    }
                }
                return;
            }

            NSError *jsonError = nil;
            id json = [NSJSONSerialization JSONObjectWithData:data
                                                      options:0
                                                        error:&jsonError];

            if (![json isKindOfClass:[NSDictionary class]]) {
                if (showCurrentVersion) {
                    [self runUpdateAlertWithMessage:@"Couldn't check for updates"
                                   informativeText:jsonError.localizedDescription ?: @"GitHub returned an unexpected response."
                                          buttons:@[@"OK"]];
                }
                return;
            }

            [self handleGitHubRelease:(NSDictionary *)json
                    showCurrentVersion:showCurrentVersion];
        });

        [session finishTasksAndInvalidate];
    }];

    [task resume];
}

- (void)finishManualUpdateCheckForButton:(NSButton *)button
{
    if (!button) {
        return;
    }

    button.title = @"Check for Update";
    button.enabled = YES;
}

- (NSModalResponse)runUpdateAlertWithMessage:(NSString *)message
                             informativeText:(NSString *)informativeText
                                    buttons:(NSArray<NSString *> *)buttons
{
    NSAlert *alert = [NSAlert new];
    alert.messageText = message ?: @"AppTrap";
    alert.informativeText = informativeText ?: @"";

    for (NSString *buttonTitle in buttons) {
        [alert addButtonWithTitle:buttonTitle];
    }

    return [alert runModal];
}

- (void)handleGitHubRelease:(NSDictionary *)release showCurrentVersion:(BOOL)showCurrentVersion
{
    NSString *latestVersion = [self normalizedVersionString:release[@"tag_name"]];
    NSString *currentVersion =
        [self normalizedVersionString:[self.bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];

    if (latestVersion.length == 0 || currentVersion.length == 0) {
        if (showCurrentVersion) {
            [self runUpdateAlertWithMessage:@"Couldn't check for updates"
                           informativeText:@"The release version returned by GitHub could not be read."
                                  buttons:@[@"OK"]];
        }
        return;
    }

    if (![self version:latestVersion isNewerThanVersion:currentVersion]) {
        if (showCurrentVersion) {
            [self runUpdateAlertWithMessage:@"AppTrap is up to date"
                           informativeText:[NSString stringWithFormat:@"AppTrap %@ is the latest version.", currentVersion]
                                  buttons:@[@"OK"]];
        }
        return;
    }

    NSURL *downloadURL = [self downloadURLForRelease:release];
    NSString *releasePageString =
        [release[@"html_url"] isKindOfClass:[NSString class]]
            ? release[@"html_url"]
            : AppTrapGitHubReleasesURL;
    NSURL *releasePageURL = [NSURL URLWithString:releasePageString];

    NSArray<NSString *> *buttons =
        downloadURL
            ? @[@"Download Update", @"View Release", @"Not Now"]
            : @[@"View Release", @"Not Now"];

    NSModalResponse responseCode =
        [self runUpdateAlertWithMessage:[NSString stringWithFormat:@"AppTrap %@ is available", latestVersion]
                       informativeText:[NSString stringWithFormat:@"You are running AppTrap %@.", currentVersion]
                              buttons:buttons];

    if (downloadURL) {
        if (responseCode == NSAlertFirstButtonReturn) {
            [self downloadUpdateFromURL:downloadURL];
        } else if (responseCode == NSAlertSecondButtonReturn && releasePageURL) {
            [[NSWorkspace sharedWorkspace] openURL:releasePageURL];
        }
    } else if (responseCode == NSAlertFirstButtonReturn && releasePageURL) {
        [[NSWorkspace sharedWorkspace] openURL:releasePageURL];
    }
}

- (NSString *)normalizedVersionString:(NSString *)version
{
    if (![version isKindOfClass:[NSString class]]) {
        return @"";
    }

    NSString *normalized = [version stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([normalized hasPrefix:@"v"] || [normalized hasPrefix:@"V"]) {
        normalized = [normalized substringFromIndex:1];
    }
    return normalized;
}

- (BOOL)version:(NSString *)candidateVersion isNewerThanVersion:(NSString *)currentVersion
{
    return [candidateVersion compare:currentVersion options:NSNumericSearch] == NSOrderedDescending;
}

- (NSURL *)downloadURLForRelease:(NSDictionary *)release
{
    NSArray *assets = [release[@"assets"] isKindOfClass:[NSArray class]] ? release[@"assets"] : @[];
    NSString *releaseVersion = [self normalizedVersionString:release[@"tag_name"]];
    NSString *expectedDMGName =
        releaseVersion.length > 0
            ? [NSString stringWithFormat:@"AppTrap-%@.dmg", releaseVersion]
            : nil;

    NSDictionary *firstDMGAsset = nil;
    NSDictionary *zipAsset = nil;

    for (id object in assets) {
        if (![object isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSDictionary *asset = (NSDictionary *)object;
        NSString *name =
            [asset[@"name"] isKindOfClass:[NSString class]]
                ? asset[@"name"]
                : @"";
        NSString *download =
            [asset[@"browser_download_url"] isKindOfClass:[NSString class]]
                ? asset[@"browser_download_url"]
                : nil;

        if (download.length == 0) {
            continue;
        }

        if (expectedDMGName &&
            [name caseInsensitiveCompare:expectedDMGName] == NSOrderedSame) {
            return [NSURL URLWithString:download];
        }

        if ([[name.pathExtension lowercaseString] isEqualToString:@"dmg"] &&
            !firstDMGAsset) {
            firstDMGAsset = asset;
        }

        if ([[name.pathExtension lowercaseString] isEqualToString:@"zip"] &&
            !zipAsset) {
            zipAsset = asset;
        }
    }

    NSString *dmgDownload =
        [firstDMGAsset[@"browser_download_url"] isKindOfClass:[NSString class]]
            ? firstDMGAsset[@"browser_download_url"]
            : nil;

    if (dmgDownload.length > 0) {
        return [NSURL URLWithString:dmgDownload];
    }

    NSString *zipDownload =
        [zipAsset[@"browser_download_url"] isKindOfClass:[NSString class]]
            ? zipAsset[@"browser_download_url"]
            : nil;

    return zipDownload.length > 0 ? [NSURL URLWithString:zipDownload] : nil;
}

- (void)downloadUpdateFromURL:(NSURL *)url
{
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
        downloadTaskWithURL:url
          completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self runUpdateAlertWithMessage:@"Update download failed"
                                   informativeText:error.localizedDescription ?: @"AppTrap could not download the update."
                                          buttons:@[@"OK"]];
            });
            return;
        }

        NSString *filename = response.suggestedFilename;
        if (filename.length == 0) {
            filename = url.lastPathComponent.length > 0 ? url.lastPathComponent : @"AppTrap-update.dmg";
        }

        NSURL *destination = [self availableDownloadDestinationForSuggestedFilename:filename];
        NSError *moveError = nil;
        if (!destination || ![[NSFileManager defaultManager] moveItemAtURL:location toURL:destination error:&moveError]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // System Settings may not always be allowed to write into the user's Downloads
                // folder. Fall back to the browser download URL if that happens.
                [[NSWorkspace sharedWorkspace] openURL:url];

                [self runUpdateAlertWithMessage:@"Opening update in your browser"
                                   informativeText:moveError.localizedDescription ?: @"AppTrap could not save the update directly, so the download was opened in your browser instead."
                                          buttons:@[@"OK"]];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSWorkspace sharedWorkspace] openURL:destination];
        });
    }];
    [task resume];
}

- (NSURL *)availableDownloadDestinationForSuggestedFilename:(NSString *)filename
{
    NSURL *downloadsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory
                                                                  inDomains:NSUserDomainMask] firstObject];
    if (!downloadsURL) {
        return nil;
    }

    NSURL *candidate = [downloadsURL URLByAppendingPathComponent:filename];
    if (![[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
        return candidate;
    }

    NSString *baseName = filename.stringByDeletingPathExtension;
    NSString *extension = filename.pathExtension;
    for (NSInteger index = 2; index < 1000; index++) {
        NSString *numberedName = extension.length > 0
            ? [NSString stringWithFormat:@"%@-%ld.%@", baseName, (long)index, extension]
            : [NSString stringWithFormat:@"%@-%ld", baseName, (long)index];
        candidate = [downloadsURL URLByAppendingPathComponent:numberedName];
        if (![[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
            return candidate;
        }
    }

    return nil;
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
