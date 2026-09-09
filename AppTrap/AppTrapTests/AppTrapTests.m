//
//  AppTrapTests.m
//  AppTrapTests
//
//  Created by Kumaran Vijayan on 2013-08-17.
//
//

#import "AppTrapTests.h"

#import "APTApplicationController.h"

@interface APTApplicationController ()
@property (nonatomic, readonly) NSString *pathToTrash;
@property (nonatomic, readonly) NSArray *libraryPaths;
@end

@interface AppTrapTests ()
@property (nonatomic) APTApplicationController *controller;
@end


@implementation AppTrapTests

- (void)setUp
{
    [super setUp];

	APTApplicationController *controller = [APTApplicationController new];
	[self setController:controller];
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void)testPathToTrash
{
	NSString *pathToTrash = self.controller.pathToTrash;
	XCTAssertNotNil(pathToTrash, @"");
	NSString *trash = pathToTrash.lastPathComponent;
	XCTAssertEqualObjects(trash, @".Trash", @"");
}

- (void)testLibraryPaths
{
	NSArray *libraryPaths = self.controller.libraryPaths;
	XCTAssertNotNil(libraryPaths, @"");
	XCTAssertTrue(libraryPaths.count > 0, @"");
}

@end
