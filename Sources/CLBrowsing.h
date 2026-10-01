#import <AppKit/AppKit.h>

/** Every action uses the same visible record snapshot as the rendered rows. */
@interface CLRecordTable : NSTableView
{
  NSArray *_visibleRecords;
@public
  NSSearchField *search;
  NSPopUpButton *statusFilter;
  NSPopUpButton *dateFilter;
  NSPopUpButton *clientFilter;
  NSTextField *resultCount;
}
- (NSArray *) visibleRecords;
@end

@interface NSObject (CLRecordTableSource)
- (NSArray *) browseRowsForTable: (CLRecordTable *)table;
@end
