//
//  main.m
//  RelaunchObjC
//
//  Created by Kumaran Vijayan on 2015-12-28.
//
//

#import <AppKit/AppKit.h>

@interface Observer: NSObject
@property (nonatomic, copy) void (^callback)(void);
- (instancetype)initWithCallback:(void (^)(void))callback;
@end
@implementation Observer
- (instancetype)initWithCallback:(void (^)(void))callback {
    self = [super init];
    if (self) {
        _callback = callback;
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context {
    self.callback();
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        int parentPid = atoi(argv[1]);
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:parentPid];
        NSURL *bundleURL = app.bundleURL;
        Observer *listener = [[Observer alloc] initWithCallback:^{
            CFRunLoopStop(CFRunLoopGetCurrent());
        }];
        [app addObserver:listener forKeyPath:@"isTerminated" options:0 context:nil];
        [app terminate];
        CFRunLoopRun();
        [app removeObserver:listener forKeyPath:@"isTerminated"];
        
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [[NSWorkspace sharedWorkspace] openApplicationAtURL:bundleURL
                                              configuration:configuration
                                          completionHandler:^(__unused NSRunningApplication * _Nullable runningApplication,
                                                              __unused NSError * _Nullable error) {
            dispatch_semaphore_signal(semaphore);
        }];

        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
    return 0;
}
