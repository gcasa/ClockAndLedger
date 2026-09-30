#import <AppKit/AppKit.h>

/** Asynchronous Apple Mail handoff. Never calls a shell or embeds client data
 * in script source. The caller journals automatic attempts before starting. */
@interface CLInvoiceMailer : NSObject
{
  NSTask *_task;
  NSString *_directory;
  NSDate *_started;
  NSString *_failure;
  BOOL _timedOut;
  BOOL _send;
}
- (BOOL) startInvoice: (NSDictionary *)invoice recipient: (NSString *)recipient
              sender: (NSString *)sender message: (NSString *)message
                send: (BOOL)send error: (NSString **)error;
- (BOOL) isRunning;
- (BOOL) succeeded;
- (NSString *) failure;
- (void) cancel;
@end
