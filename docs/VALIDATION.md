# Local validation

## Release preparation — 2026-10-02

Version `0.0.3-alpha` includes the private connection work and onboarding contract
fixes below. Its release source passed the complete **54-test** suite, including
the official SDK's real stdio MCP subprocess, on Apple Silicon with Swift 6.4
and the Xcode macOS 27 SDK using the supported native build engine. Strict Swift
format lint passed for all 15 Swift files changed since `v0.0.2-alpha`.

The versioned tool reference, all **28 schemas and synthetic examples**, fenced
JSON and relative links passed the documentation check. Release preparation
preserves the pinned dependencies and existing CI workflows. Packaging now builds
native architecture slices separately and combines them with `lipo`, avoiding the
Swift 6.1 combined-build manifest failure observed in CI. Packaging,
CI results and uploaded asset verification are separate checks recorded with
the GitHub release; these source tests do not establish their success.

This remains an alpha. No real Apple credentials, account roles or report
availability were qualified. The complete registered-host invitation and resumed
report workflow, Intel runtime, a clean macOS 14 installation and ordinary
quarantined-download/Gatekeeper behavior remain unverified. Ad-hoc signing does
not establish Developer ID signing or notarization. The Relic ticket's live
acceptance work remains In Progress.

## Onboarding contract follow-up — 2026-10-02

Prepared on `codex/onboarding-qualification` in an isolated copy of
`codex/apple-account-onboarding` at `781290a`, using Swift 6.4 and the Xcode macOS
27 SDK on Apple Silicon. These checks preceded release preparation.

- New regressions first reproduced missing background setup actions, cancellation
  re-invitations, and collection dropping the already connected provider.
- The complete `swift test` suite passed: **54 tests**, including the real stdio
  MCP subprocess. New cases cover nonblocking background actions, cancellation
  snoozes across restart/countries, explicit retry, permanent declines,
  app/account preference precedence, both mixed-provider report directions,
  original refresh exclusions and frozen keywords across restart, HTTP 401/403/500
  verification failures, and continuation stopping before collection on failure.
  Existing partial-access, report-readiness, secret-boundary, concurrent worker,
  cancellation and private-import regressions remain passing.
- Generated documentation passed for all **28 tool schemas and examples**, fenced
  JSON and relative links. Changed Swift files passed strict format lint; the
  patch passed `git diff --check`. The built CLI help ran successfully.
- A deterministic fixture host made **11 bounded requests** to the actual MCP
  subprocess using protocol `2025-11-25`. Tool discovery advertised interactive
  setup. A cached report retained one fictional public ranking; background setup
  actions did not invite. Interactive requests exposed both invitations;
  cancellation, decline and explicit retry produced their expected states.
  Native setup UI was disabled, account configuration remained empty, and no
  provider verification or credential entry was performed in this walkthrough.

SwiftPM's default build engine could not sign its generated test bundle because
of Finder metadata. The supported native build engine completed the build/tests.
The execution environment also required approved execution for SwiftPM's nested
manifest sandbox. Build concurrency was limited to two jobs, dependency versions
stayed pinned, and dependency updates/credential stores were disabled.

The deterministic host walkthrough proves the stdio contract and a scripted
invitation renderer. It does **not** prove that a registered agent host naturally
presents the invitation or delivers a live completed report. No AppScope tools
were exposed to the implementation task's host. Real Apple authentication,
account roles, report availability, native packaged/Gatekeeper behavior, and
Intel/macOS 14 runtime qualification remain outstanding. No real account was
connected and no reports, listings or campaigns were changed. Keep the Relic
ticket In Progress until the required live host/account acceptance is evidenced.

## Private Apple connections — 2026-09-29

Branch: `codex/apple-account-onboarding`. Unreleased source build on Apple Silicon
with the Xcode macOS 27 SDK; deployment target remains macOS 14.

- `swift test`: **47 tests passed**, including the real stdio MCP subprocess.
  New coverage exercises invitation/decline persistence, background suppression,
  scoped and expired verification, partial access, pending reports, private key
  import, stale edit rejection, credential/key rotation without restart, bounded
  continuation across restart, cancellation, concurrent workers, repair, and
  fresh refresh IDs with preserved provider options.
