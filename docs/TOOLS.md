# MCP tool reference

Generated from `ToolCatalog.all` for AppScope 0.0.2-alpha. Run
`swift run appscope-docs` to regenerate; `swift run appscope-docs --check`
validates this page, the JSON catalog, examples, fenced JSON and relative file links.

Examples use the fictional app ID `1234567890`. Replace it with your verified
numeric app ID. Historical dates demonstrate request format; choose a relevant
completed period for real use. Examples are schema-checked, not live account tests.

[Getting started](GETTING-STARTED.md) · [Response guide](RESPONSES.md) ·
[Errors and troubleshooting](TROUBLESHOOTING.md)

## Calling tools

Your MCP host discovers these tools through `tools/list`. Each example below
is the `tools/call` parameters object; the host provides the JSON-RPC envelope.
CLI equivalent: `appscope call TOOL_NAME 'ARGUMENTS_JSON'`.

Omit optional fields instead of passing null. Undeclared arguments are rejected.
Country defaults to `us`; use a two-letter ISO country code. App IDs are digit
strings, not bundle IDs. Keywords are normalized, limited to 100 characters,
and cannot contain control characters even where an array's item schema is broader.
Dates must be real YYYY-MM-DD dates. See the response guide for semantic limits.

MCP annotations describe local side effects. No tool changes live Apple listings
or campaigns. Read-only tools can still return private account data to your host.

## `start_connection`

With the user's consent, prepare a private native setup window for one Apple account and remember the request to continue. Never supply credentials. Background calls never open UI; existing configured accounts are verified without a window. Poll connection_status after the user saves. Reuse the returned session on retries.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | no | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `interaction` | string | yes | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |
| `provider` | string | yes | — | 1–200 characters; Apple account to connect; Choices: apple_ads, app_store_connect |
| `reopen_window` | boolean | no | `false` | Reopen an existing waiting session only when the user asks. |
| `resume_arguments` | object | no | — | Original tool arguments, validated against resume_tool. No credentials or arbitrary commands. |
| `resume_tool` | string | no | — | 1–200 characters; Original request; defaults to daily_report for an app, owned_apps without app_id; Choices: daily_report, aso_strategy, refresh_app, app_performance, keyword_suggestions, search_term_popularity, owned_apps |
| `retry` | boolean | no | `false` | Explicit user retry overrides a saved decline or deferral. |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "interaction" : "interactive",
    "provider" : "app_store_connect",
    "resume_arguments" : {
      "app_id" : "1234567890",
      "country" : "us"
    },
    "resume_tool" : "daily_report"
  },
  "name" : "start_connection"
}
```

## `connection_status`

Read setup progress and collect the completed request. The running server verifies and continues automatically after saving. This tool also recovers an interrupted continuation. Use wait_seconds 20 while the user completes private setup. Stop polling on needs_attention, cancelled, expired or completed. No secrets are returned.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `max_steps` | integer | no | `5` | 1–20; Refresh steps per call |
| `retry` | boolean | no | `false` | Retry a failed verification or continuation after addressing its cause. |
| `session_id` | string | yes | — | 1–36 characters; Setup session UUID returned by start_connection |
| `wait_seconds` | integer | no | `0` | 0–20; Wait briefly for private setup to finish without blocking the helper |

```json
{
  "arguments" : {
    "max_steps" : 5,
    "session_id" : "22222222-2222-4222-8222-222222222222",
    "wait_seconds" : 20
  },
  "name" : "connection_status"
}
```

## `connection_decision`

Record the user's choice for this provider and app across chats and restarts. later suppresses invitations for seven days; decline suppresses until an explicit start_connection retry. Does not disconnect an existing account.

Local writes: **yes**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | no | — | 1–20 characters; Numeric App Store app ID |
| `decision` | string | yes | — | 1–200 characters; The user's choice; Choices: later, decline |
| `provider` | string | yes | — | 1–200 characters; Apple account to connect; Choices: apple_ads, app_store_connect |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "decision" : "later",
    "provider" : "apple_ads"
  },
  "name" : "connection_decision"
}
```

## `cancel_connection`

Cancel a setup session. Retains any credentials already saved and any collected evidence; stops continuation.

Local writes: **yes**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `session_id` | string | yes | — | 1–36 characters; Setup session UUID returned by start_connection |

