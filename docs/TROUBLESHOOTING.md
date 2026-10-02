# Troubleshooting

Start with the installed executable, outside the MCP host:

```sh
"$HOME/.local/bin/appscope" --version
"$HOME/.local/bin/appscope" doctor
```

Use your custom install path if different. `doctor` checks local configuration
presence and database access; it does not authenticate with Apple. A successful
live provider call is the access check. Never paste private keys or your complete
configuration into a chat or issue.

## Installation and agent connection

| Symptom | Check and recovery |
|---|---|
| `command not found: appscope` | Run the absolute installed path above. Add its directory to your shell's PATH if desired. GUI MCP hosts should use an absolute command path. |
| `swift: command not found`, missing SDK or build errors | Source installs require Swift 6+ and a macOS SDK. With full Xcode installed, select it using the command below. A compiled release needs no compiler. |
| `no such module 'Testing'` | Use the full Xcode developer directory for `swift test`; the selected Command Line Tools may not include the test framework. |
| macOS blocks a downloaded executable | Check that it came from the intended release and matches its checksum. Verify the release's signing/notarization status with its maintainer. Do not disable Gatekeeper. Source installation is an alternative. |
| Host cannot start the server | Use `command` pointing to the executable, with `args: ["serve"]`. Do not put shell syntax, quotes, or the word `serve` inside `command`. Check the host's stderr log. |
| `appscope serve` appears to hang in Terminal | It is waiting for MCP messages on stdin. Use `appscope call` for direct testing; the MCP host normally launches `serve`. |
| Host sees no tools | Restart that MCP connection after changing settings. Confirm it supports launching a local stdio server and has tools enabled. Version 0.0.3-alpha advertises 28 tools; the older v0.0.2-alpha archive has 24. |
| Terminal sees data but the host does not | Compare `APPSCOPE_DATA_DIR`, `APPSCOPE_CONFIG`, executable version and macOS user in both environments. A GUI host need not inherit Terminal's environment. |
| Ranking batches time out | Start with `batch_size: 3`, follow `next_offset`, and use a host tool timeout of at least 120 seconds. An uncached 10-term batch includes roughly 30 seconds of pacing, plus network time/retries. |

From a source checkout with full Xcode at its usual location:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Check the [installation guide](SETUP.md) for host configuration and updates.

## Configuration and authentication

| Error or state | Meaning and next step |
|---|---|
| `credentials_missing` / `not_configured` | Use the private connection window or `appscope configure` for that provider. Apple Ads and App Store Connect are independent. Public searches remain available. |
| `configured_unverified` | All required strings are present. This state does not turn into a permanent verified badge after authentication. Test an actual provider call. |
| `invalid_config` | Correct JSON syntax locally: double quotes, no comments or trailing commas. `setup` preserves existing files; rerunning it does not repair invalid JSON. |
| `unsafe_permissions` | Set the actual config and private-key files to mode 0600. Do not loosen permissions to make a host work. |
| `unsafe_file` | Use a regular private credential file; do not supply a directory or special file. |
| `invalid_private_key` | Check the configured path, file readability, and unencrypted P-256 PEM format. Ensure the key belongs to the configured provider/key ID. |
| `provider_http_401` | Check matching IDs/key, revocation status and the Mac's clock. Ads uses its client/team/key IDs; App Store Connect uses its team issuer/key IDs. |
| `provider_http_403` | Ask the account administrator to verify the API user's/key's role and access. Check the Ads Platform API ad account ID separately from a legacy org ID. |
| `provider_http_400` | Check app ID, storefront, date interval and the documented genre enum. Use the tool schema and Apple account documentation. |

For the default configuration location:

```sh
chmod 600 "$HOME/Library/Application Support/AppScope/config.json"
```

Apply `chmod 600` separately to your actual private-key file. Retry the tool
call after config/key changes. AppScope intentionally withholds provider
error bodies and native error details; this is why an error may be less detailed
than a raw Apple response. See the [credential walkthrough](CREDENTIALS.md).

## Rankings, competitors and popularity

