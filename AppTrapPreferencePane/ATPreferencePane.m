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
//#import "UKLoginItemRegistry.h"

static NSString *AppTrapBackgroundBundleIdentifier = @"com.KumaranVijayan.AppTrap";
static NSString *AppTrapBackgroundBundleIdentifierOld = @"se.konstochvanligasaker.AppTrap";

@interface ATPreferencePane ()
- (void)updateStartOnLoginButton;
@end

@implementation ATPreferencePane

- (void)mainViewDidLoad
{
	[[ATSUUpdater sharedUpdater] resetUpdateCycle];
	[[ATSUUpdater sharedUpdater] setDelegate:self];
		
    // Setup the application path
    appPath = [[self bundle] pathForResource:@"AppTrap" ofType:@"app"];
	NSLog(@"appPath: %@", appPath);
	
	[automaticallyCheckForUpdate setState:[[ATSUUpdater sharedUpdater] automaticallyChecksForUpdates] ? NSControlStateValueOn : NSControlStateValueOff];

    // Restart AppTrap in case the user just updated to a new version
    // TODO: Check AppTrap's version against the prefpane version and only restart if they differ
    // TODO: Leave this off for now, something goes haywire on startup
    /*if ([self appTrapIsRunning])
        [self launchAppTrap];*/
	[self updateStartOnLoginButton];
    
    // Display read me file
    [aboutView readRTFDFromFile:[[self bundle] pathForResource:@"Read Me" ofType:@"rtf"]];
    // Replace the {APPTRAP_VERSION} symbol with the version number
    NSRange versionSymbolRange = [[aboutView string] rangeOfString:@"{APPTRAP_VERSION}"];
    if (versionSymbolRange.location != NSNotFound){
        [[aboutView textStorage] replaceCharactersInRange:versionSymbolRange withString:[[self bundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
	}

    // Register for notifications from AppTrap
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

- (void)checkBackgroundProcessVersion:(NSNotification*)notification {
	NSLog(@"checkBackgroundProcessVersion");
	NSLog(@"notification: %@", [notification description]);
	NSLog(@"notification userInfo class: %@", [[notification userInfo] className]);
	NSLog(@"notification userInfo: %@", [[notification userInfo] description]);
	
	NSString *backgroundProcessVersion = [notification userInfo][ATBackgroundProcessVersion];
	int backgroundProcessVersionInt = [backgroundProcessVersion intValue];
	NSString *prefpaneVersion = [[self bundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	int prefpaneVersionInt = [prefpaneVersion intValue];
	
	if (prefpaneVersionInt != backgroundProcessVersionInt) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"AppTrap"];
        [alert setInformativeText:NSLocalizedStringFromTableInBundle(@"The background process is an older version. Would you like to restart it with the newer version?", nil, [self bundle], @"")];
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Restart AppTrap", nil, [self bundle], @"")];
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Don't restart AppTrap", nil, [self bundle], @"")];
        [alert beginSheetModalForWindow:[startStopButton window] completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertFirstButtonReturn) {
                [startStopButton setEnabled:NO];
                [restartingAppTrapIndicator startAnimation:nil];
                [restartingAppTrapTextField setHidden:NO];
                [self terminateAppTrap];
                [self performSelector:@selector(restartWithNewVersion) withObject:nil afterDelay:5];
            }
        }];
	}
}

- (void)checkBackgroundProcessVersion {
	NSDistributedNotificationCenter *nc = [NSDistributedNotificationCenter defaultCenter];
	
	[nc postNotificationName:ATApplicationSendVersionData
					  object:nil
					userInfo:nil
		  deliverImmediately:YES];
}

- (void)restartWithNewVersion {
	[self launchAppTrap];
	[restartingAppTrapIndicator stopAnimation:nil];
	[restartingAppTrapTextField setHidden:YES];
	[startStopButton setEnabled:YES];
}

- (void)didSelect
{
	[self updateStartOnLoginButton];
	
    [self updateStatus];
	[self checkBackgroundProcessVersion];
}

- (void)updateStatus
{
    if ([self appTrapIsRunning]) {
        // Need to specify bundle because we're a prefpane
        [statusText setStringValue:NSLocalizedStringFromTableInBundle(@"Active", nil, [self bundle], @"")];
        [statusText setTextColor:[NSColor blackColor]];
        [startStopButton setTitle:NSLocalizedStringFromTableInBundle(@"Stop AppTrap", nil, [self bundle], @"")];
    }
    else {
        // Need to specify bundle because we're a prefpane
        [statusText setStringValue:NSLocalizedStringFromTableInBundle(@"Inactive", nil, [self bundle], @"")];
        [statusText setTextColor:[NSColor grayColor]];
        [startStopButton setTitle:NSLocalizedStringFromTableInBundle(@"Start AppTrap", nil, [self bundle], @"")];
    }
    
    // Extra check after five seconds in case the launch/termination was delayed
    [self performSelector:@selector(updateStatus)
			   withObject:nil
			   afterDelay:5.0];
}

- (void)launchAppTrap
{
    // Try to launch AppTrap
	NSLog(@"launching AppTrap");
	NSURL *appURL = [NSURL fileURLWithPath:appPath];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    [configuration setAddsToRecentItems:NO];
    [configuration setActivates:NO];
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:appURL
                                          configuration:configuration
                                      completionHandler:^(NSRunningApplication *application, NSError *error) {
        if (error) {
            NSLog(@"Couldn't launch AppTrap: %@", error);
        }
    }];
}

- (void)terminateAppTrap
{
	NSLog(@"terminating Apptrap");
    NSDistributedNotificationCenter *nc = [NSDistributedNotificationCenter defaultCenter];
    [nc postNotificationName:ATApplicationShouldTerminateNotification
                      object:nil
                    userInfo:nil
          deliverImmediately:YES];
}

- (BOOL)appTrapIsRunning
{
	id <NSFastEnumeration> applications = [NSRunningApplication runningApplicationsWithBundleIdentifier:AppTrapBackgroundBundleIdentifier];
	for (NSRunningApplication *application in applications)
	{
		NSString *bundleIdentifier = application.bundleIdentifier;
		if ([bundleIdentifier isEqualToString:AppTrapBackgroundBundleIdentifier])
		{
			return YES;
		}
	}
	return NO;
}

#pragma mark -
#pragma mark Update check

- (id)updater {
	return [ATSUUpdater sharedUpdater];
}

- (IBAction)automaticallyCheckForUpdate:(id)sender {
	[[ATSUUpdater sharedUpdater] setAutomaticallyChecksForUpdates:([sender state] == NSControlStateValueOn)];
}

- (IBAction)checkForUpdate:(id)sender {
	[[ATSUUpdater sharedUpdater] checkForUpdates:sender];
}

#pragma mark -
#pragma mark Login items

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (void)updateStartOnLoginButton
{
    CFURLRef appPathURL = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    BOOL isInLoginItems = NO;
    if (loginItems) {
        isInLoginItems = [self inLoginItems:loginItems forPath:appPathURL];
        CFRelease(loginItems);
    }
    [startOnLoginButton setState:isInLoginItems ? NSControlStateValueOn : NSControlStateValueOff];
}
- (BOOL)inLoginItems:(LSSharedFileListRef)theLoginItemsRefs forPath:(CFURLRef)thePath
{
	if (!theLoginItemsRefs || !thePath) {
		return NO;
	}

	UInt32 seedValue;
	NSArray *loginItemsArray = (NSArray *)CFBridgingRelease(LSSharedFileListCopySnapshot(theLoginItemsRefs, &seedValue));
	for (id item in loginItemsArray) {
		LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)item;
		CFURLRef itemURL = NULL;
		if (LSSharedFileListItemResolve(itemRef, 0, &itemURL, NULL) == noErr && itemURL) {
			NSString *itemPath = [(__bridge NSURL *)itemURL path];
			CFRelease(itemURL);
			if ([itemPath hasPrefix:appPath]) {
				return YES;
			}
		}
	}
	
	return NO;
}

