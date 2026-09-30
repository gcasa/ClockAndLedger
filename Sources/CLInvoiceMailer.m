#import "CLInvoiceMailer.h"
#import "CLInvoiceView.h"
#import "CLLedger.h"

@implementation CLInvoiceMailer
- (void) dealloc
{
  [self cancel];
  [_task release];
  [_directory release];
  [_started release];
  [_failure release];
  [super dealloc];
}

- (BOOL) startInvoice: (NSDictionary *)invoice recipient: (NSString *)recipient
              sender: (NSString *)sender message: (NSString *)message
                send: (BOOL)send error: (NSString **)error
{
#ifdef __APPLE__
  NSString *base;
  NSString *pdfPath;
  NSString *bodyPath;
  NSString *script;
  NSString *number;
  NSString *subject;
  CLInvoiceView *view;
  NSError *failure = nil;
  NSFileManager *manager = [NSFileManager defaultManager];
  if (_task != nil || ![CLLedger validEmailAddress: recipient]
      || ((send || [sender length] > 0) && ![CLLedger validEmailAddress: sender]))
    { if (error != NULL) *error = @"Set valid client and business email addresses first."; return NO; }
  script = [[NSBundle mainBundle] pathForResource: @"InvoiceMail" ofType: @"applescript"];
  if (script == nil)
    { if (error != NULL) *error = @"The Apple Mail helper is missing. Rebuild the application."; return NO; }
  base = [[NSSearchPathForDirectoriesInDomains (NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex: 0]
    stringByAppendingPathComponent: @"ClockAndLedger/MailExports"];
  _directory = [[base stringByAppendingPathComponent: [[NSProcessInfo processInfo] globallyUniqueString]] copy];
  if (![manager createDirectoryAtPath: _directory withIntermediateDirectories: YES
      attributes: [NSDictionary dictionaryWithObject: [NSNumber numberWithInt: 0700] forKey: NSFilePosixPermissions] error: &failure])
    { if (error != NULL) *error = [failure localizedDescription]; return NO; }
  number = [[[CLLedger invoiceNumber: invoice] componentsSeparatedByCharactersInSet:
    [[NSCharacterSet characterSetWithCharactersInString: @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"] invertedSet]] componentsJoinedByString: @"_"];
  if ([number length] > 100) number = [number substringToIndex: 100];
  pdfPath = [_directory stringByAppendingPathComponent: [number stringByAppendingString: @".pdf"]];
  bodyPath = [_directory stringByAppendingPathComponent: @"message.txt"];
  view = [[[CLInvoiceView alloc] initWithInvoice: invoice] autorelease];
  if (![view writePDFToPath: pdfPath error: error]) return NO;
  if (![[NSString stringWithFormat: @"%@\n\n%@", message, [view emailText]]
      writeToFile: bodyPath atomically: YES encoding: NSUTF8StringEncoding error: &failure])
    { if (error != NULL) *error = [failure localizedDescription]; return NO; }
  subject = [NSString stringWithFormat: @"Invoice %@ — %@", [CLLedger invoiceNumber: invoice],
    [[invoice objectForKey: @"business"] objectForKey: @"name"]];
  _send = send;
  _task = [[NSTask alloc] init];
  [_task setLaunchPath: @"/usr/bin/osascript"];
  [_task setArguments: [NSArray arrayWithObjects: script, recipient, sender ?: @"", subject, bodyPath, pdfPath, send ? @"send" : @"draft", nil]];
  [manager createFileAtPath: [_directory stringByAppendingPathComponent: @"result.txt"] contents: [NSData data] attributes: nil];
  [manager createFileAtPath: [_directory stringByAppendingPathComponent: @"error.txt"] contents: [NSData data] attributes: nil];
  [_task setStandardOutput: [NSFileHandle fileHandleForWritingAtPath: [_directory stringByAppendingPathComponent: @"result.txt"]]];
  [_task setStandardError: [NSFileHandle fileHandleForWritingAtPath: [_directory stringByAppendingPathComponent: @"error.txt"]]];
  @try { [_task launch]; }
  @catch (NSException *exception)
    { if (error != NULL) *error = [exception reason]; return NO; }
  _started = [[NSDate date] retain];
  return YES;
#else
  if (error != NULL) *error = @"PDF email attachments and automatic delivery require Apple Mail on macOS.";
  return NO;
#endif
}

- (BOOL) isRunning
{
  if (_task == nil || _started == nil) return NO;
  if ([_task isRunning] && -[_started timeIntervalSinceNow] > 120 && !_timedOut)
    { _timedOut = YES; [_task terminate]; }
  return [_task isRunning];
}

- (BOOL) succeeded
{
  NSString *result;
  if (_task == nil || _started == nil || [self isRunning] || _timedOut || [_task terminationStatus] != 0) return NO;
  result = [NSString stringWithContentsOfFile: [_directory stringByAppendingPathComponent: @"result.txt"] encoding: NSUTF8StringEncoding error: NULL];
  return [[result stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqual: _send ? @"submitted" : @"draft"];
}

- (NSString *) failure
{
  if (_failure == nil)
    {
      NSString *detail = [NSString stringWithContentsOfFile: [_directory stringByAppendingPathComponent: @"error.txt"] encoding: NSUTF8StringEncoding error: NULL];
      _failure = [[NSString stringWithFormat: @"%@ Check Apple Mail's Drafts, Outbox and Sent before retrying. Allow Clock & Ledger to control Mail in System Settings > Privacy & Security > Automation.",
        _timedOut ? @"Mail timed out." : ([detail length] > 0 ? detail : @"Mail did not confirm the operation.")] copy];
    }
  return _failure;
}

- (void) cancel
{
  if (_started != nil && [_task isRunning]) [_task terminate];
}
@end
