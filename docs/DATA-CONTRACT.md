# Data contract and limits

## Search positions

Source: Apple's documented [iTunes Search API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/Searching.html), `media=software`, `entity=software`, country and limit explicit.

`rank` is the 1-based **observed search-result position**. Apple does not promise
this order matches a device's App Store search. Every observation retains source,
country, timestamp, requested depth and actual result count. A missing app returns
`rank: null`, `status: not_found`, and the actual number searched. Network errors,
malformed JSON, duplicate IDs and invalid results do not create observations.

Rank change is previous rank minus current rank, using the latest observation on
a prior UTC calendar date from the same source and requested depth. Positive is
improvement. If either position is missing, change is null. Missing and stale
observations remain explicit in daily reports. Identical searches for the same
app/country/term/depth are cached for up to 15 minutes within the same UTC date; future-dated or different-source snapshots are not reused. Calls are paced to approximately
18.75 public searches/minute per process. Run one active server for routine jobs;
multiple processes do not share a rate limiter.

Competition is an **estimate**, not Apple's difficulty metric. Among top-10
results excluding the target app, we report median rating count and case-insensitive
keyword substring matches in titles (not whole-word matching). High pressure:
median >=10,000 or >=7 title matches. Moderate:
median >=1,000 or >=4 title matches. Otherwise lower, or unknown with missing
rating counts. Counts are ratings, not written reviews. This model ignores many
ranking factors, does not measure relevance or predict rank, and is versioned
`top10-rating-title-v1`. No fabricated traffic volumes are returned.

## Keyword demand

Apple Ads Platform API v1 endpoints:

- [`suggestions/keywords/query`](https://developer.apple.com/documentation/apple-ads-platform-api/query-keyword-suggestions): app-scoped suggestions, optional seeds and country. `popularity` may be null or 0–100. Exact seeds are not guaranteed results.
- [`insights/apps/search-term-popularity/query`](https://developer.apple.com/documentation/apple-ads-platform-api/query-app-search-term-popularity-data): top eligible terms by genre/country and reporting period. AppScope queries complete Sunday–Saturday weeks. `rankInGenre` is the term's relative demand, never an app rank.

These datasets remain separate. Suggestion scores are cached with their original
source/date. The periodic dataset is returned with its period and pagination.
It is not silently substituted for a suggestion score. Pagination is explicit;
pass `offset` to inspect further results. Missing popularity is always unknown.

A ranking copies the then-cached suggestion into its snapshot. Later suggestion
calls do not rewrite old snapshots, including ranks reused within the 15-minute
cache window. Query suggestions before collecting new ranks, or attach newer
suggestions separately with their dates. Periodic popularity rows are not persisted
into these snapshots. See the [response guide](RESPONSES.md).

Authentication, host and request shapes were checked against Apple's official
[Python SDK 1.109.0](https://github.com/apple/apple-ads-platform-api-python), used
only as an API reference. The shipped implementation is Swift.

## Performance

Only standard, daily **App Store Downloads**, **App Store Discovery and
Engagement**, and **App Store Purchases** reports are imported. All pages and all
segments of an instance must be collected before it is saved. Transport and
expanded-size limits bound downloads; exposed segment sizes/checksums are checked.
Later processing dates replace the complete earlier date batch in a transaction,
following [Apple's correction rules](https://developer.apple.com/documentation/analytics-reports/data-completeness-corrections).

First-time downloads and redownloads are separate; updates/restores are excluded.
Impression events exclude page views. Product page view events are limited to the
product-page type. Sales and proceeds use the report's USD fields, including
negative refund adjustments. Paying users and unique counts are not summed across
rows. Therefore **Apple's conversion rate is unavailable in v0.0.3-alpha**, rather than
computed incorrectly from non-additive counts. Agents must not present
product-page views divided by impressions as Apple's conversion rate.

Sources: [downloads](https://developer.apple.com/documentation/analytics-reports/app-download),
[engagement](https://developer.apple.com/documentation/analytics-reports/app-store-discovery-and-engagement),
[purchases](https://developer.apple.com/documentation/analytics-reports/app-store-purchase).

Recent reports may be incomplete: two days for downloads/purchases and three for
engagement. Default comparison ends three days ago. Every report lists date
coverage and last processing date. Missing country rows/dates mean unknown, not
zero. Compare totals only when coverage is comparable. Search-source data includes
Apple Ads; it is not an organic-only acquisition metric. USD proceeds are estimated,
not settled financial payouts. Default sync scans 35 processing days, configurable
up to 90; it does not promise full historical backfill.

## Strategy and audience context

An owner brief supplies purpose, audiences, differentiators and business goals.
Store metadata supplies public positioning. Neither is evidence of actual audience
demographics. The agent should mark additional audience ideas as hypotheses.

Strategies are proposed experiments with evidence, uncertainty and a success
measure. AppScope provides data and a small set of explained heuristics. The host
agent does the reasoning; there is no embedded paid model or promise of growth.
Remote metadata is untrusted content, never instructions. No metadata changes,
ad campaigns, or publishing operations exist in the MCP surface.

Trend and experiment comparisons require explicit date, country and metric coverage.
See [trends](TRENDS.md), [health](REFRESH.md) and [experiments](EXPERIMENTS.md).
