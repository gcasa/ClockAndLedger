# Clock & Ledger

A native, local-first desktop time and invoice tracker written in classic
Objective-C. Runs on GNUstep and macOS AppKit. No browser, server, subscription,
ARC, properties, blocks, object literals, subscripting, or fast enumeration.
Source uses GNU C brace/indentation conventions and autogsdoc API comments.

## What works

- Create and edit clients, addresses, email and default hourly rates.
- Start/stop one live timer; it survives restarts and includes time while the
  application is closed or the computer sleeps.
- Enter an individual date, a weekly/monthly total, or daily hours in a weekly
  or monthly timesheet. View hours and charges and delete unbilled mistakes.
- Define tasks per client with separate hourly rates; edit, archive and restore
  tasks while preserving the rates and names on existing time/invoices.
- Bill a raw number of hours using an active client task's current rate, with no timesheet required.
- Optionally convert a client's unbilled timesheet hours into an invoice at their recorded rates.
- Open an Apple Mail draft with an invoice PDF, complete invoice text, and a per-client payment reminder.
- Preserve original time rates and invoice snapshots when client/business
  details change. Billed time is locked against deletion or duplicate billing.
- Set a tax percentage and due date; mark invoices paid/unpaid and see overdue
  status, unbilled charges, outstanding balances and paid totals.
- Preview and print invoices with wrapping and multiple pages. Use the native
  print dialog's PDF/file output when provided by the platform/backend.
- Import QuickBooks IIF and CSV exports with a review step, duplicate detection
  and atomic saving. [Supported formats and export instructions](Documentation/QuickBooks-import.md).
- Save business/payment details and copy the ledger using **Back Up Ledger**.

This is an initial time-billing application, not a complete accounting suite.
It does not yet include expenses, bank feeds, payroll, inventory, projects,
partial payments, credit notes, invoice voiding, or multi-user/cloud sync.
Issued invoices cannot currently be edited or removed.

## Build on GNUstep

On Debian/Ubuntu, install the GNUstep development tools and a GUI backend:

```sh
sudo apt-get install build-essential gobjc gnustep-make \
  libgnustep-base-dev libgnustep-gui-dev gnustep-back0.29-cairo
. /usr/share/GNUstep/Makefiles/GNUstep.sh
make -f GNUmakefile
openapp ./ClockAndLedger.app
```

The backend package name may differ by distribution/version. An X11 desktop
session and configured printing backend are needed to run/print. The source
uses Objective-C 1.0 language features with current Foundation/AppKit APIs;
it does not target historic NeXTSTEP SDKs.

Build and ledger tests were verified with GCC 12, the traditional GNU Objective-C
runtime, GNUstep Base 1.28 and GUI 0.29 on Debian Bookworm (ARM64).
The Linux GUI and a physical printer have not been exercised here.

## Build on macOS

Requires Xcode or Command Line Tools with the macOS SDK. Explicitly select
`Makefile`, because GNU make prefers `GNUmakefile` when both exist:

```sh
make -f Makefile macos
make -f Makefile run
```

The app is created at `build/ClockAndLedger.app`. It is a local unsigned build.

## First use

1. Open **Business**, enter your business and payment details, choose a
   currency, then save. All monetary values use two decimal places.
2. Open **Clients** and add a client with their hourly rate and **Net payment days** (default 30; 0 means due on receipt). Invoice due dates are calculated by adding these calendar days to the issue date, for both direct billing and timesheet invoices. You can override the due date before issuing an invoice. Changing client terms does not change existing invoices. In the same client editor, **Starting invoice #** optionally starts a client sequence (for example, 500 gives `INV-00500`). Blank uses business numbering. Both billing workflows advance the client sequence and skip numbers already used, including deleted invoices. Once the client sequence has been used, its starting number is fixed; existing invoices keep their numbers.
3. In **Client Tasks**, select a client and add work types such as Design,
   Development or Support, each with its own hourly rate.
4. Optionally open **Timesheets**, choose the client and task (or **Client default**), and enter
   optional notes. Start/stop the timer, or choose **Day**, **Week** or **Month**,
   enter a date within that period, choose an entry method and click **Add Time…**.
   **One total for period** creates one entry for the entire range.
   **Daily timesheet** opens a row for every date; enter decimal hours
   (`1.5` means 1 hour 30 minutes) and leave unused days blank or zero.
   A description is required when using the client default rate.
5. Open **Invoices**, choose the client and an active **Task**, and enter **Hours**,
   tax percentage, **Issued** date and due date, then **Create Invoice**. The issued
   date defaults to today; changing it recalculates the due date using the client’s
   net payment days. You can still override the due date. Billing uses the displayed
   task rate and does not consume or create timesheet entries. Alternatively,
   in **Timesheets**, review the selected client's total and available hours and
   use **Create Invoice…** to convert all their unbilled time at its recorded rates.
   A running timer is excluded until stopped. Converted entries cannot be billed again.
