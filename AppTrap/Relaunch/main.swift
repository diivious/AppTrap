//
//  main.swift
//  Relaunch
//
//  Created by Kumaran Vijayan on 2015-11-11.
//
//

import AppKit

class Observer: NSObject
{
    private let callback: () -> Void
    
    // Swift 4+ `private` is type-scoped; this must be callable from this file.
    fileprivate init(callback: @escaping () -> Void)
    {
        self.callback = callback
        super.init()
    }
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?)
    {
        callback()
    }
}

// main
autoreleasepool
{
    // get the application instance
    let args = CommandLine.arguments
    if args.count > 1,
       let parentPID = Int32(args[1]),
       let app = NSRunningApplication(processIdentifier: parentPID),
       let bundleURL = app.bundleURL
    {
        // terminate() and wait terminated.
        let listener = Observer { CFRunLoopStop(CFRunLoopGetCurrent()) }
        app.addObserver(
            listener,
            forKeyPath: #keyPath(NSRunningApplication.isTerminated),
            options: [],
            context: nil)
        app.terminate()
        CFRunLoopRun() // wait KVO notification
        app.removeObserver(listener, forKeyPath: #keyPath(NSRunningApplication.isTerminated), context: nil)
        
        // relaunch
        _ = try NSWorkspace.shared.launchApplication(
            at: bundleURL,
            options: [.default],
            configuration: [:])
    }
}