- The real MCP test discovers 28 tools, reads an interactive invitation, starts
  and cancels a setup session with UI disabled, rejects credential arguments,
  and sees externally saved credentials without restarting the process.
- Both native provider forms were opened and visually inspected. An isolated
  App Store Connect form selected a synthetic `.p8`, filled the key ID from its
  filename, accepted a dummy issuer ID, saved, and closed. The session became
  `saved`; imported key/config modes were 0600 and the source remained intact.
  Apple Ads prepared a private key and exposed its public-key copy action.
  Cancelling both provider flows was read back from local session records.
- Native testing caught a file-type filter that could disable valid `.p8` files.
  The picker now accepts file selection and validates P-256 contents locally.
- `swift format lint --strict` passed for changed Swift files. Generated schemas,
  all 28 examples, fenced JSON and relative links passed the documentation check.

All credentials and provider responses in these checks were synthetic and stored
in isolated directories. No real Apple account was connected, no reports were
enabled, and no listings or campaigns changed. Still to qualify: real Apple
authentication/roles/report availability, an agent host visibly presenting the
invitation and delivering the completed report, packaged/Gatekeeper behavior,
and Intel/macOS 14 runtime operation. Local tests do not establish those outcomes.

## Public alpha candidate — 2026-09-07

Version 0.0.2-alpha names the previously local 0.2.0 feature set for the first
public release. All 35 tests passed again with the alpha version, including the
real MCP subprocess test. Generated docs and examples passed validation. The
archive targets Intel and Apple Silicon on macOS 14+. It is ad-hoc signed, not
Developer ID signed or notarized. Prior live public-data evidence and remaining
account/device/Intel runtime gates below still apply.


## v0.2.0 — 2026-09-06

Verified locally on an Apple Silicon Mac with Swift 6.3.3 and the Xcode macOS SDK.
The installed executable reports `0.2.0` and exposes 24 MCP tools.

- **35 automated tests passed.** Coverage includes durable refresh recovery,
  cancellation and lock release, fixed keyword selections, expired checkpoints,
  daily observation selection, recurring competitor changes, experiment creation
  retries and revision conflicts, preserved baselines, later analytics corrections,
  credential setup, and independent connection-check failures.
- The real Swift MCP client test passed against both the development executable
  and the installed universal executable. It discovered all 24 tools, resumed a
  saved refresh, and received increasing progress notifications with its supplied
  progress token.
- An installed CLI process refreshed a live public app and saved a paused
  checkpoint after the profile step. A new process resumed the same run and
  completed two keyword observations. Metadata and rankings were reported fresh;
  unconfigured popularity and performance sources remained explicit. The overall
  report was partial, as expected without account data. This check used a separate
  local data directory and no account credentials.
- The same live workflow read keyword trends and recorded a synthetic local
  experiment. Its report remained `collecting`, with unavailable comparison
  changes set to null. No App Store listing was changed. Seven-/thirty-day movement
  and full experiment comparisons were tested with dated fixtures; this new live
  history has not accumulated those periods yet.
- A focused failing regression exposed an analytics coverage gap: report dates
  alone did not establish matching country rows or values for each metric. The
  fix adds that coverage and prevents incomplete periods from producing a
  numerical experiment comparison or a fresh performance classification.
- Guided setup was exercised through a real pseudo-terminal: successful save,
  cancellation preserving configuration, and refusal without a terminal.
  Synthetic key generation and configuration tests verified private permissions
  and rejection of invalid keys or accidental key replacement.
- The universal archive built successfully. Both `arm64` and `x86_64` slices
  declare macOS 14.0 and link to system runtime libraries. Its checksum and strict
  ad-hoc signature verification passed. Installation preserved existing config;
  only the ARM slice was executed on this Mac.
- Generated tool documentation, all 24 synthetic examples, fenced JSON and
  relative documentation links passed validation, including the extracted
  handbook. Swift format lint, shell syntax and Git whitespace checks passed.
