<div align="center">
  <img src="assets/branding/appscope-moth-scout-v1.png" width="240" alt="Scout, AppScope’s mint-green moth mascot wearing oversized scout goggles">
  <h1>AppScope</h1>
  <p><strong>Give your agent eyes on the App Store.</strong></p>
  <p>Keyword discovery. Competitor context. Your next ASO experiment.</p>
  <p><code>Swift</code> &nbsp; <code>macOS 14+</code> &nbsp; <code>28 MCP tools</code> &nbsp; <code>MIT licensed</code></p>
  <p>
    <a href="docs/GETTING-STARTED.md">Get started</a> &nbsp; · &nbsp;
    <a href="docs/TOOLS.md">Explore the tools</a> &nbsp; · &nbsp;
    <a href="docs/README.md">Read the handbook</a>
  </p>
</div>

---

## Your apps have a story. Scout helps you read it.

**AppScope is an open-source Swift MCP server for your Mac.** It gives your AI
agent app metadata, observed keyword positions, competitor evidence, and local
history to help answer the questions behind your next release.

You ask. Scout gathers the evidence. Your agent connects the dots.

> “Where does my app show up? Who’s ahead of it? What should I try next?”

Everything stays in your agent’s workflow. No extra dashboard to check, no
AppScope subscription, and no separate LLM API key. History lives locally in
SQLite; account data uses your own credentials.

## A little scout. A useful toolkit.

| 🔎 Find your footing | 🦋 Watch the neighborhood | 🧪 Learn from changes |
|---|---|---|
| Find your app and understand its purpose | See competing apps for each keyword | Record ASO experiments and preserve baselines |
| Test keywords and record observed positions | Inspect explained competition estimates | Compare equal before/after periods |
| Keep app and audience context for your agent | Follow 7/30-day keyword and competitor trends | See missing data before drawing conclusions |

**With Apple account access**, add available keyword popularity and suggestions,
plus downloads, engagement, sales and proceeds. Your agent turns that evidence
into a briefing and possible next steps.

## First flight

### 1 · Install AppScope on your Mac

