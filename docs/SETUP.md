# Installation and connection

AppScope runs on macOS 14+ with an MCP host that can launch a local stdio process.
The host provides the agent and scheduler. Source and compiled installations use
the same executable and local data format.

For your first app and report, follow [getting started](GETTING-STARTED.md).

## Install from source

The [official GitHub repository](https://github.com/MikesHorcrux/AppScope)
is available now. Open Terminal and run the commands below to download and
install it. Building requires Swift 6+ and a macOS SDK. The installer selects
full Xcode at `/Applications/Xcode.app/Contents/Developer` when available; otherwise
use matching Command Line Tools. Dependency resolution needs network access.

```sh
git clone https://github.com/MikesHorcrux/AppScope.git
cd AppScope
./scripts/install.sh
"$HOME/.local/bin/appscope" setup
"$HOME/.local/bin/appscope" doctor
```

The installer builds the release executable for your Mac and copies only that
program to `~/.local/bin/appscope`. It does not register a service, change PATH,
or create configuration. `setup` creates a private empty configuration if needed,
preserves existing settings, and prints MCP connection JSON. `doctor` checks local
setup without contacting Apple.

To use `appscope` without its absolute path in the current Terminal session:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

You can add that line to your own shell configuration for future sessions.
For a custom install directory, set `APPSCOPE_PREFIX` when running the installer;
the program goes into that prefix's `bin` directory. This does not change the
data directory. Use a writable prefix without `sudo`.

## Install a compiled release

Download the `.tar.gz` archive and `.sha256` file from the official
[GitHub releases](https://github.com/MikesHorcrux/AppScope/releases).
This alpha is ad-hoc signed, not Developer ID signed or notarized; macOS may block
the downloaded executable. Do not disable Gatekeeper. Source installation above
is an alternative. In Terminal, enter the folder containing the downloads. For
the v0.0.3-alpha archive, run the following; use the matching versioned filenames
if you downloaded an older alpha:

```sh
shasum -a 256 -c appscope-0.0.3-alpha-macos-universal.tar.gz.sha256
tar -xzf appscope-0.0.3-alpha-macos-universal.tar.gz
cd appscope-0.0.3-alpha-macos-universal
./install.sh
"$HOME/.local/bin/appscope" setup
"$HOME/.local/bin/appscope" doctor
```

Check that the checksum command reports `OK` before extracting. A checksum detects
file mismatch; obtain it from the trusted release alongside its signing status.
The archive includes the universal Apple Silicon/Intel executable, installer,
handbook, examples and licenses. Keep that extracted documentation if useful; the
installer copies only the executable. End users need no Swift compiler or Python.

An ad-hoc local build is not a Developer ID signed/notarized public release.
Do not disable Gatekeeper as an install step. See [troubleshooting](TROUBLESHOOTING.md)
if macOS blocks the download. Homebrew installation instructions will be added
when an actual tap is published; formula-generation support alone is not a tap.

## Connect an MCP host

Run `appscope setup` using the installed executable and copy the JSON connection
it prints into your host's MCP settings. Merge the AppScope entry with existing
servers instead of overwriting them. The conventional JSON shape is:

```json
{
  "mcpServers": {
    "appscope": {
      "command": "/absolute/path/to/appscope",
      "args": ["serve"]
    }
  }
}
```

The command above is a placeholder; use the absolute path printed by `setup`.
Some hosts use a settings form or another file format: the executable and `serve`
argument are the same. Consult that host's current MCP instructions for where to
put them. Never add credentials or private-key contents to the connection JSON.

Restart the connection and call `setup_status`. Version 0.0.3-alpha exposes 28
tools; the older v0.0.2-alpha archive has 24.
`configured_unverified` means required credential strings are present, not that
Apple access was checked. Start with `search_apps` for a public live check.

Use a host tool timeout of at least 120 seconds for ranking batches and allow
longer for initial analytics imports. Smaller batches help hosts with shorter
timeouts. Host tool permissions can restrict which capabilities the agent uses.
MCP annotations distinguish local changes, but even read-only tools may return
private account data to the host.

### Custom data/configuration paths

`APPSCOPE_DATA_DIR` changes local storage and the default config path.
`APPSCOPE_CONFIG` changes only the configuration file path. Use absolute paths
and set the same environment in the host. `setup` prints an `env` block when run
with these overrides. Config variables set only in Terminal might not reach a
GUI host. See the [full configuration reference](CLI.md).

Default private files live under `~/Library/Application Support/AppScope`.
Add optional providers using the [Apple credential guide](CREDENTIALS.md).

## Update or move the installation

1. Read the new release notes and back up local data if the data format changes.
2. Stop the host's AppScope connection so it does not keep an older process running.
3. Review/check out the intended source version and rerun the source installer,
   or verify and run the new archive's installer with the same prefix.
4. Confirm `appscope --version`, then restart the host connection.
5. Run `doctor` and a small tool call. Config/history are preserved by the installer.

If the executable path changes, rerun the new executable's `setup` and update the
host connection. Do not assume Homebrew, source and archive installs resolve to
the same binary: check `command -v appscope` and use an explicit path.

## Backup and restore

Stop **all** AppScope processes/host connections before copying data. Copy the
entire configured data directory, including any SQLite `-wal` and `-shm` files,
to your normal secure backup location. Also back up an external config file and
private keys stored outside that directory. Backups contain private app context
and account data; do not put them in a public repository.

To restore, keep the server stopped, preserve the current directory separately,
and restore a complete consistent backup into the chosen data location. Check
config/key paths and permissions (0600 for config, keys and database; 0700 for
the data directory), then run `doctor` and inspect `list_apps`/`keyword_history`.
Moving to a new Mac may require updating absolute key paths in the local config.
A future schema change may prevent older binaries reading newer data; consult
the matching release notes before downgrading.

## Uninstall

Remove the AppScope entry from the host and stop its process. Remove only the
installed `appscope` executable from the prefix you chose. The installer creates
no login item or background service to remove. Local data and credential files
remain intact; delete those separately only if you intend to discard them.
Uninstalling does not revoke keys in Apple accounts.