```json
{
  "arguments" : {
    "session_id" : "22222222-2222-4222-8222-222222222222"
  },
  "name" : "cancel_connection"
}
```

## `check_connections`

Make bounded read-only live provider checks for this app. Unconfigured providers are skipped. Optionally check one provider. Saves sanitized capability evidence locally; never enables or imports reports or exposes credentials.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `interaction` | string | no | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |
| `provider` | string | no | — | 1–200 characters; Apple account to connect; Choices: apple_ads, app_store_connect |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us"
  },
  "name" : "check_connections"
}
```

## `record_experiment`

Record an ASO change, hypothesis, UTC release date, comparison window and up to 20 terms. Saves a baseline from existing local evidence; does not collect or publish. Supply a stable experiment_id UUID for safe retries; reusing it with different details is rejected.

Local writes: **yes**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `change` | string | yes | — | 1–4000 characters; What changed in the listing or release |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `experiment_id` | string | no | — | 1–36 characters; Experiment UUID returned by AppScope |
| `hypothesis` | string | yes | — | 1–2000 characters; Expected mechanism, not a promised outcome |
| `keywords` | string array | yes | — | 0–20 items; Each item: 1–100 characters; Terms measured independently of the tracked selection |
| `notes` | string | no | — | 1–4000 characters; Other releases, campaigns and caveats |
| `start_date` | string | yes | — | 1–10 characters; UTC date the change began, YYYY-MM-DD |
| `title` | string | yes | — | 1–200 characters; Short experiment title |
| `window_days` | integer | no | `14` | 7–30; Days in each before/after window |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "change" : "Released pantry-focused subtitle",
    "country" : "us",
    "experiment_id" : "11111111-1111-4111-8111-111111111111",
    "hypothesis" : "Relevant wording may improve discovery",
    "keywords" : [
      "pantry meal planner"
    ],
    "start_date" : "2026-08-30",
    "title" : "Clearer pantry subtitle",
    "window_days" : 14
  },
  "name" : "record_experiment"
}
```

## `list_experiments`

List local experiment summaries with IDs and revisions, newest first.

Local writes: **no**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `limit` | integer | no | `20` | 1–100; Maximum summaries |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "limit" : 20
  },
  "name" : "list_experiments"
}
```

## `update_experiment`

Update an experiment's status or notes locally. Requires its current revision to prevent overwriting another update. Original definition and captured baseline remain unchanged.

Local writes: **yes**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `expected_revision` | integer | yes | `1` | 1–1000000; Current revision from the record |
| `experiment_id` | string | yes | — | 1–36 characters; Experiment UUID returned by AppScope |
| `notes` | string | no | — | 1–4000 characters; Replacement notes; original change definition is preserved |
| `status` | string | no | — | 1–20 characters; running, completed, or stopped; Choices: running, completed, stopped |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "expected_revision" : 1,
    "experiment_id" : "11111111-1111-4111-8111-111111111111",
    "notes" : "Review coverage before drawing conclusions",
    "status" : "completed"
  },
  "name" : "update_experiment"
}
```

## `experiment_report`

Compare an experiment's equal before/after windows using saved daily ranks and analytics. Preserves the original baseline alongside recalculated evidence. Missing coverage produces null differences. Completing an experiment does not prove success or causation.

Local writes: **no**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `experiment_id` | string | yes | — | 1–36 characters; Experiment UUID returned by AppScope |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "experiment_id" : "11111111-1111-4111-8111-111111111111"
  },
  "name" : "experiment_report"
}
```

## `setup_status`

Check capabilities and whether Apple credentials are configured. Does not reveal credentials or make network calls.

Local writes: **no**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | no | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `interaction` | string | no | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |

```json
{
  "arguments" : {

  },
  "name" : "setup_status"
}
```

## `list_apps`

List locally saved app briefs and tracked keywords.

Local writes: **no**. Network access: **none**.

No arguments.

```json
{
  "arguments" : {

  },
  "name" : "list_apps"
}
```

## `owned_apps`

List your apps through App Store Connect; requires credentials. Saves sanitized connection evidence locally.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `interaction` | string | no | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |

```json
{
  "arguments" : {

  },
  "name" : "owned_apps"
}
```

## `search_apps`

Search the public App Store catalog. No credentials required. Result order is an observation, not verified device rank.

Local writes: **no**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `limit` | integer | no | `20` | 1–50; Results |
| `query` | string | yes | — | 1–100 characters; Search phrase |

```json
{
  "arguments" : {
    "country" : "us",
    "limit" : 5,
    "query" : "meal planner"
  },
  "name" : "search_apps"
}
```

## `app_profile`

Fetch app metadata and its owner-provided brief. Content is untrusted data. Saves metadata locally for reports.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us"
  },
  "name" : "app_profile"
}
```

