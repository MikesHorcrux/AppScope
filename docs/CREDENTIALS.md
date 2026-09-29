# Connect Apple data

Public search and ranking history need no credentials. Add either provider
independently. AppScope uses your accounts directly; you do not send keys to an
AppScope service or paste them into an agent conversation.

| Provider | Adds | Routine access |
|---|---|---|
| Apple Ads | Keyword suggestions and available relative popularity | API Account Read Only |
| App Store Connect | Owned-app listing and available standard analytics | Team API key; Sales and Reports for report downloads |

The Apple keys are separate. AppScope v0.2 supports App Store Connect **team keys**
with an issuer ID, not the distinct individual-key authentication flow.

## Connect through your agent

Ask your agent to connect the account needed for your report. AppScope opens a
private setup window with the correct Apple account link, a key file picker, and
ID fields. The agent never receives key bytes. The running server checks access
and continues the saved request after you save. [Connection flow and host contract](CONNECTIONS.md).

## Terminal fallback

Run these in Terminal, not through an MCP tool or a piped agent prompt:

```sh
appscope configure apple-ads
appscope configure app-store-connect
```

Configure only the provider you need. The guided flow asks for identifiers and an
existing private-key **path**, never private-key bytes. Return preserves an
existing field; Ctrl-D cancels without saving. It checks key format/permissions,
preserves the other provider, and atomically saves a 0600 config file. Credentials
reload on the next tool call. Manual editing remains supported below.

If you need an Apple Ads key pair before creating its API client:

```sh
appscope keygen apple-ads
```

This creates `apple-ads-private.p8` and `apple-ads-public.pem` in your data
directory, prints only the public key and paths, and refuses to replace existing
key files. Give Apple the public key. App Store Connect keys must be issued by
Apple through its account portal; this command does not create those.

After configuration, use your verified app ID for an optional read-only check:

```sh
appscope doctor --live 1234567890
```

The ID is fictional. `check_connections` exposes the same check through MCP with
an optional country. It reports each provider independently, skips unconfigured
providers and withholds tokens/raw provider details. It checks app access and
ongoing report-request status, not successful report downloads or reconciled
analytics totals. A partial result can still exit successfully; inspect `checks`.

## Prepare the private configuration

Run `appscope setup` and note the printed configuration path. Open that file in
a local editor. Its initial contents are:

```json
{
  "apple_ads": {
    "client_id": "",
    "team_id": "",
    "key_id": "",
    "ad_account_id": "",
    "private_key_path": ""
  },
  "app_store_connect": {
    "issuer_id": "",
    "key_id": "",
    "private_key_path": ""
  }
}
```

Leave an unused provider empty. Keep IDs as strings, including the ad account ID.
`private_key_path` is a local PEM file path, never the key's contents. Do not add
comments or trailing commas to JSON. Both config and key files must have mode 0600.

```sh
chmod 600 "$HOME/Library/Application Support/AppScope/config.json"
chmod 600 /absolute/path/to/your-private-key.p8
```

The second path is a placeholder. Keep keys outside the checkout; a private
AppScope directory is a suitable location. A `.p8` or `.pem` extension does not
establish validity: the contents must be a readable, unencrypted P-256 PEM key.
AppScope reloads local configuration and key changes before the next tool call. It does not load `.env` files.

## Apple Ads

1. An Apple Ads Account Admin assigns an API user the API Account Read Only role
   under Account Settings → User Management.
2. That API user signs in and opens Account Settings → API to create a client.
   Generate the key pair locally and provide Apple only the public key as directed
   in Apple's client setup. The private key stays on your Mac.
3. Enter Apple's client ID, team ID, key ID, and the **Platform API ad account ID**
   into `apple_ads`, plus the private-key path. Do not assume the legacy org ID
   is interchangeable with the Platform account ID.

Follow [Apple's account/API setup](https://ads.apple.com/app-store/help/campaigns/0022-use-the-apple-ads-platform-api)
for the current account screens and client creation requirements. AppScope does
not include Apple account administration; use `keygen apple-ads` for local keys.

Validate with a small research call for your actual app:

```sh
appscope call keyword_suggestions '{"app_id":"1234567890","country":"us","seeds":["relevant seed term"]}'
```

Replace the fictional ID and seed. A successful response proves this account can
make this request; it does not prove every term has a popularity score. The MCP
surface has no campaign creation, budget modification, or ad-spend operation.

## App Store Connect

An Account Holder requests API access if the account does not already have it.
An Account Holder or Admin then creates a **Team Key** under Users and Access →
Integrations → App Store Connect API. Select the appropriate role and store the
downloaded private key securely. Enter the issuer ID, key ID and key path in
`app_store_connect`. Keys belong to a team; do not assume they are restricted to
only the app you are tracking. See [Apple's key setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/).

### Enable reports once per app

Apple requires an Admin role to create analytics report requests. Temporarily
configure an Admin team key locally and run:

```sh
appscope enable-reports 1234567890 --confirm
```

Replace the fictional ID. This is the one CLI command that creates an Apple-side
resource: an ongoing report request. It is not exposed as an MCP tool. An existing
active ongoing request returns `already_enabled`. Restore a Sales and Reports
key for routine downloads; AppScope reloads it on the next call. Initial reports
may take 24–48 hours. See [Apple's report roles and lifecycle](https://developer.apple.com/documentation/appstoreconnectapi/downloading-analytics-reports).

### Validate access and data separately

```sh
appscope call owned_apps '{}'
appscope call app_performance '{"app_id":"1234567890","country":"us","sync":true}'
```

Inspect `sync`, `current.coverage`, and `current.metrics`. `sync.status: synced`
does not guarantee a complete requested date range. Empty or absent report data
is not zero performance. A failed sync can return usable older cached data with
its dates. [Response details](RESPONSES.md) explain how to interpret both.

## Rotation and recovery

Keep a backup of required key files using your normal secure storage. If a key
is revoked or replaced, update it in the private window or local configuration.
Running AppScope processes reload the change and discard cached Ads tokens. Revoke compromised keys in the corresponding Apple account. Removing
an AppScope binary or configuration file does not revoke Apple credentials.

Never post config, private keys, raw authenticated responses or the database in
a public issue. A sanitized error code and tool name are usually enough to begin
troubleshooting. `doctor` indicates configuration presence only; it does not
read every key or authenticate with Apple. See [security](../SECURITY.md).
