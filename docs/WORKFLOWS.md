# Agent workflows

AppScope provides evidence. The agent supplies research judgment and scheduling.
All examples describe proposed work, not permission to publish metadata or run ads.

## Connect missing accounts during a conversation

Use `interaction: interactive` on a relevant request. Read `onboarding`, present
one invitation when `should_invite` is true, and record a later/decline response.
With consent, start the private setup session and keep its original request.
AppScope reloads saved credentials and continues it; the agent retrieves the result.
See [the connection flow](CONNECTIONS.md) and [copyable host prompt](../examples/interactive-setup.md).

## Understand the app and propose audiences

Call `app_profile` and read the description, genre, positioning and owner brief.
Ask the owner for missing purpose, business goal, audiences and differentiators;
store an agreed brief with `save_app_brief`. Do not infer analytics or real user
characteristics from marketing copy.

For a pantry meal planner, useful candidate audiences might be busy households,
people trying to reduce food waste, or cooks who shop infrequently. These are
**hypotheses** grounded in a feature/use case. The next step is testing relevant
search terms and messaging, not claiming those people already use the app.

Suggested prompt:

> Explain the app in one sentence. Propose three plausible audience/use-case
> combinations. For each, cite a feature or owner statement, state what remains
> uncertain, and suggest a few terms people might search. Do not invent audience
> demographics or search volumes.

## Research an initial keyword set

1. Build seeds from the app's core problem, use cases, intended audiences and
   language used by the owner. Distinguish branded terms from generic ones.
2. If Apple Ads is configured, call `keyword_suggestions`. Keep official scores,
   missing values, country, observation date and pagination visible. Otherwise
   proceed with public search and label demand as unknown.
3. Call `analyze_keyword` for relevant candidates. Inspect your position, top
   competitors and their titles, ratings and rating counts. Search API order is
   not a verified device rank.
4. Select a small relevant set with `track_keywords`, then establish a baseline
   using `refresh_rankings`. Keep tracked selections stable during batch pagination.
5. Return a shortlist with relevance, demand evidence, observed competition,
   current position and uncertainties. Do not rank opportunities using a fabricated
   popularity score or assume an absent app/term is an easy opportunity.

AppScope does not offer exhaustive reverse lookup of all competitor keywords.
An agent can generate candidates from competitor titles/descriptions and then
check them; it must not present those candidates as a known competitor keyword list.

## Choose a measurable ASO experiment

Use `aso_strategy` or `daily_report` after collecting data. They return the same
cached briefing in v0.0.3-alpha. The agent can refine its provisional suggestions.

A useful experiment includes the affected app/country, target term or audience,
current evidence and dates, a proposed change, the expected mechanism, a baseline,
and a success measure. For example:

> **Hypothesis:** clearer pantry-focused wording may attract more relevant search
> traffic. **Evidence:** the feature exists in the owner brief; the term has a
> recorded search observation; competing titles explicitly mention pantry use.
> **Proposed change:** draft a relevant subtitle variant for owner review.
> **Measure:** compare the tracked position and available first-time-download data
> for equal 14-day windows after and before release, documenting other marketing,
> releases, seasonality and coverage gaps.

This does not prove the proposed wording will improve ranking. Apple account
metrics are country-level reports, not organic downloads attributed to each keyword.
AppScope neither edits metadata nor validates every App Store metadata limit.
The owner must review listing changes and Apple's current rules before publishing.

## Daily report

Recommended workflow for a host-owned scheduled job:

1. Call `refresh_app` with `interaction: background`. It collects sources in order and returns `run` plus `report`.
   For short host timeouts, use `max_steps: 3` and resume the returned `run_id` while
   paused. Retry failed steps at most once per job, then report unresolved failures.
2. Inspect `report.health`, each source date and the run's skipped/failed steps.
   A completed collection run does not imply complete provider data.
3. Review compact 7/30-day trends and change candidates. Request paginated
   `keyword_trends` for detailed competitor evidence when relevant. Daily movement
   is also visible in each ranking's previous-observation fields.
4. Review running experiment summaries; call `experiment_report` for those whose
   comparison windows are ready. Keep original baselines, corrections and coverage
   visible. See [experiment tracking](EXPERIMENTS.md).
5. Write the narrative and save it in the host's normal job history. Choose at
   most three actions supported by the app brief and evidence.

The separate collection tools remain available for targeted research. Use
`check_connections` after setup or to diagnose access; repeating it on every
healthy daily job adds requests without collecting useful history.

Use the [copyable daily-job template](../examples/hex-daily-job.md). Configure the
schedule in Hex when its scheduler is ready, or in another host. AppScope does not
run after the host stops unless that host relaunches it for a job.

A first day has no historical comparison. A failed or missed day remains a gap;
the next comparison may be against an earlier date. Report the interval honestly.
Respect the user's notification preference rather than sending the same report
on every unchanged run.

## Multiple apps and countries

Repeat the workflow for each verified app ID and country. Briefs are app-wide;
keyword tracking, ranking snapshots and cached performance are country-specific.
The default is `us`, not the computer's region. There is no `country: all` option
in the v0.0.3-alpha MCP tools. Run separate country calls and keep their evidence separate.

Prefer one active server and one job at a time. SQLite supports multiple local
processes, but request pacing and Apple Ads token caching are per process.
There is no global scheduler, global rate limiter, or automatic data retention.