6. Preview/print the invoice, or click **Email Invoice…** to open an Apple Mail
   draft addressed to the client's current email. The payment message appears
   above the invoice text and the complete PDF is attached. Review and send the
   draft in Mail. The **Business** email should match an enabled Mail account.
   Use **Mark Paid / Unpaid** when payment is received.

Rates and amounts use `.` as the decimal separator. Dates use `YYYY-MM-DD`.
Tax is a user-entered percentage, not a jurisdiction-specific tax calculation.
Direct invoice hours accept up to four decimal places and are billed exactly as
entered (up to 8760 hours per invoice). Timesheet hours accept up to four decimal places and are truncated to whole
seconds. Charges use exact decimal math and round half-up to cents per line;
tax rounds once on the subtotal. Displayed hours are rounded to four places.
Currency cannot change after any time is recorded; separate currencies require
separate ledger files. Make a backup before replacing any ledger file.

## Storage and recovery

Every successful change is saved atomically as an XML property list. Failed
writes report an error and restore the in-memory ledger to its previous state.
Invalid/unsupported ledger files are refused rather than overwritten. The app
uses a directory lock to guard against opening the ledger in two instances.
After a crash, use **Recover lock** only after closing all other copies.

The file lives in the platform's user Application Support directory under
`ClockAndLedger/Ledger.plist`:

- macOS: `~/Library/Application Support/ClockAndLedger/Ledger.plist`
- GNUstep: typically `~/GNUstep/Library/ApplicationSupport/ClockAndLedger/Ledger.plist`
  (depends on the configured GNUstep filesystem layout).

Backups include all clients, time, invoices, settings and any running timer.
To restore: quit every copy of the app, copy the backup to the ledger path,
then reopen the app. A restored running timer continues from its saved start
time. Data is stored locally in plaintext; backup copies use the same format.

## Tests

macOS model tests:

```sh
make -f Makefile test test-import test-time test-reminders
```

Native macOS print-pipeline test (writes an 80-entry, multi-page sample PDF
under `build/`, without sending anything to a printer):

```sh
make -f Makefile test-print test-ui
```

GNUstep model tests, after sourcing `GNUstep.sh`:

```sh
gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
  Tests/LedgerTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -o /tmp/LedgerTests \
  $(gnustep-config --base-libs)
/tmp/LedgerTests
```

Or build and test GNUstep inside an isolated Debian container:

```sh
docker build -f Tests/Dockerfile -t clockandledger-test .
```

Tests cover decimal validation/rounding, invalid dates/durations, rate and
invoice snapshots, duplicate billing, locked billed time, payment status,
recovered timers, sequential numbering, write rollback and corrupt files.
Task/calendar tests also cover leap years, Monday–Sunday week boundaries,
daylight-saving changes, task ownership, historical rate snapshots, archived
tasks, restart recovery, legacy ledgers and atomic timesheet writes.
Model tests use temporary directories and never touch the application's ledger.

## Source and documentation

- `Sources/CLQuickBooksImporter.*`: IIF/CSV parsing and source validation.
- `Sources/CLLedger.*`: validation, persistence, timing and invoice accounting.
- `Sources/CLAppController.*`: native menus, tabs, tables and editors.
- `Sources/CLInvoiceView.*`: shared preview and paginated print renderer.
- `Sources/main.m`: application bootstrap and manual memory management.
- `Tests/`: model checks, macOS PDF-print test and GNUstep build environment.

With `autogsdoc` installed, generate HTML API documentation:

```sh
make -f Makefile docs
```

