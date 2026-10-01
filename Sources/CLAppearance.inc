/* Shared native workspace chrome. Semantic surface colors follow the system appearance. */
static NSColor *CLAccent (void)
{
  return [NSColor colorWithCalibratedRed: 0.12 green: 0.48 blue: 0.45 alpha: 1];
}

@interface CLWorkspaceView : NSView
@end
@implementation CLWorkspaceView
- (void) drawRect: (NSRect)dirtyRect
{
  NSRect bounds = [self bounds];
  [[NSColor windowBackgroundColor] setFill];
  NSRectFill (bounds);
  [[NSColor colorWithCalibratedRed: 0.075 green: 0.18 blue: 0.20 alpha: 1] setFill];
  NSRectFill (NSMakeRect (0, 0, 196, bounds.size.height));
  [[NSColor controlBackgroundColor] setFill];
  [[NSBezierPath bezierPathWithRoundedRect: NSMakeRect (216, 20, bounds.size.width - 240, bounds.size.height - 170)
    xRadius: 14 yRadius: 14] fill];
  [[NSColor gridColor] setStroke];
  [[NSBezierPath bezierPathWithRoundedRect: NSMakeRect (216.5, 20.5, bounds.size.width - 241, bounds.size.height - 171)
    xRadius: 14 yRadius: 14] stroke];
}
@end

@interface CLNavigationButton : NSButton
@end
@implementation CLNavigationButton
- (void) drawRect: (NSRect)dirtyRect
{
  BOOL selected = [self state] == NSOnState;
  NSRect bounds = NSInsetRect ([self bounds], 1, 1);
  NSDictionary *attributes;
  if (selected || [[self cell] isHighlighted])
    {
      [(selected ? CLAccent () : [NSColor colorWithCalibratedWhite: 1 alpha: 0.09]) setFill];
      [[NSBezierPath bezierPathWithRoundedRect: bounds xRadius: 8 yRadius: 8] fill];
    }
  attributes = [NSDictionary dictionaryWithObjectsAndKeys:
    (selected ? [NSFont boldSystemFontOfSize: 13] : [NSFont systemFontOfSize: 13]), NSFontAttributeName,
    [NSColor colorWithCalibratedWhite: 1 alpha: selected ? 1 : 0.78], NSForegroundColorAttributeName, nil];
  [[self title] drawInRect: NSMakeRect (16, 12, bounds.size.width - 24, 20) withAttributes: attributes];
  if ([[self window] firstResponder] == self)
    {
      [NSGraphicsContext saveGraphicsState];
      NSSetFocusRingStyle (NSFocusRingOnly);
      [[NSBezierPath bezierPathWithRoundedRect: bounds xRadius: 8 yRadius: 8] fill];
      [NSGraphicsContext restoreGraphicsState];
    }
}
@end

/* Keep native button interaction and accessibility, with a consistent primary treatment. */
@interface CLPrimaryButton : NSButton
@end
@implementation CLPrimaryButton
- (void) drawRect: (NSRect)dirtyRect
{
  NSRect bounds = NSInsetRect ([self bounds], 3, 3);
  NSDictionary *attributes;
  NSSize titleSize;
  NSColor *fill = [[self cell] isHighlighted] ? [CLAccent () shadowWithLevel: 0.2] : CLAccent ();
  if (![self isEnabled]) fill = [NSColor disabledControlTextColor];
  [fill setFill];
  [[NSBezierPath bezierPathWithRoundedRect: bounds xRadius: 6 yRadius: 6] fill];
  attributes = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont boldSystemFontOfSize: 12], NSFontAttributeName,
    [NSColor whiteColor], NSForegroundColorAttributeName, nil];
  titleSize = [[self title] sizeWithAttributes: attributes];
  [[self title] drawAtPoint: NSMakePoint (NSMidX (bounds) - titleSize.width / 2,
    NSMidY (bounds) - titleSize.height / 2) withAttributes: attributes];
  if ([[self window] firstResponder] == self)
    {
      [NSGraphicsContext saveGraphicsState];
      NSSetFocusRingStyle (NSFocusRingOnly);
      [[NSBezierPath bezierPathWithRoundedRect: bounds xRadius: 6 yRadius: 6] fill];
      [NSGraphicsContext restoreGraphicsState];
    }
}
@end

@interface CLMetricCard : NSView
@end
@implementation CLMetricCard
- (void) drawRect: (NSRect)dirtyRect
{
  [[NSColor windowBackgroundColor] setFill];
  [[NSBezierPath bezierPathWithRoundedRect: NSInsetRect ([self bounds], 1, 1) xRadius: 10 yRadius: 10] fill];
  [CLAccent () setFill];
  NSRectFill (NSMakeRect (14, [self bounds].size.height - 17, 24, 3));
}
@end
