# CLI and configuration reference

The installed program is `appscope`. These commands match v0.0.3-alpha. Apple
account setup can open a private native window. There is no dashboard, `--json`
flag, HTTP server mode, or built-in scheduler.

## Commands

| Command | Behavior |
|---|---|
| `appscope`, `appscope help`, `appscope --help` | Print help; do not create configuration or contact providers |
| `appscope --version` | Print the version only |
| `appscope setup` | Create the data directory and an empty private configuration if absent; print the actual MCP launch settings |
| `appscope doctor` | Load config, open/create the local database and print capability/configuration presence; no network calls |
| `appscope doctor --live APP_ID` | Check public lookup and configured Apple providers with bounded read-only requests; inspect nested statuses |
| `appscope configure apple-ads` / `appscope configure app-store-connect` | Guided Terminal-only credential setup; validates the local key and saves private configuration atomically |
| `appscope connection-window SESSION_ID` | Open the private native window for an existing setup session, using this process's data/config environment |
| `appscope keygen apple-ads` | Generate P-256 key files in the data directory and print the public key; refuses to replace existing keys |
| `appscope serve` | Serve MCP on stdin/stdout until the host disconnects; diagnostics go to stderr |
| `appscope call TOOL 'JSON_OBJECT'` | Invoke the same implementation as MCP and print formatted JSON |
| `appscope enable-reports APP_ID --confirm` | Create an ongoing analytics request if no active one exists; requires an App Store Connect Admin key; not an MCP tool |

Quote the JSON argument so the shell passes it as one argument. Use JSON strings
for app IDs and arrays for keyword lists. Unknown tool arguments are rejected.
See [every tool and its example](TOOLS.md).

Exit status 1 means a top-level command/tool failure. A successful command can
still contain partial data: `app_performance` returns sync errors alongside cached
results; `refresh_rankings` returns errors per keyword. Automation must inspect
the JSON, not just the exit status. In MCP, a top-level tool failure uses
`isError: true` and a structured error object. Partial results normally have
`isError: false` and explicit nested statuses. See [responses](RESPONSES.md).

## Runtime environment

| Variable | Default | Purpose |
|---|---|---|
| `APPSCOPE_DATA_DIR` | `~/Library/Application Support/AppScope` | Root for SQLite data and the default configuration file |
| `APPSCOPE_CONFIG` | `APPSCOPE_DATA_DIR/config.json` | Override only the credential configuration file |
| `APPSCOPE_DISABLE_SETUP_UI` | Unset | Set to `1` to disable native setup launch; MCP returns a local fallback |

Use absolute paths. AppScope does not load `.env` files or expand shell variables
inside JSON. The private-key path supports `~` expansion, but absolute paths make
sharing host configurations clearer. Set environment overrides in the MCP host,
not only an unrelated Terminal session. The host must be able to read the files.

**Changing only `APPSCOPE_CONFIG` does not isolate account data.** Each instance
supports one account per provider. For another Apple team/ad account, use a
separate instance with distinct config and data directories. Replacing credentials
keeps cached private data, and already-refreshing continuations are not bound to
an account identity. [Account limits](CREDENTIALS.md#one-account-per-provider)

If `APPSCOPE_CONFIG` points outside the data directory, create its parent directory
before running `setup`. Setup preserves an existing config file and checks its
permissions. It does not validate configuration values against Apple.

Changing either path environment variable affects new processes. Credential changes
at those paths reload on the next tool call. Key replacement also invalidates the
in-memory Ads token and prior verification evidence. No credential restart is needed.

## Build and installation environment

| Variable | Used by | Meaning |
|---|---|---|
| `APPSCOPE_PREFIX` | Install scripts | Install under `PREFIX/bin`; defaults to `~/.local` |
| `DEVELOPER_DIR` | Swift/Xcode commands | Select a toolchain. Scripts choose `/Applications/Xcode.app/Contents/Developer` if it exists and this variable is unset |
| `APPSCOPE_SIGNING_IDENTITY` | Mac packaging script | Existing Developer ID Application signing identity |
| `APPSCOPE_NOTARY_PROFILE` | Mac packaging script | Existing `notarytool` Keychain credential profile |
| `APPSCOPE_REQUIRE_NOTARIZATION` | Mac packaging script | Set to `1` to require signing identity/profile; a notarized build must return Accepted before an archive is produced |
| `APPSCOPE_TEST_BINARY` | MCP subprocess test | Test a particular packaged/installed executable instead of `.build/debug/appscope` |

The prefix is not a data-directory setting. Signing variables are maintainer
settings, unrelated to Apple Ads or App Store Connect API access.

## Local files

| Location under the data directory | Contents |
|---|---|
| `config.json` | Credential identifiers and private-key paths; no key bytes |
| `appscope.sqlite3` | Briefs, metadata, tracking, rankings, suggestion scores, analytics, refresh checkpoints, experiments and cached performance results |
| `refresh-APP-COUNTRY.lock` | OS lock for same-app/country refresh exclusion; an existing file does not mean the lock is held |
| `apple-ads-private.p8`, `apple-ads-public.pem` | Key pair created only by the explicit `keygen apple-ads` command |
| `keys/` | Private copies imported by the setup window and locally prepared Apple Ads keys |
| `connection-ui/` | Private app wrappers keyed by executable hash; same executable, no extra download |
| `appscope.sqlite3-wal`, `appscope.sqlite3-shm` when present | SQLite working files; preserve them when copying an active database |

No automatic retention/deletion policy is implemented in v0.0.3-alpha. Data can grow over
time. Untracking a keyword preserves its history. Files are private local data;
they are not intended for Git, support issues, or public release artifacts.
Back up and restore using the [installation guide](SETUP.md).
