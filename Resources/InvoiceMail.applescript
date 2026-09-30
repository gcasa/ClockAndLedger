-- Values arrive as arguments, never as executable AppleScript source.
on run argv
    set recipientAddress to item 1 of argv
    set senderAddress to item 2 of argv
    set subjectText to item 3 of argv
    set bodyText to read (POSIX file (item 4 of argv)) as «class utf8»
    set pdfFile to (POSIX file (item 5 of argv)) as alias
    set deliveryMode to item 6 of argv
    if deliveryMode is not "draft" and deliveryMode is not "send" then error "Unknown invoice email mode."
    set sendNow to (deliveryMode is "send")
    with timeout of 90 seconds
        tell application id "com.apple.mail"
            if senderAddress is not "" then
                set matchedAccount to false
                repeat with mailAccount in accounts
                    if enabled of mailAccount then
                        if email addresses of mailAccount contains senderAddress then set matchedAccount to true
                    end if
                end repeat
                if not matchedAccount then error "The business email address is not configured in an enabled Apple Mail account."
            else if sendNow then
                error "Set a business email address before sending automatic reminders."
            end if
            set invoiceMessage to make new outgoing message with properties {subject:subjectText, content:bodyText & return & return, visible:(not sendNow)}
            tell invoiceMessage
                if senderAddress is not "" then set sender to senderAddress
                make new to recipient at end of to recipients with properties {address:recipientAddress}
                tell content
                    make new attachment with properties {file name:pdfFile} at after last paragraph
                end tell
                -- Saving a hidden outgoing message can asynchronously close its
                -- editor after visible is set. Manual drafts use Mail's autosave.
                if sendNow then save
                if (count of attachments of content) < 1 then error "Mail did not confirm the PDF attachment. No automatic send was requested."
            end tell
            if sendNow then
                if not (send invoiceMessage) then error "Mail did not confirm submission. Check Drafts, Outbox and Sent before retrying."
                return "submitted"
            else
                set visible of invoiceMessage to true
                activate
                return "draft"
            end if
        end tell
    end timeout
end run
