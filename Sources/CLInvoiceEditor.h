#import <AppKit/AppKit.h>
@class CLLedger;

/** Edits a detached invoice draft. Cancel never mutates the ledger. */
@interface CLInvoiceEditor : NSObject
{
  CLLedger *_ledger;
  NSString *_identifier;
  NSMutableDictionary *_values;
  NSMutableDictionary *_fields;
  NSMutableArray *_lines;
  NSPanel *_panel;
  NSTableView *_table;
  NSImageView *_logo;
  BOOL _saved;
  NSPanel *_linePanel;
  NSMutableDictionary *_lineFields;
  BOOL _lineAccepted;
}
- (id) initWithLedger: (CLLedger *)ledger invoice: (NSDictionary *)invoice;
- (BOOL) run;
- (void) controlTextDidChange: (NSNotification *)notification;
- (void) save: (id)sender;
- (void) cancel: (id)sender;
- (void) addLine: (id)sender;
- (void) editLine: (id)sender;
- (void) removeLine: (id)sender;
- (void) acceptLine: (id)sender;
- (void) cancelLine: (id)sender;
- (void) chooseLogo: (id)sender;
- (void) removeLogo: (id)sender;
@end
