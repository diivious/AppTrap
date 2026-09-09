//
//  APTFSEventsWatcher.m
//  AppTrap
//
//  Created by Kumaran Vijayan on 2013-05-08.
//

#import "APTFSEventsWatcher.h"

static CFTimeInterval kEventStreamLatency = 3.0;

void eventStreamCallback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]);

@interface APTFSEventsWatcher ()
{
    BOOL _watching;
}

@property (nonatomic, assign) FSEventStreamRef eventStream;

@end

@implementation APTFSEventsWatcher

#pragma mark - Creation

- (id)initWithDirectoryPath:(NSString *)directoryPath
{
    self = [super init];
    if (self)
    {
        if (directoryPath.length == 0)
        {
            [NSException raise:NSInvalidArgumentException format:@"directoryPath must be a valid NSString."];
        }

        _watching = NO;

        FSEventStreamContext eventStreamContext = {0};
        eventStreamContext.info = (__bridge void *)self;

        FSEventStreamRef eventStream = FSEventStreamCreate(kCFAllocatorDefault,
                                                           &eventStreamCallback,
                                                           &eventStreamContext,
                                                           (__bridge CFArrayRef)@[directoryPath],
                                                           kFSEventStreamEventIdSinceNow,
                                                           kEventStreamLatency,
                                                           kFSEventStreamCreateFlagUseCFTypes);
        if (eventStream == NULL)
        {
            return nil;
        }

        self.eventStream = eventStream;
        FSEventStreamSetDispatchQueue(self.eventStream, dispatch_get_main_queue());
    }
    return self;
}

#pragma mark - Public APIs

- (BOOL)isWatching
{
    return _watching;
}

- (void)startWatching
{
    if (self.eventStream != NULL && !_watching)
    {
        _watching = FSEventStreamStart(self.eventStream);
    }
}

- (void)stopWatching
{
    if (self.eventStream != NULL && _watching)
    {
        FSEventStreamStop(self.eventStream);
        _watching = NO;
    }
}

#pragma mark - FSEventStream Callback

void eventStreamCallback(__unused ConstFSEventStreamRef streamRef,
                         void *clientCallBackInfo,
                         size_t numEvents,
                         void *eventPaths,
                         __unused const FSEventStreamEventFlags eventFlags[],
                         __unused const FSEventStreamEventId eventIds[])
{
    if (clientCallBackInfo == NULL || numEvents == 0 || eventPaths == NULL)
    {
        return;
    }

    APTFSEventsWatcher *watcher = (__bridge APTFSEventsWatcher *)clientCallBackInfo;
    NSArray<NSString *> *paths = (__bridge NSArray *)eventPaths;
    NSString *path = paths.firstObject;
    if (path.length > 0 && watcher.delegate != nil)
    {
        [watcher.delegate eventsWatcher:watcher observedChangesInDirectoryPath:path];
    }
}

#pragma mark - Memory Management

- (void)dealloc
{
    if (self.eventStream != NULL)
    {
        FSEventStreamStop(self.eventStream);
        FSEventStreamSetDispatchQueue(self.eventStream, NULL);
        FSEventStreamInvalidate(self.eventStream);
        FSEventStreamRelease(self.eventStream);
        self.eventStream = NULL;
    }
}

@end