- The archive includes a version marker and clean-commit provenance in
  `BUILD.json`. Homebrew formula generation and Ruby syntax checks passed with an
  explicitly synthetic release URL; mismatched filenames were rejected. This is
  not a public tap installation test.
- Notarization result checks accepted `Accepted` and rejected invalid, pending or
  missing statuses. Requiring notarization without signing prerequisites failed
  before building. No actual signing submission was made.

**Remaining qualification:** live Apple Ads access, App Store Connect imports
and reconciliation, physical-device search comparisons, Intel runtime, and a
clean macOS 14 download/install. No Developer ID Application identity was available
for this build, so the archive is ad-hoc signed and **not notarized**. GitHub
publication and a real Homebrew tap install remain pending. Automated fixtures,
configuration validation and a successful public search do not establish those
results. No Hex schedule was enabled.

The following sections preserve the earlier v0.1 verification record.

## v0.1.0 — 2026-09-06

Verified on an Apple Silicon Mac with Swift 6.3.3 and the Xcode macOS SDK.

- `swift test`: 21 passing Swift Testing tests, including a real Swift MCP client
  launching the server executable as a subprocess.
- The same MCP integration test passed against the installed universal executable.
- A second MCP client launched the installed binary and successfully called public
  app lookup, keyword tracking, a two-keyword ranking refresh, daily report, and
  persisted keyword history. The live search covered both a found app and an app
  absent from the returned results; the latter returned null, not an invented rank.
- Public live searches were performed separately from deterministic tests. No
  authenticated Apple account data was used.
- Universal archive built for `x86_64` and `arm64`; both Mach-O slices declare
  macOS 14.0 as their minimum. The ARM slice was executed on the local Mac. An
  Intel Mac and a clean macOS 14 machine have not been used for runtime checks.
- Source and binary installers and private setup configuration verified. New data directory
  permissions are 0700; configuration/database files are 0600.
- Format lint, shell syntax, Git whitespace checks and a source scan for private
  key/token patterns passed. This scan is not an independent security audit.

The release archive has an **ad-hoc development signature**, not a Developer ID
signature or notarization ticket. Source and distribution files are ready locally;
a public GitHub release and Homebrew tap have not been published.

Account-specific Apple Ads/analytics access remains unverified without credentials.
Tests validate synthetic request/response shapes, ES256 signatures, token isolation,
missing popularity, pagination host restrictions, report segment atomicity,
corrections, refund handling, missing metrics, and concurrent tracking limits.
These tests do not establish live account qualification or device search accuracy.

Apple's conversion rate is intentionally unavailable in v0.1; see the data contract.
Hex scheduling is not enabled by this project. A host-side daily job template is
provided separately in `examples/hex-daily-job.md`.

## Documentation qualification — 2026-09-06

- Re-ran the 21-test suite successfully after adding the maintainer docs utility.
- Generated the tool reference and JSON catalog from the runtime catalog; all 16
  synthetic calls passed schema/selected semantic validation. Fenced JSON and
  relative documentation file links passed checks, including the agent index.
- In isolated copies, confirmed the checker rejects stale generated files,
  broken relative links, malformed fenced JSON and unexpected tool arguments.
- Rebuilt the universal archive, verified its portable SHA-256 checksum, extracted
  it and checked the handbook's links without a source tree present.
- From that extracted archive, installed into a temporary prefix and verified
  setup, doctor and nine local CLI workflows with synthetic data. The performance
  example used `sync: false`; no authenticated provider request was made.
- Swift formatting, shell syntax, Git whitespace and a limited public-doc scan
  for local usernames/app identifiers/private-key patterns passed. This was not
  an independent security audit or a complete secret-detection guarantee.

CI and packaging now run `swift run appscope-docs --check`. The check does not
validate external URLs, Markdown anchors, live account access or the accuracy of
all explanatory prose. The Homebrew formula now includes the complete handbook;
an actual public tap install remains a publication-stage check.