- (void)addToLoginItems:(LSSharedFileListRef )theLoginItemsRefs forPath:(CFURLRef)thePath
{
	if (!theLoginItemsRefs || !thePath) {
		return;
	}
	LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(theLoginItemsRefs, kLSSharedFileListItemLast, NULL, NULL, thePath, NULL, NULL);		
	if (item) {
		CFRelease(item);
	}
}

- (void)removeFromLoginItems:(LSSharedFileListRef )theLoginItemsRefs forPath:(CFURLRef)thePath
{
	if (!theLoginItemsRefs || !thePath) {
		return;
	}

	UInt32 seedValue;
	NSArray *loginItemsArray = (NSArray *)CFBridgingRelease(LSSharedFileListCopySnapshot(theLoginItemsRefs, &seedValue));
	for (id item in loginItemsArray) {
		LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)item;
		CFURLRef itemURL = NULL;
		if (LSSharedFileListItemResolve(itemRef, 0, &itemURL, NULL) == noErr && itemURL) {
			NSString *itemPath = [(__bridge NSURL *)itemURL path];
			CFRelease(itemURL);
			if ([itemPath hasPrefix:appPath]) {
				LSSharedFileListItemRemove(theLoginItemsRefs, itemRef);
			}
		}
	}
	
}

#pragma mark -
#pragma mark Interface actions

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
	CFURLRef appPathURL = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (!loginItems) {
        return;
    }

    if ([sender state] == NSControlStateValueOn) {
        [self addToLoginItems:loginItems forPath:appPathURL];
	} else {
        [self removeFromLoginItems:loginItems forPath:appPathURL];
	}
	
    CFRelease(loginItems);
}

#pragma clang diagnostic pop

- (IBAction)visitWebsite:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"http://onnati.net/apptrap/"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

@end
