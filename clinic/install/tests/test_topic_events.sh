#!/usr/bin/env bash
# topic_events: a topic that does not exist yet (a freshly seeded node has
# written nothing) has 0 events -- it must not end a set -e task.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
run(){ # FAKE_RC FAKE_OUT : topic_events under set -euo pipefail with a fake runtime
  bash -c "set -euo pipefail; . '${HERE}/../lib.sh'; ct(){ printf '%s\n' '$2'; return $1; }; n=\"\$(topic_events some.topic)\"; echo \"n=\$n\"" 2>/dev/null
}
out="$(run 1 '')"; [ "$out" = "n=0" ] && ok_ "a missing topic counts 0 and the task goes on" || bad "missing topic: '$out'"
out="$(run 0 'some.topic:0:42')"; [ "$out" = "n=42" ] && ok_ "an existing topic counts its end offset" || bad "existing topic: '$out'"
grep -q 'kafka-get-offsets --bootstrap-server localhost:9092' "${HERE}/../tasks/090-local-sync.sh" && bad "090 still counts local events itself" || ok_ "090 counts through topic_events"
exit $((fails > 0))
