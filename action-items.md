# Action items deferred from cleanup PR

These items were called out in `hardening-checklist.md` as candidates to drop
from the analyzer-12 cleanup PR. After rebasing on `origin/master`, neither
needs follow-up.

## SDK-floor downgrade — nothing to do

The fork's branch base predated upstream's SDK-floor bump from `>=3.11.0` to
`>=3.12.0-0`. There was no commit that explicitly downgraded the SDK floor;
the difference was an artifact of how stale the fork's branch base was.

`git pull --rebase origin master` resolved this automatically — the workspace
now uses upstream's `>=3.12.0-0` floor across all pubspecs. No additional
work needed.

## Windows-CI removal — nothing to do

Upstream already removed `.github/workflows/windows.yml` (referenced in the
hardening checklist as commits `175fb719`, `329e596f`, `c5533072`,
`aea97343`, `434d8352`). During the rebase on `origin/master`, git correctly
identified the local `remove windows ci` commit as a duplicate and dropped
it with `patch contents already upstream`. No additional work needed.

## Streaming-codec test rewrite — already upstream

Not in the original drop list, but worth recording: the rebase also
deduplicated the streaming-codec test rewrite in
`packages/core/test/http/body_encoder_streaming_test.dart` and the codec
type tightening in `packages/core/lib/src/http/request.dart`. Both are
already on `origin/master`. The cleanup PR therefore landed only the
analyzer dependency bump; the previously-described streaming-codec content
needs no separate PR.
