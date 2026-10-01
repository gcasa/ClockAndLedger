FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gobjc gnustep-make libgnustep-base-dev libgnustep-gui-dev \
    gnustep-base-runtime && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
COPY . .
RUN . /usr/share/GNUstep/Makefiles/GNUstep.sh && \
    gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
    Tests/ReportingTests.m Sources/CLReporting.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m \
    -o /tmp/ReportingTests $(gnustep-config --base-libs) && /tmp/ReportingTests

RUN . /usr/share/GNUstep/Makefiles/GNUstep.sh && make -f GNUmakefile && \
    gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
    Tests/LedgerTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m -o /tmp/LedgerTests \
    $(gnustep-config --base-libs) && /tmp/LedgerTests && \
    gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
    Tests/ImportTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m \
    -o /tmp/ImportTests $(gnustep-config --base-libs) && /tmp/ImportTests && \
    gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
    Tests/TimeEntryTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m \
    -o /tmp/TimeEntryTests $(gnustep-config --base-libs) && /tmp/TimeEntryTests

RUN . /usr/share/GNUstep/Makefiles/GNUstep.sh && \
    gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
    Tests/ReminderTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m \
    -o /tmp/ReminderTests $(gnustep-config --base-libs) && /tmp/ReminderTests

RUN . /usr/share/GNUstep/Makefiles/GNUstep.sh && \
    gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
    Tests/InvoiceEditTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m \
    -o /tmp/InvoiceEditTests $(gnustep-config --base-libs) && /tmp/InvoiceEditTests

RUN . /usr/share/GNUstep/Makefiles/GNUstep.sh && \
    gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
    Tests/FinanceTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m \
    -o /tmp/FinanceTests $(gnustep-config --base-libs) && /tmp/FinanceTests

RUN . /usr/share/GNUstep/Makefiles/GNUstep.sh && \
    gcc $(gnustep-config --objc-flags) -std=gnu89 -ISources \
    Tests/RecurringTests.m Sources/CLLedger.m Sources/CLQuickBooksImporter.m \
    -o /tmp/RecurringTests $(gnustep-config --base-libs) && /tmp/RecurringTests
