# AppScope documentation

AppScope gives a local MCP agent app and keyword evidence. The agent supplies
reasoning, scheduling, and the place where you read the report.

## Start here

| I want to… | Read |
|---|---|
| Get my first useful result without Apple credentials | [Getting started](GETTING-STARTED.md) |
| Install, connect my host, update, or uninstall | [Installation and connection](SETUP.md) |
| Add Apple popularity and performance data | [Apple credentials](CREDENTIALS.md) |
| Let the agent handle account setup and continuation | [Private connections](CONNECTIONS.md) |
| Refresh everything and recover interrupted jobs | [Refresh and health](REFRESH.md) |
| Compare weekly/monthly ranks and competitors | [Trends](TRENDS.md) |
| Record and compare ASO changes | [Experiments](EXPERIMENTS.md) |
| Run commands directly | [CLI and configuration reference](CLI.md) |
| Look up a tool's exact arguments | [MCP tool reference](TOOLS.md) |
| Understand a result, null value, or status | [Response guide](RESPONSES.md) |
| Plan keyword research and ASO experiments | [Agent workflows](WORKFLOWS.md) |
| Set up a daily job in my agent | [Daily job template](../examples/hex-daily-job.md) |
| Fix installation, authentication, or data problems | [Troubleshooting](TROUBLESHOOTING.md) |
| Learn the limits before relying on a report | [Data contract](DATA-CONTRACT.md) and [FAQ](FAQ.md) |
| Understand storage and contribute code | [Architecture](ARCHITECTURE.md) and [Contributing](../CONTRIBUTING.md) |
| Publish a release or Homebrew tap | [Release guide](RELEASING.md) |
| See what has actually been verified | [Validation record](VALIDATION.md) and [Changelog](../CHANGELOG.md) |

[Security and credential handling](../SECURITY.md) applies to every workflow.

## Current release status

These docs describe v0.0.3-alpha, including private Apple connection sessions and
28 MCP tools. Compiled downloads are listed on
[GitHub releases](https://github.com/MikesHorcrux/AppScope/releases). Alpha archives
are ad-hoc signed, not notarized. Homebrew remains pending. Public app search and
MCP have been exercised live; Apple account access and the complete host-led
connection workflow await live qualification.

The [tool catalog](../examples/tool-catalog.json) and
[example calls](../examples/tool-calls.json) are machine-readable. The
[agent reading index](llms.txt) points an agent at the smallest useful set of docs.
