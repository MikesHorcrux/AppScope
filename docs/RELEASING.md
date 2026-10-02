# Publishing a release

This guide is for maintainers. Building locally or running CI does not publish
a repository, release or Homebrew tap. There is no Python/npm package to publish.
Alpha archives use an ad-hoc development signature by default; see
[validation status](VALIDATION.md).

## 1. Prepare a reviewable source release

- Choose the real public GitHub owner/repository and confirm it is the intended
  publication destination. The current public repository is
  `MikesHorcrux/AppScope`; alpha downloads exist, while Homebrew remains pending.
- Review staged/tracked files for secrets, private app data and machine-specific
  paths. Never publish config, PEM keys, databases, raw report exports or `work/`.
- Keep `LICENSE`, dependency pins, security guidance and the handbook with the
  source. Enable GitHub's private vulnerability reporting when available, and
  update `SECURITY.md` with that actual reporting route.
- Update `Version.swift`, changelog, version examples and the archive version marker together. Document schema changes and migration/
  downgrade limits before shipping them. Preview status does not excuse silent
  metric or output-contract changes.
- Replace the current local-preview status in the README, handbook, FAQ and
  validation record only after the corresponding publication/qualification is
  complete. Add verified clone, release and Homebrew URLs at that point.

## 2. Validate the candidate

From the source root with a supported Xcode toolchain:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift run appscope-docs --check
git diff --check
./scripts/package-macos.sh
```

Adjust `DEVELOPER_DIR` if Xcode is installed elsewhere. The package script also
runs the documentation check. Every archive includes `VERSION` and `BUILD.json` (source revision and whether
uncommitted changes were present). Build from the intended clean commit. Staging
is temporary and recreated for each build. It builds both `arm64` and `x86_64`, creates a
single executable, includes the handbook/examples/licenses and produces:

```text
dist/appscope-0.0.3-alpha-macos-universal.tar.gz
dist/appscope-0.0.3-alpha-macos-universal.tar.gz.sha256
```

Names follow the executable's version. Run `shasum -a 256 -c` on the checksum file
from its directory. Verify archive contents and first install/update using a
temporary `APPSCOPE_PREFIX`; use a separate private data directory for setup.
Check that updates preserve existing config/history. Run the MCP integration
test against the extracted executable using `APPSCOPE_TEST_BINARY`.

Both architecture slices must declare macOS 14 as their minimum. A successful
universal build is not proof of runtime behavior on Intel or a clean macOS 14
machine. Record which systems actually ran the executable and keep untested
platforms explicit in the release notes.

## 3. Sign and qualify the download

The default package has an **ad-hoc development signature**. For a public binary,
use an existing Developer ID Application identity in the local Keychain and an
existing `notarytool` credential profile. Set `APPSCOPE_SIGNING_IDENTITY` and
`APPSCOPE_NOTARY_PROFILE` to those existing local references, then rerun
`./scripts/package-macos.sh`.

These values reference local signing setup, not private key contents. The script
signs with hardened runtime, submits a ZIP containing the same executable for
notarization and waits for Apple's result. **Read and verify that the returned
notarization status is Accepted.** Script completion alone is insufficient
qualification. If the result is invalid or uncertain, inspect the submission
with `xcrun notarytool info`/`log` using its submission ID and resolve it before
publishing a notarized claim. The package script now rejects every status other
than Accepted before creating the archive. Set `APPSCOPE_REQUIRE_NOTARIZATION=1`
to require signing/profile prerequisites from the start. A pre-existing archive
from an earlier build is not evidence that a failed new build succeeded.

The bare CLI cannot be stapled; Gatekeeper checks its ticket online. Check the
Developer ID signature and exercise the actual downloaded archive on a clean Mac
with ordinary quarantine/Gatekeeper behavior. Do not bypass those checks for the
release smoke test. Never label an ad-hoc build signed by Developer ID or notarized.

Apple Ads/App Store Connect API credentials are unrelated to binary signing and
must not be supplied to builds or CI. The included workflows create development
artifacts only; they do not use signing secrets or upload a public release.

## 4. Publish matching source and artifacts

Publish the reviewed source to the chosen repository, tag the verified commit
as `v0.0.3-alpha` (or its actual version), and create a GitHub Release for that tag.
Upload the exact archive and checksum verified above. Signing/rebuilding changes
the artifact; if either happens, re-check the new archive and checksum together.

Release notes should state minimum macOS, architectures, installation commands,
signing/notarization status, changes, data-format compatibility and known limits.
Download the uploaded assets back from the public release and verify their
checksum/install. Update public-facing status/links without claiming unavailable
account or device qualification.

## 5. Publish a Homebrew tap

Homebrew's convention is an owner/repository such as `OWNER/homebrew-tap` with a
`Formula` directory; `OWNER` here is a placeholder. Follow the official
[tap guide](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).

After the release URL exists, run the following **from the AppScope checkout**.
Replace `OWNER` and `/absolute/path/to/homebrew-tap` with the actual destination;
its `Formula` directory must already exist:

```sh
./scripts/homebrew-formula.sh https://github.com/OWNER/AppScope/releases/download/v0.0.3-alpha/appscope-0.0.3-alpha-macos-universal.tar.gz dist/appscope-0.0.3-alpha-macos-universal.tar.gz > /absolute/path/to/homebrew-tap/Formula/appscope.rb
```

The generator checks the versioned filename against the archive's `VERSION` marker
and uses its SHA-256 and actual version for the formula test. Review the URL, homepage,
checksum, minimum macOS and version test. The formula downloads the universal
binary, so end users need no compiler. Test a real `brew install OWNER/tap/appscope`,
`brew test OWNER/tap/appscope` and upgrade from the previous version as applicable.
Commit/publish the tap and only then advertise that exact install command.

## Live data qualification

Fixtures establish implementation behavior; account access remains a separate
check. Before describing authenticated integration as live-qualified, record a
successful Ads keyword-suggestion request for an accessible app, a completed
analytics import, and reconciliation of dates/coverage/totals against App Store
Connect. Keep the private responses outside Git; publish only sanitized findings.

Validate API search ordering against physical-device storefront observations
before offering a device-rank accuracy claim. Until then, retain the explicit
observed-position wording in product docs and releases. Initial reports, privacy
gaps and missing popularity remain possible even after a successful live call.
