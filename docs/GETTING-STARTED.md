# Your first AppScope report

Start with one app, one country, and a few keywords. Public app lookup and search
positions work without Apple credentials. This walkthrough uses a fictional meal
planning app; use your own verified app ID and relevant terms.

## 1. Install and confirm the executable

Open Terminal on a Mac with Swift 6+ and a macOS SDK installed. Download the
source and install it:

```sh
git clone https://github.com/LunarMothStudios/AppScope.git
cd AppScope
./scripts/install.sh
"$HOME/.local/bin/appscope" setup
"$HOME/.local/bin/appscope" doctor
```

A source build needs Swift 6+ and a macOS SDK. A compiled release only needs
macOS 14+. See [installation](SETUP.md) for archive installation and updates.

It is normal for `doctor` to say `apple_ads: not_configured` and
`app_store_connect: not_configured`. That does not prevent public searches.
`configured_unverified` means the required configuration strings are present;
it is not an authentication check.

For the short CLI commands below, add the default install directory to this
terminal's PATH:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

You can instead use the full executable path every time. `setup` does not change
PATH, register an MCP host, or start a background process.

## 2. Connect your agent

Copy the JSON printed by `appscope setup` into your host's local MCP configuration.
Merge the `appscope` entry with any existing servers; do not replace unrelated
configuration. Use `serve` as the argument and the absolute executable path.
Reload the host's MCP connection using its normal controls.

Ask the agent:

> Call AppScope's setup_status and list its available tools.

Current source builds expose 28 tools; the published v0.0.2-alpha archive has 24. If the host cannot launch local stdio programs, it cannot
connect directly to this server. See [connection troubleshooting](TROUBLESHOOTING.md).
Starting `appscope serve` yourself in Terminal looks quiet because it waits for
MCP messages on standard input. That is not an installation test; use `doctor`.

## 3. Identify the correct app

Ask your agent to search for your app, or run:

```sh
appscope call search_apps '{"query":"your app name","country":"us","limit":5}'
```

Check the title, developer and App Store URL. Record the returned `app_id`, which
is a numeric string. A bundle ID such as `com.example.app` is not accepted here.
App names can collide, so do not choose an app by its name alone.

All subsequent examples use `1234567890` as a **fictional placeholder**. Replace
it before calling a provider. `country` defaults to `us`; use your target country
consistently, for example `gb` for the United Kingdom.

```sh
appscope call app_profile '{"app_id":"1234567890","country":"us"}'
```

The result includes public metadata and any saved owner brief. It also caches the
metadata for the report. Your private keyword field and actual audience demographics
are not part of public lookup.

## 4. Give the agent useful app context

Ask the agent to save your purpose, intended audience, differences, and goal.
This updates local context only. It does not edit your App Store listing.

```sh
appscope call save_app_brief '{"app_id":"1234567890","purpose":"Plan meals from food already in the pantry.","audiences":["Busy households reducing food waste"],"differentiators":["Plans around existing ingredients"],"business_goal":"Grow first-time downloads from relevant searches"}'
```

A new brief replaces the previous brief for this app. Include every required
field; use empty arrays when an audience or differentiator is not yet known.
An agent may propose additional audiences, but those are hypotheses to investigate.

## 5. Track and inspect a few keywords

```sh
appscope call track_keywords '{"app_id":"1234567890","country":"us","keywords":["pantry meal planner","reduce food waste","weekly meal plan"]}'
appscope call refresh_app '{"app_id":"1234567890","country":"us"}'
```

Tracking saves the selection. `refresh_app` collects metadata, optional Apple
popularity, every selected rank and optional analytics, then returns a briefing.
Unconfigured providers are skipped. Check `run.status` and `report.health`.

The default request completes the whole run. For a host with short timeouts,
set `max_steps: 3` and resume the returned `run_id` while its status is `paused`.
A `partial` run contains failed steps; retry deliberately, then preserve unresolved
errors in the report. See [refresh and recovery](REFRESH.md). The lower-level
`refresh_rankings` tool remains available when you want ranking batches only.

For one keyword's fuller competitor details:

```sh
appscope call analyze_keyword '{"app_id":"1234567890","country":"us","keyword":"pantry meal planner","limit":200}'
```

The result includes a position or `rank: null`, actual result count, competitors,
an explained competition estimate, timestamp, and any previously collected Apple
suggestion score. The source is `itunes_search`: **an observed search API position,
not a verified physical-device App Store rank**. Scores are unknown until available.

## 6. Read the report

```sh
appscope call daily_report '{"app_id":"1234567890","country":"us"}'
```

The CLI prints structured evidence. Your agent turns it into readable prose:

> Use this evidence to explain my current positions, the strongest competitors,
> and up to three relevant ASO experiments. Separate facts from hypotheses. Include
> country, data dates and gaps. Do not claim complete keyword coverage or exact device
> ranks. Do not edit my listing or spend money.

The first report has no previous-day ranking baseline. That is expected. Refresh
on a later UTC date to build comparisons; refreshing repeatedly on the same day
does not create a day-over-day trend. Matching ranking observations use a 15-minute cache.

`daily_report` reads saved data; it does not collect fresh data. Without Apple
credentials, its performance field may be null. `rankings_current` describes only today’s ranks. Use `health.sources` for freshness
and gaps in each data source. The briefing also includes compact seven-/thirty-day
trends and recorded experiments. See the [response guide](RESPONSES.md).

## 7. Add demand and performance when ready

Ask your agent to connect the relevant Apple account. It opens a private setup
window, checks access, and continues your request. See [the connection flow](CONNECTIONS.md).
For Terminal setup, use [Apple credential setup](CREDENTIALS.md). Once configured, query
`keyword_suggestions` before collecting a new ranking snapshot when you want its
cached popularity attached. Call `app_performance` to sync available reports.
If a ranking is already cached, a new popularity query does not rewrite that old
snapshot; the agent can use the newer suggestion response with its own date.

Then follow [the daily workflow](WORKFLOWS.md) or install the
[daily job prompt](../examples/hex-daily-job.md) in your host's scheduler. Installing
AppScope alone does not schedule anything.