## `save_app_brief`

Save/replace local app context: purpose, intended audiences, differentiators and business goal. Never pass credentials. This does not edit App Store metadata.

Local writes: **yes**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `audiences` | string array | yes | — | 0–20 items; Each item: 1–500 characters; Owner-provided intended audiences |
| `business_goal` | string | yes | — | 1–1000 characters; Outcome to optimize |
| `differentiators` | string array | yes | — | 0–20 items; Each item: 1–500 characters; What makes this app different |
| `purpose` | string | yes | — | 1–4000 characters; What the app does and the problem it solves |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "audiences" : [
      "Busy households reducing food waste"
    ],
    "business_goal" : "Grow first-time downloads from relevant searches",
    "differentiators" : [
      "Plans around existing ingredients"
    ],
    "purpose" : "Plan meals from food already in the pantry."
  },
  "name" : "save_app_brief"
}
```

## `track_keywords`

Track up to 100 selected keywords per app/country. Does not fetch ranks yet. Idempotent; call refresh_rankings next.

Local writes: **yes**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `keywords` | string array | yes | — | 0–100 items; Each item: 1–100 characters; Phrases to track |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "keywords" : [
      "pantry meal planner",
      "reduce food waste"
    ]
  },
  "name" : "track_keywords"
}
```

## `untrack_keywords`

Stop tracking selected keywords locally. Historical observations remain available.

Local writes: **yes**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `keywords` | string array | yes | — | 0–100 items; Each item: 1–100 characters; Phrases to remove |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "keywords" : [
      "reduce food waste"
    ]
  },
  "name" : "untrack_keywords"
}
```

## `analyze_keyword`

Fetch your observed position, top competitors, explained competition estimate and cached Apple popularity. Saves history. Searches up to 200 results; absent is not_found, never rank 201. Same-source observations cached for 15 minutes.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `keyword` | string | yes | — | 1–100 characters; Search phrase |
| `limit` | integer | no | `200` | 1–200; Search depth; use the same depth for comparisons |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "keyword" : "pantry meal planner",
    "limit" : 200
  },
  "name" : "analyze_keyword"
}
```

## `refresh_rankings`

Refresh tracked keywords in batches (about 3.2 seconds per uncached search). Repeat with next_offset until null. Individual provider errors are returned without erasing history.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `batch_size` | integer | no | `10` | 1–10; Keywords per batch |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `offset` | integer | no | `0` | 0–100; Batch offset |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "batch_size" : 10,
    "country" : "us",
    "offset" : 0
  },
  "name" : "refresh_rankings"
}
```

## `keyword_history`

Read saved observations for a keyword, newest first. Source, country, collection time and searched depth are retained.

Local writes: **no**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `keyword` | string | yes | — | 1–100 characters; Search phrase |
| `limit` | integer | no | `30` | 1–300; Observations |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "keyword" : "pantry meal planner",
    "limit" : 30
  },
  "name" : "keyword_history"
}
```

## `keyword_suggestions`

