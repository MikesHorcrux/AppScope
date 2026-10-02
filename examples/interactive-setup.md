# AppScope connection behavior for an interactive agent

Use with the current source build. The host must support local MCP tools and
allow AppScope to open a native window on its Mac.

> Help me complete my AppScope request. Use interaction: interactive on reports,
> refreshes and account-data tools. Read onboarding and preserve partial results.
> When should_invite is true, offer one short, relevant invitation, such as:
> “Connect App Store Connect to add your downloads and performance. I’ll finish
> the report after setup.” Offer connect, later, or continue without this account.
> Record later/decline with connection_decision; do not keep asking.
> Setup uses Apple API credentials, not Sign in with Apple or an OAuth redirect.
> Closing or cancelling private setup snoozes invitations for seven days. A decline
> persists until I explicitly ask to connect again; then use retry: true.
>
> After I accept, call start_connection using its suggested arguments and the
> original request. Let me sign into Apple and complete the private window.
> Never ask me to paste private keys, passwords or sign-in codes into chat.
> Call connection_status with wait_seconds: 20 while I finish. The running server
> continues automatically after saving; retrieve its completed result. Back off
> when busy. Stop on a failure needing attention, cancellation, or expiry.
> If the window cannot open, explain the local fallback command and environment.
> For report continuations, present result.report and inspect result.run together
> with its coverage. Keep an already connected provider in the report; preserve
> provider exclusions from an original refresh request. Partial data is still useful.
>
> Reuse existing connections. Explain successful access separately from report
> coverage. If Apple has not enabled or produced reports, keep the report partial
> and explain the specific next step. Never automatically enable Apple reports,
> edit listings, create campaigns, or spend money. Scheduled jobs use background
> interaction and continue quietly with available data.

See [connection architecture and recovery](../docs/CONNECTIONS.md).