| Symptom | Explanation and recovery |
|---|---|
| `app_not_found` | Confirm the numeric app ID and availability in the requested country. Search by name and verify the developer and returned URL. |
| `rank: null`, `status: not_found` | The app was absent from the actual returned list. Read `searched_count`; this is not a network error or a rank of 201. |
| Rank differs from an iPhone | The source is iTunes Search API order, which has not been qualified as equivalent to device results. Preserve that distinction in reports. |
| No rank movement on the first day | Comparison requires an observation from a prior UTC date with the same source and requested depth. Keep collecting daily. |
| Repeated calls return the same time | The latest matching snapshot is reused for 15 minutes. `cache_hit: true` identifies a reused observation. |
| `tracking_limit` | At most 100 unique terms per app/country are tracked. Use `untrack_keywords` to free selection slots; history stays available. |
| `invalid_arguments`, `invalid_keyword`, `invalid_country`, `invalid_app_id` | Use exact schema names and types, digit-string app IDs, two-letter countries and nonempty phrases up to 100 characters. Omit optional values instead of passing null. |
| No popularity for an exact keyword | Apple suggestions do not guarantee a response for every seed. Missing remains unknown even with valid credentials. |
| New suggestions do not appear in a saved rank | Popularity is copied into a snapshot when it is created. Existing snapshots are not rewritten; a cached rank can contain an older score. Combine newer suggestion results explicitly with their dates, or wait for the next uncached observation. |
| Competition is `unknown` | Rating counts needed by the estimate are missing. Do not relabel unknown pressure as low difficulty. |
| `invalid_period` for popularity | Use complete Sunday–Saturday week boundaries, no future end date, and at most one year. These are UTC dates. |
| `provider_http_429` or recurring network failures | Let the bounded built-in retries finish, reduce job frequency and run one server/job at a time. Separate processes have separate rate limiters. |
| `invalid_search_results` / `invalid_response` | The returned data did not meet the expected schema. No new rank is stored. Preserve the old observation and report the failed refresh. |

## Analytics and daily reports

`app_performance` can succeed as a command while `sync.status` is `error` and
cached data is returned. Inspect `sync`, each metric's coverage and dates before
concluding that downloads or revenue changed.

| Symptom | Explanation and recovery |
|---|---|
| No active report request / reports pending | An Admin key must enable ongoing reports once using `enable-reports APP_ID --confirm`. Initial generation can take 24–48 hours; then sync again. An inactive request needs re-enabling. |
| `synced` but some reports are missing | Sync completion does not guarantee all three report types or every requested date. Read `missing_reports` and per-report coverage. |
| Old dates remain empty | Summary dates and import lookback are separate. Increase `sync_days` if appropriate (7–90 processing days). Full historical backfill is not implemented. |
| Country metrics are null | Missing matching report rows are unknown, not zero. Check country, dates, report type and available coverage. |
| Conversion rate is null | Expected in v0.0.3-alpha. AppScope does not reconstruct Apple's conversion rate from segmented unique counts. |
| `unsafe_url`, `invalid_report`, checksum/size errors | The import stopped rather than accepting unexpected data. Keep existing data, record the error code and report a sanitized reproduction. Do not bypass validation. |
| `daily_report` is `incomplete` | Save a brief, fetch a profile, track keywords and finish every refresh batch. Read missing/stale lists. The briefing itself performs no network requests. |
| Report says `rankings_current` but performance is old | That status describes only today's tracked rankings. Fetch `app_performance` and inspect its independent dates/coverage. |
| Nothing runs automatically | The agent must schedule the job. Installing AppScope alone does not create a daemon or daily task. Use the [job template](../examples/hex-daily-job.md). |

## Local storage problems

For `database_error`, stop other AppScope connections, check free disk space and
whether the configured data directory is writable by your macOS user. Preserve a
backup before troubleshooting corruption. Do not delete SQLite working files
while a server is running. Follow [backup and restore](SETUP.md#backup-and-restore).

To distinguish an installation problem from a data/config problem, launch
`doctor` with a fresh, private `APPSCOPE_DATA_DIR` and no `APPSCOPE_CONFIG` override.
This creates a separate empty database; it does not recover the original history.
Never overwrite the original database as a diagnostic step.

## What to include in a public issue

Include AppScope version, macOS version/architecture, installation method, host
name/version, tool name, redacted arguments, error code, and expected versus
observed behavior. State whether this happens with fresh local data and whether
the provider call was public or authenticated. Remove account identifiers,
private app information, tokens, signed report URLs and local usernames/paths.
Do not attach config, databases, keys, or raw authenticated report exports.

## Refresh runs and guided setup

For `refresh_busy`, another process holds this app/country's lock. Read
`refresh_status` and wait for that process to finish; a leftover `.lock` filename
alone is harmless. For a saved running/paused/interrupted state, resume the run
on the same UTC date. For `run_expired`, start a new run. Changed options or a
new tracked selection require `new_run: true`. See [recovery](REFRESH.md).

`terminal_required` means guided configuration was launched without a real
Terminal. Use `appscope configure apple-ads` or `appscope configure app-store-connect`
in Terminal. Ctrl-D cancels without saving. Missing fields or invalid/unsafe keys
are rejected before replacing existing config. `keygen apple-ads` intentionally
refuses to overwrite an existing key pair. Keep existing private keys; do not
regenerate them as a routine fix for an authentication failure.

`doctor --live APP_ID` checks public lookup and configured account access. Inspect
its per-provider `checks`, even when the CLI exits successfully. A successful
App Store Connect access check still needs a real report import to validate data.
