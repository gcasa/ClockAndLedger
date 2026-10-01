/* macOS menu bar controls share the main window's durable ledger timer. */
#ifdef __APPLE__
- (void) setupStatusItem
{
  NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"Clock & Ledger"] autorelease];
  NSMenuItem *item;
  [menu setAutoenablesItems: NO];
  [menu setDelegate: (id)self];
  _statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength: NSVariableStatusItemLength] retain];
  [[_statusItem button] setFont: [NSFont monospacedDigitSystemFontOfSize: 12 weight: NSFontWeightRegular]];
  [[_statusItem button] setAccessibilityLabel: @"Clock & Ledger timer"];
  _statusSummary = [menu addItemWithTitle: @"No timer running" action: NULL keyEquivalent: @""];
  [_statusSummary setEnabled: NO];
  [menu addItem: [NSMenuItem separatorItem]];
  _statusStart = [menu addItemWithTitle: @"Start Timer" action: NULL keyEquivalent: @""];
  _statusStop = [menu addItemWithTitle: @"Stop Timer & Save Time" action: @selector(stopTimer:) keyEquivalent: @""];
  [_statusStop setTarget: self];
  [menu addItem: [NSMenuItem separatorItem]];
  item = [menu addItemWithTitle: @"Open Clock & Ledger" action: @selector(showMainWindow:) keyEquivalent: @""];
  [item setTarget: self];
  _statusDock = [menu addItemWithTitle: @"Hide Dock Icon" action: @selector(toggleDockVisibility:) keyEquivalent: @""];
  [_statusDock setTarget: self];
  item = [menu addItemWithTitle: @"Quit Clock & Ledger" action: @selector(terminate:) keyEquivalent: @""];
  [item setTarget: NSApp];
  [_statusItem setMenu: menu];
  /* Install the menu bar access point before hiding the Dock icon. */
  [NSApp setActivationPolicy: [[NSUserDefaults standardUserDefaults] boolForKey: @"HideDockIcon"]
    ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyRegular];
  /* Keep elapsed time updating while menus or modal editors are open. */
  _statusPulse = [[NSTimer timerWithTimeInterval: 1 target: self selector: @selector(updateStatusItem:) userInfo: nil repeats: YES] retain];
  [[NSRunLoop mainRunLoop] addTimer: _statusPulse forMode: NSRunLoopCommonModes];
  [self updateStatusItem: nil];
}

- (void) updateStatusItem: (id)sender
{
  NSDictionary *timer = [_ledger timer];
  BOOL running = timer != nil;
  NSString *summary = @"No timer running";
  NSString *title = @"◷";
  if (running)
    {
      long long seconds = MAX (0, (long long)[_ledger timerElapsed]);
      title = [NSString stringWithFormat: @"● %02lld:%02lld:%02lld", seconds / 3600, (seconds / 60) % 60, seconds % 60];
      summary = [NSString stringWithFormat: @"%@ — %@", [[_ledger clientWithID: [timer objectForKey: @"clientID"]] objectForKey: @"name"], [CLLedger workLabelForEntry: timer]];
    }
  [[_statusItem button] setTitle: title];
  [[_statusItem button] setToolTip: [NSString stringWithFormat: @"Clock & Ledger: %@", summary]];
  [_statusSummary setTitle: summary];
  [_statusDock setTitle: [NSApp activationPolicy] == NSApplicationActivationPolicyAccessory
    ? @"Show Dock Icon" : @"Hide Dock Icon"];
  [_statusStart setEnabled: !running && [[_ledger clients] count] > 0 && [NSApp modalWindow] == nil];
  [_statusStop setEnabled: running && [NSApp modalWindow] == nil];
}

- (void) menuNeedsUpdate: (NSMenu *)menu
{
  NSMenu *clients;
  NSUInteger i, j;
  if (menu != [_statusItem menu]) return;
  clients = [[[NSMenu alloc] initWithTitle: @"Start Timer"] autorelease];
  [clients setAutoenablesItems: NO];
  for (i = 0; i < [[_ledger clients] count]; i++)
    {
      NSDictionary *client = [[_ledger clients] objectAtIndex: i];
      NSString *clientID = [client objectForKey: @"id"];
      NSArray *tasks = [_ledger tasksForClient: clientID includeArchived: NO];
      NSMenuItem *clientItem = [clients addItemWithTitle: [client objectForKey: @"name"] action: NULL keyEquivalent: @""];
      NSMenu *taskMenu = [[[NSMenu alloc] initWithTitle: [client objectForKey: @"name"]] autorelease];
      [taskMenu setAutoenablesItems: NO];
      for (j = 0; j <= [tasks count]; j++)
        {
          NSDictionary *task = j == 0 ? nil : [tasks objectAtIndex: j - 1];
          NSString *taskID = task == nil ? @"" : [task objectForKey: @"id"];
          NSMenuItem *item = [taskMenu addItemWithTitle: task == nil ? @"Client default (enter description)…" : [task objectForKey: @"name"] action: @selector(startStatusTimer:) keyEquivalent: @""];
          [item setTarget: self];
          [item setRepresentedObject: [NSDictionary dictionaryWithObjectsAndKeys: clientID, @"clientID", taskID, @"taskID", nil]];
        }
      [clientItem setSubmenu: taskMenu];
    }
  [_statusStart setSubmenu: clients];
  [_statusStart setTitle: [[_ledger clients] count] == 0 ? @"Start Timer (add a client first)" : @"Start Timer"];
  [self updateStatusItem: nil];
}

- (void) startStatusTimer: (id)sender
{
  NSDictionary *selection = [[[sender representedObject] retain] autorelease];
  NSString *taskID = [selection objectForKey: @"taskID"];
  NSString *description = @"";
  NSString *error = nil;
  if (selection == nil || [_ledger timer] != nil || [NSApp modalWindow] != nil) return;
  if ([taskID length] == 0)
    {
      NSDictionary *form;
      [NSApp activateIgnoringOtherApps: YES];
      form = [self editForm: @"Start Timer — describe your work"
        labels: [NSArray arrayWithObject: @"Description"] values: [NSArray arrayWithObject: @""]];
      if (form == nil) return;
      description = [form objectForKey: @"Description"];
    }
  if (![_ledger startTimerForClient: [selection objectForKey: @"clientID"] task: [taskID length] > 0 ? taskID : nil description: description error: &error])
    {
      [NSApp activateIgnoringOtherApps: YES];
      [self showError: error];
    }
  [self refresh];
}

- (void) toggleDockVisibility: (id)sender
{
  BOOL hide = [NSApp activationPolicy] != NSApplicationActivationPolicyAccessory;
  if ([NSApp setActivationPolicy: hide ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyRegular])
    [[NSUserDefaults standardUserDefaults] setBool: hide forKey: @"HideDockIcon"];
  else
    [self showError: @"Could not change Dock visibility. Please try again."];
  [self updateStatusItem: nil];
}

- (void) showMainWindow: (id)sender
{
  [NSApp activateIgnoringOtherApps: YES];
  if ([_window isMiniaturized]) [_window deminiaturize: nil];
  [_window makeKeyAndOrderFront: nil];
}
#endif
