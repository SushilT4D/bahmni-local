#!/usr/bin/env bash
# No connector in this fleet uses a schema registry (every converter is
# JsonConverter or ByteArrayConverter), so none runs: no service, no image
# pin, no healthcheck to wait for, nothing that names one.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$(cd "${HERE}/../../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
conv="$(cd "$R" && git grep -hoE '(CONNECT_(INTERNAL_)?(KEY|VALUE)_CONVERTER|(key|value)\.converter)"?[[:space:]]*[:=][[:space:]]*"?[A-Za-z.]+' -- clinic hub sync 2>/dev/null | sed -E 's/.*[:=][[:space:]]*"?//' | sort -u)"
odd="$(printf '%s\n' "$conv" | grep -vE '^$|JsonConverter$|ByteArrayConverter$' || true)"
[ -n "$conv" ] && [ -z "$odd" ] && ok_ "every converter is JSON or ByteArray" || bad "a converter that may need a registry: ${odd:-<none found at all>}"
left="$(cd "$R" && git grep -il 'schema-registry\|schema_registry\|SCHEMAREGISTRY' -- clinic hub sync/versions.env sync/tests ':!*.md' ':!clinic/install/tests/test_no_schema_registry.sh' ':!clinic/install/tests/test_no_old_kafka.sh' ':!hub/install/tests/test_compose.sh' 2>/dev/null)"
[ -z "$left" ] && ok_ "no file under clinic/, hub/ or the fleet pins names a schema registry" || bad "still named in: $(printf '%s' "$left" | tr '\n' ' ')"
exit $((fails > 0))
