@implementation CLRecordTable
- (void) dealloc { [_visibleRecords release]; [super dealloc]; }
- (NSArray *) visibleRecords { return _visibleRecords ?: [NSArray array]; }
- (void) reloadData
{
  id source = [self dataSource];
  if ([source respondsToSelector: @selector(browseRowsForTable:)])
    {
      NSInteger selected = [self selectedRow];
      NSDictionary *previous = selected >= 0 && (NSUInteger)selected < [_visibleRecords count] ? [_visibleRecords objectAtIndex: selected] : nil;
      NSString *identifier = [[previous objectForKey: @"id"] copy];
      NSString *invoiceID = [[previous objectForKey: @"invoiceID"] copy];
      NSArray *rows = [[source browseRowsForTable: self] copy];
      [_visibleRecords release]; _visibleRecords = rows;
      [self deselectAll: nil];
      [super reloadData];
      if (identifier)
        {
          NSUInteger i;
          for (i = 0; i < [rows count]; i++)
            if ([[[rows objectAtIndex: i] objectForKey: @"id"] isEqual: identifier] &&
                (!invoiceID || [[[rows objectAtIndex: i] objectForKey: @"invoiceID"] isEqual: invoiceID]))
              { [self selectRowIndexes: [NSIndexSet indexSetWithIndex: i] byExtendingSelection: NO]; break; }
        }
      [identifier release]; [invoiceID release];
      [resultCount setStringValue: [NSString stringWithFormat: @"%lu shown", (unsigned long)[rows count]]];
      [self setNeedsDisplay: YES];
    }
  else [super reloadData];
}
- (void) drawRect: (NSRect)rect
{
  [super drawRect: rect];
  if ([[self visibleRecords] count] == 0)
    {
      NSString *message = search ? @"No records to show. Try clearing your filters." : @"No recorded activity for this report and currency.";
      NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 13], NSFontAttributeName,
        [NSColor disabledControlTextColor], NSForegroundColorAttributeName, nil];
      NSRect visible = [self visibleRect];
      NSSize size = [message sizeWithAttributes: attributes];
      [message drawAtPoint: NSMakePoint (NSMidX (visible) - size.width / 2, NSMinY (visible) + 30) withAttributes: attributes];
    }
}
@end

static NSInteger CLCompareBrowseRows (id left, id right, void *context)
{
  id a = [left objectForKey: @"sort"], b = [right objectForKey: @"sort"];
  NSComparisonResult order;
  BOOL ascending = *(BOOL *)context;
  if ([a isKindOfClass: [NSNumber class]] && [b isKindOfClass: [NSNumber class]]) order = [a compare: b];
  else order = [[a description] localizedCaseInsensitiveCompare: [b description]];
  if (order == NSOrderedSame) return [[left objectForKey: @"index"] compare: [right objectForKey: @"index"]];
  return ascending ? order : -order;
}
