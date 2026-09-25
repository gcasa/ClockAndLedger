#import <AppKit/AppKit.h>
#import "CLAppController.h"

/** Start Clock and Ledger with an explicitly managed autorelease pool. */
int
main (int argc, const char **argv)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  CLAppController *controller;
  [NSApplication sharedApplication];
  controller = [[CLAppController alloc] init];
  [NSApp setDelegate: (id)controller];
  [NSApp run];
  [NSApp setDelegate: nil];
  [controller release];
  [pool drain];
  return 0;
}