Documentation goes to `Documentation/API/`. Public interfaces contain `/** … */`
comments consumed by [autogsdoc](https://www.gnustep.org/resources/documentation/Developer/BaseTools/autogsdoc.html).
Printing uses GNUstep's public
[NSPrintOperation API](https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSPrintOperation.html).

## Application icon

Both builds include the clock-and-ledger icon. GNUstep packages a transparent
PNG and generates the `NSIcon` and desktop launcher entries; macOS packages a
multi-resolution ICNS. Artwork, the generation prompt, and regeneration
instructions are in [Resources/Artwork/README.md](Resources/Artwork/README.md).

## Time periods and task rates

Weeks run Monday–Sunday; months use their actual calendar dates, including
February 29 in leap years. The date field takes any `YYYY-MM-DD` within the
chosen week or month, and the resolved range appears below it.

A timesheet uses one client and one task/rate for all its entered days. Repeat
for other tasks as needed. Blank and zero-hour days are omitted. Every populated
row is validated before saving, so one invalid row saves nothing and leaves the
form available for correction. Each save **adds** time; it does not replace an
earlier timesheet. Period totals and daily entries are alternative ways to
record work: avoid entering the same work through both methods.

Time entries preserve their task name, rate and date/range at recording time;
timers capture these when started. Renaming a task or changing its rate affects
future work only. Archive tasks to remove them from new-entry choices; restore
them in **Client Tasks** when needed. Archived tasks remain visible on past time
and invoices, and an already-running timer can still be stopped.

Invoices include each entry's task and date range and charge a weekly/monthly
total exactly once. Existing ledgers and imported time without task assignments
continue using their stored rates. New timers persist an absolute numeric start
time as well as a date to avoid timezone-dependent date decoding in GNUstep.

### Business branding and invoice numbers

In **Business**, choose a PNG, JPEG, TIFF or icon image (up to 5 MB), then save your business details. The logo appears on invoice previews and printed/PDF pages, with its proportions preserved. Logo bytes are stored in the ledger and each issued invoice, so moving the original image or replacing/removing your logo does not change older invoices. Email drafts include the branded, multipage invoice PDF as an attachment.

Set **Starting invoice number** before issuing or importing your first invoice. Leaving it blank starts at 1 (`INV-00001`); entering 500 starts at `INV-00500`, followed by `INV-00501`. The starting number is fixed once invoices exist. Existing ledgers keep their numbering, and imported invoices keep displaying their original QuickBooks numbers.

To delete an invoice, select it in **Invoices** and click **Delete Invoice…**. The confirmation defaults to Cancel and warns that deletion cannot be undone. Confirming removes the invoice and its payment status from the ledger totals and returns linked time entries to unbilled status. Standalone invoices do not create time entries when deleted. Deleted invoice numbers remain reserved, even if every invoice is deleted. Printed/emailed copies and QuickBooks records are unaffected; deleting a paid invoice does not refund payment.


## Client payment reminders and background email (macOS)

In **Clients**, select a client and choose **Email Reminders…**. Configure
**Days before due** (default 3; 0 means the due date), the friendly **Payment
reminder**, and the separate **Overdue reminder**. Blank messages use built-in
wording; overdue wording asks for prompt payment and a payment date. Templates
support `{client}`, `{invoice}`, `{total}`, and `{dueDate}`. These current client
settings also control the message above the invoice in manually opened drafts.
Paid invoices use a thank-you message instead of a payment demand.

Turn on **Send reminders through Apple Mail** to enable unattended delivery for
that client. This is off by default. Set valid client and business email
addresses first, and configure the business address in an enabled Apple Mail
account. On first use, allow the app to control Mail in macOS Automation
permissions. No email passwords are stored in the ledger.

While running, the app checks once per minute and submits at most one friendly
reminder per invoice within the configured window, then one separate overdue
reminder after its due date. If the app first sees an invoice when it is already
late, only the overdue reminder is sent. Both include the complete invoice PDF.
Paid, zero-total, and unverified imported invoices are excluded. New settings
apply to existing eligible unpaid invoices as well as future invoices.

Closing the main window leaves the app running in the background. Click its
Dock icon to reopen it. **Quit** stops checks, and nothing is sent while the Mac
is asleep or the app is not running; the next check catches up when it resumes.
The app does not install a login item. Apple Mail may queue messages while
offline: “submitted” means Mail accepted the message, not that the recipient
has received it. Check Mail for delivery failures or bounce notices.

Attempts are saved before handing mail to Apple Mail to avoid repeated sends
after a crash. Errors and interrupted attempts show **Review email** in the
invoice table. Select the invoice and click **Review Email…**, inspect Mail's
Drafts, Outbox and Sent, then either confirm submission or explicitly allow a
retry. Remove any stale draft before retrying. Turning off automatic reminders
stops future checks for that client; it cannot recall messages already handed
to Mail. Temporary PDF and message files are retained under
`~/Library/Caches/ClockAndLedger/MailExports` so queued messages and drafts can
still access their attachments.

Direct invoices now require an active task from **Client Tasks**. Select it in
**Invoices** and enter hours: the displayed task rate is snapshotted with the
task name when the invoice is issued. Later task edits do not alter the invoice.
Timesheet invoices continue to use each time entry's recorded task and rate.
Apple Mail delivery is macOS-only; the ledger, task billing and reminder policy
tests also build under GNUstep.

The **Issued** date is saved on the invoice and shown in the invoice list, PDF,
and email text. Past and future dates are supported; the due date must be on or
after the issued date. Timesheet invoice creation also has an Issued field;
changing it calculates the due date from that client's terms while preserving
the time entries' original work dates. Reminder timing follows the saved dates.

Paid invoices display a large, translucent red diagonal **PAID** stamp on every
page in previews, printed output and PDF email attachments. Marking an invoice
unpaid removes the stamp from newly generated output. Unverified imported
payment states are not stamped.

Every editable date has a calendar button alongside the text box: the timesheet
period date and the Issued and Due date fields in both invoice creation flows.
Type `YYYY-MM-DD` directly or choose a day in the calendar. **Today** selects the
current day, **Choose** applies it, and **Cancel** keeps the existing text.
Calendar selections update due dates and timesheet period summaries just like
manual entry. Dates shown on fixed daily timesheet rows remain tied to the
selected period.
