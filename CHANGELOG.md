# Changelog

Changes to AppScope are recorded here. Version numbers describe the executable,
MCP tools and data behavior together. Preview releases may change these contracts;
check release notes before updating and back up private local data.

## 0.0.3-alpha — 2026-10-02

Private Apple account setup and resumable agent requests. This alpha remains
ad-hoc signed, not Developer ID signed or notarized.

- Missing credentials now return nonblocking `setup_needed` guidance to background
  callers. Tool discovery explains how live conversations opt into invitations.
- Cancelling private setup snoozes invitations for seven days without shortening
  a saved decline. Explicit retry can reopen setup; account and app choices persist.
- Resumed daily reports and strategies collect both requested providers. Explicit
  refresh exclusions and frozen keyword selections survive setup and restart.
- Added agent-led Apple account setup: a private native form, key import, ID
  autofill, saved decisions and automatic continuation of the original request.
- Added `start_connection`, `connection_status`, `connection_decision` and
  `cancel_connection`, bringing AppScope to 28 MCP tools. Background jobs
  remain noninteractive; declines survive server restarts.
- Added structured onboarding and scoped capability evidence to reports, setup,
  refreshes and credential failures. Partial access and pending/disabled reports
  stay distinct from missing or rejected credentials.
- Credentials and key changes now reload without restarting MCP, invalidating
  old Ads tokens and verification evidence. Setup uses fresh refresh runs so
  earlier credential-related skips cannot be mistaken for new collection.
- Added synthetic session, import, rotation, cancellation, restart and real MCP
  transport coverage. Apple authentication and host invitation presentation still
  require live qualification.

Existing config, history and cached reports are retained. Connection sessions,
preferences and capability evidence add local record kinds without a destructive
SQLite migration. Response fields are additive; clients should tolerate them.
Older binaries cannot use the four connection tools or resume their sessions.
Back up private local data before updating or downgrading an alpha installation.

## 0.0.2-alpha — 2026-09-07

First public alpha. This release names the previously local 0.2.0 development
preview as 0.0.2-alpha; existing local data is retained. Includes Scout branding
and complete installation/MCP connection instructions. The universal download
is ad-hoc signed, not Developer ID signed or notarized.

- Added `refresh_app` and `refresh_status`: ordered collection, durable checkpoints,
  fixed keyword selections, resumable bounded requests, per-app/country OS locks
  and optional MCP progress notifications.
- Added report health by source, separately dated latest popularity, compact
  7/30-day trends, paginated detailed comparisons and recurring competitor changes.
- Added experiment recording, listing, revision-checked updates and equal-window
  reports. Original baselines remain preserved when later analytics corrections arrive.
- Tightened comparison coverage per date, country and individual metric. Missing
  country/metric days cannot become a comparable performance decline.
- Added guided Terminal credential configuration, safe local Apple Ads key
  generation, and read-only `doctor --live` / `check_connections` diagnostics.
- Increased MCP surface to 24 tools; documented all inputs, responses and workflows.
- Release archives include version/source provenance and fresh staging. Homebrew
  formulas verify archive versions. Public packaging can require credentials and
  rejects notarization results other than Accepted.

Existing v0.1 data is retained; new features add record kinds and response fields
without a destructive SQLite migration. Run `app_performance` with `sync: false`
to recalculate new coverage fields for previously cached analytics. Old clients
should tolerate added JSON fields. No automatic scheduler or Apple listing/ad
write capability was added. Public release, notarization and live account/device
qualification remain separate from local build/tests.

## 0.1.0 — local preview, not yet published

- Native Swift stdio MCP server with 16 tools and matching direct CLI calls.
- Public app discovery, metadata and owner-provided audience/purpose briefs.
- Country-specific keyword tracking, observed iTunes Search positions, competitors,
  explained competition estimates and persistent daily comparisons.
- Apple Ads Platform API suggestions with available popularity and a separate
  weekly search-term popularity tool.
- App Store Connect report imports for downloads, engagement and purchases, with
  corrections, coverage, refund adjustments and explicit missing metrics.
- Cached agent briefings and provisional ASO experiments; host-owned daily job
  template.
- Private local credential configuration, in-memory tokens and SQLite history.
- Source installer, universal Mac archive packaging and Homebrew formula generator.
- Public-facing handbook, complete source-derived tool reference, synthetic
  examples and automated documentation checks.

Validation: 21 deterministic tests passed, including an MCP subprocess client;
the installed executable's public workflow was exercised live on Apple Silicon.
See the dated [validation record](docs/VALIDATION.md) for precise coverage.

Known limits: authenticated Apple account qualification, physical-device rank
comparison, Intel/clean macOS 14 runtime checks, Developer ID notarization and
public GitHub/Homebrew publication remain outstanding. Apple conversion rate is
unavailable. No UI, scheduler, exhaustive reverse keyword index or Apple metadata/
campaign write tools are included.