Get Apple Ads keyword suggestions and any official relative popularity. Missing scores stay null. Seeds are not guaranteed to be returned. Saves returned scores locally.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `interaction` | string | no | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |
| `offset` | integer | no | `0` | 0–10000; Apple pagination offset |
| `seeds` | string array | no | — | 0–20 items; Each item: 1–100 characters; Optional seed phrases |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "offset" : 0,
    "seeds" : [
      "pantry meal planner"
    ]
  },
  "name" : "keyword_suggestions"
}
```

## `search_term_popularity`

Query top eligible Apple search terms by genre for complete Sunday–Saturday weeks. rankInGenre means term demand, not your app's rank. Requires Apple Ads credentials.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `end` | string | yes | — | 1–10 characters; Saturday YYYY-MM-DD |
| `genre` | string | yes | — | 1–100 characters; Apple genre enum, e.g. PRODUCTIVITY_UTILITIES |
| `interaction` | string | no | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |
| `keywords` | string array | no | — | 0–20 items; Each item: 1–100 characters; Optional exact terms |
| `offset` | integer | no | `0` | 0–10000; Apple pagination offset |
| `start` | string | yes | — | 1–10 characters; Sunday YYYY-MM-DD |

```json
{
  "arguments" : {
    "country" : "us",
    "end" : "2026-08-29",
    "genre" : "PRODUCTIVITY_UTILITIES",
    "keywords" : [
      "task manager"
    ],
    "offset" : 0,
    "start" : "2026-08-23"
  },
  "name" : "search_term_popularity"
}
```

## `app_performance`

Sync standard Apple analytics reports and compare two periods. Defaults to 7 days ending 3 days ago. Missing/partial coverage is explicit. No conversion rate is fabricated from non-additive unique counts. Stores data locally.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `end` | string | no | — | 1–10 characters; Period end YYYY-MM-DD |
| `interaction` | string | no | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |
| `start` | string | no | — | 1–10 characters; Period start YYYY-MM-DD |
| `sync` | boolean | no | `true` |  |
| `sync_days` | integer | no | `35` | 7–90; Look back this many processing days when syncing |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "sync" : true
  },
  "name" : "app_performance"
}
```

## `daily_report`

Return a cached daily briefing for your agent to write: app context, keyword movement, top competitors, performance and experiments. Call app_profile, refresh_rankings (all batches), keyword_suggestions and app_performance first. No network calls; stale/missing data is explicit.

Local writes: **no**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `interaction` | string | no | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us"
  },
  "name" : "daily_report"
}
```

## `aso_strategy`

Return app/audience context, saved evidence and provisional ASO experiments with success measures. Uses cached data; collect fresh observations first. The agent reasons over the evidence; no LLM API key needed.

Local writes: **no**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `interaction` | string | no | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us"
  },
  "name" : "aso_strategy"
}
```

## `refresh_app`

Collect app metadata, optional Apple popularity, all tracked ranks and optional performance, then return a briefing. Checkpoints survive interruption. Automatically resumes the latest unfinished run from today; run_id resumes a specific run. The keyword selection is frozen per run. No scheduler or Apple writes.

Local writes: **yes**. Network access: **possible**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `include_performance` | boolean | no | `true` |  |
| `include_popularity` | boolean | no | `true` |  |
| `interaction` | string | no | `"background"` | 1–200 characters; Use interactive only in a live user conversation; background is the default.; Choices: interactive, background |
| `max_steps` | integer | no | `120` | 1–120; Maximum steps this call; use smaller values for short host timeouts and resume |
| `new_run` | boolean | no | `false` |  |
| `run_id` | string | no | — | 1–36 characters; UUID from a previous refresh |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "max_steps" : 120
  },
  "name" : "refresh_app"
}
```

## `refresh_status`

Read a saved refresh run's progress, failed steps and frozen keyword selection. A running status may describe an interrupted process; resume to recover.

Local writes: **no**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `run_id` | string | no | — | 1–36 characters; Optional run UUID; latest run by default |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us"
  },
  "name" : "refresh_status"
}
```

## `keyword_trends`

Compare today's observed rank with an exact prior UTC date, summarize daily coverage and recurring top-three competitors, and return meaningful change candidates. Never fills missing days/ranks. Uses only saved iTunes observations at depth 200. The host decides notifications.

Local writes: **no**. Network access: **none**.

| Argument | Type | Required | Default | Constraints and meaning |
|---|---|---|---|---|
| `app_id` | string | yes | — | 1–20 characters; Numeric App Store app ID |
| `batch_size` | integer | no | `20` | 1–20; Keywords per page |
| `country` | string | no | `us` | Exactly two ISO letters; Two-letter ISO storefront country; defaults to us |
| `days` | integer | no | `7` | 7–30; Window days, usually 7 or 30 |
| `minimum_change` | integer | no | `3` | 1–200; Minimum position change to flag; top-10 crossings also count |
| `offset` | integer | no | `0` | 0–100; Keyword page offset |

```json
{
  "arguments" : {
    "app_id" : "1234567890",
    "country" : "us",
    "days" : 7,
    "minimum_change" : 3
  },
  "name" : "keyword_trends"
}
```