**Download a [Mac alpha release](https://github.com/MikesHorcrux/AppScope/releases)** for Apple Silicon or Intel, macOS 14+. No compiler or Python required.

Download the `.tar.gz` archive and its `.sha256` file, then follow the
[compiled installation steps](docs/SETUP.md#install-a-compiled-release).
**This alpha is ad-hoc signed and not notarized; macOS may block the downloaded
executable.** Source installation below is also available. Do not disable Gatekeeper.

**Build from source instead:** you need Swift 6+ and a macOS SDK, such as a
compatible Xcode installation.

Open **Terminal**, then copy and run:

```sh
git clone https://github.com/MikesHorcrux/AppScope.git
cd AppScope
./scripts/install.sh
"$HOME/.local/bin/appscope" setup
"$HOME/.local/bin/appscope" doctor
```

The installer puts the program at `~/.local/bin/appscope`. You do not need to
keep a Terminal window running afterward.

**Connect it to your agent:** `setup` prints your exact MCP configuration. In your
agent’s MCP settings, add a local **stdio** server using the printed executable
path as the **command** and `serve` as its **argument**. If your host uses a JSON
configuration file, merge the printed `appscope` entry into its existing servers.
Reload the connection, then ask: **“Call AppScope’s setup_status.”**

Installation puts the tool on your Mac; this connection step makes its 28 tools in v0.0.3-alpha
available to your agent. AppScope does not register itself in your host.
[Detailed connection instructions](docs/SETUP.md#connect-an-mcp-host)

> **Alpha release:** Expect rough edges. Homebrew and Developer ID notarization
> are still pending. [Installation options](docs/SETUP.md) · [Validation](docs/VALIDATION.md)

### 2 · Give your agent a mission

Copy this into your connected agent:

> Find my app and verify its developer. Save a brief about what it does and whom
> it helps. Explore relevant US keywords and show which ones actually return my
> app, its observed position, and the leading competitors. Track the useful terms.
> Suggest up to three ASO experiments, explaining the evidence and what’s missing.

Prefer a quick Terminal check?

```sh
"$HOME/.local/bin/appscope" call search_apps '{"query":"your app name","country":"us","limit":5}'
```

Replace the phrase, then verify the developer and app URL.
The [first-run walkthrough](docs/GETTING-STARTED.md) covers the rest.

### 3 · Connect the data you want

Public app and keyword searches work immediately. Add account access when you
want a fuller picture:

| You want to know… | What AppScope needs |
|---|---|
| Where does my app appear for this keyword? | Nothing extra—public search |
| Which apps compete with it? | Nothing extra—public search |
| What keywords does Apple suggest, and how popular are they? | Your Apple Ads API credentials; scores are not guaranteed for every term |
| How are downloads, engagement and sales doing? | Your App Store Connect API credentials and available, enabled analytics reports |

In v0.0.3-alpha, ask your agent to connect the account your report needs.
With your consent, AppScope opens a private setup window, checks access, and
continues the request. Your host must present the invitation and retrieve the
result; that complete live workflow still needs qualification. Keys stay on your
Mac. See [the connection flow](docs/CONNECTIONS.md).

**Each instance supports one account per provider.** Do not switch Apple teams
or ad accounts by replacing credentials in a shared data directory. Cached
private data remains, and an already-refreshing request is not bound to the
account it verified. Use separate MCP instances with distinct configuration
and data directories. [Account limits and isolation](docs/CREDENTIALS.md#one-account-per-provider)

Terminal setup remains available:

```sh
"$HOME/.local/bin/appscope" configure apple-ads
"$HOME/.local/bin/appscope" configure app-store-connect
```

Configure whichever provider you need using Apple API credentials. Follow the
[credential guide](docs/CREDENTIALS.md). Version 0.0.3-alpha reloads credentials
automatically; older alpha processes need their MCP connection restarted.

## Tomorrow, bring the receipts

Give your host the [daily job template](examples/hex-daily-job.md) to schedule a
briefing. `refresh_app` collects evidence, saves checkpoints, and returns a report
with source freshness and available trends. Interrupted work can resume on the
same UTC date.

Your agent can tell you what moved, which competitors appeared, and which
experiments have enough history to compare. **Your host handles scheduling and
report delivery**—installing AppScope doesn’t enable a Hex job or continuous scanning.

## Clear eyes about the data

Good decisions need honest measurements.

- **Positions are observed iTunes Search API order.** They are not verified device
  App Store rankings. “Not found” means absent from the returned results, not rank 201.
- **Discovery tests candidate keywords.** AppScope has no exhaustive index of every
  keyword an app ranks for. It tracks up to 100 terms per app/country.
- **Competition is an estimate; popularity is separate.** Unknown scores stay unknown.
  Audience ideas are hypotheses, not measured demographics.
- **Missing performance is not zero.** Reports can lag or have gaps. Apple’s
  conversion rate is unavailable in this alpha; authenticated adapters await live account
  qualification. Before/after differences do not prove causation.

No MCP tool changes live listings or campaigns or spends money.
[Data contract and limits](docs/DATA-CONTRACT.md) · [Response guide](docs/RESPONSES.md) · [Security](SECURITY.md)

## Pick your next trail

| Start here | Go deeper |
|---|---|
| [First report walkthrough](docs/GETTING-STARTED.md) | [Every MCP tool](docs/TOOLS.md) |
| [Installation and updates](docs/SETUP.md) | [Response shapes and data gaps](docs/RESPONSES.md) |
| [Apple credentials](docs/CREDENTIALS.md) | [Architecture](docs/ARCHITECTURE.md) |
| [Frequently asked questions](docs/FAQ.md) | [Changelog](CHANGELOG.md) |

<details>
<summary><strong>Building with Scout? Developer and agent resources</strong></summary>

```sh
swift build
swift test
swift run appscope-docs --check
```

The documentation check validates generated schemas, all 28 synthetic examples,
fenced JSON and relative documentation file links. Use full Xcode’s developer
directory if the selected Command Line Tools cannot run the tests.

- [Contributing](CONTRIBUTING.md) and [release packaging](docs/RELEASING.md)
- [JSON tool catalog](examples/tool-catalog.json) and [synthetic calls](examples/tool-calls.json)
- [Agent reading index](docs/llms.txt) and [complete handbook](docs/README.md)

</details>

---

<div align="center">
  <p><strong>Stay curious. Track the evidence. Try something useful.</strong></p>
  <p>Built with Swift, Foundation, CryptoKit, SQLite, zlib, and the official
    <a href="https://github.com/modelcontextprotocol/swift-sdk">MCP Swift SDK</a>.</p>
  <p><a href="LICENSE">MIT licensed</a> · Runs locally · No telemetry · Not affiliated with Apple</p>
</div>
