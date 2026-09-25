# Clock & Ledger

A native, local-first desktop time and invoice tracker written in classic
Objective-C. Runs on GNUstep and macOS AppKit. No browser, server, subscription,
ARC, properties, blocks, object literals, subscripting, or fast enumeration.
Source uses GNU C brace/indentation conventions and autogsdoc API comments.

## What works

- Create and edit clients, addresses, email and default hourly rates.
- Start/stop one live timer; it survives restarts and includes time while the
  application is closed or the computer sleeps.
- Add dated manual time, view hours and charges, and delete unbilled mistakes.
- Issue sequential invoices from all unbilled entries for a selected client.
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
2. Open **Clients** and add a client with their hourly rate.
3. Open **Time**, choose the client, enter a description, and start the timer;
   stop it to record a charge. Or choose **Add Manual Time** and enter decimal
   hours (`1.5` means 1 hour 30 minutes).
4. Open **Invoices**, choose the client, tax percentage and due date, then
   **Create Invoice**. The invoice captures all their unbilled entries. A
   running timer is excluded until stopped.
5. Preview/print the invoice, and toggle its status when payment arrives.

Rates and amounts use `.` as the decimal separator. Dates use `YYYY-MM-DD`.
Tax is a user-entered percentage, not a jurisdiction-specific tax calculation.
Manual hours accept up to four decimal places and are truncated to whole
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
make -f Makefile test test-import
```

Native macOS print-pipeline test (writes an 80-entry, multi-page sample PDF
under `build/`, without sending anything to a printer):

```sh
make -f Makefile test-print
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
