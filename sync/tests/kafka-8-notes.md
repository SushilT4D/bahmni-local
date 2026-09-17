# Kafka 8.3.2 (Apache Kafka 4.3.x) upgrade notes — what applies to us

Task 3 of `2026-09-17-fleet-on-staging-versions`. `sync/versions.env` pins
`KAFKA_IMAGE=confluentinc/cp-kafka:8.3.2`, `MM2_IMAGE=confluentinc/cp-kafka-connect:8.3.2`,
`SCHEMA_REGISTRY_IMAGE=confluentinc/cp-schema-registry:8.3.2` (all Apache Kafka
4.3.x, KRaft only, Java 21 in the image), against `DEBEZIUM_CONNECT_IMAGE=quay.io/debezium/connect:3.6.2.Final`.

## Upstream upgrade-notes fetch: could not be completed

Per the spec (§10.5) and this task's ruling 5, tried in order on 2026-09-17:

1. `https://kafka.apache.org/documentation/#upgrade` — WebFetch returned only
   the page's navigation/redirect shell; no upgrade-notes text.
2. `https://kafka.apache.org/43/documentation.html` — same: WebFetch's
   markdown conversion returned only navigation/menu content, no upgrade
   section body.
3. `https://raw.githubusercontent.com/apache/kafka/trunk/docs/upgrade.html` —
   HTTP 404 (matches the spec's note that the controller could not fetch this
   earlier either).
4. (Extra attempt, not in the ruling's list) `https://raw.githubusercontent.com/apache/kafka/4.3/docs/upgrade.html` — HTTP 404 (no `4.3` tag/branch at that path).

None of the four returned the actual upgrade-notes body. **The evidence for
this task is the live boot + MM2 proof below, not the upstream doc**, per the
ruling. The items below are what we independently confirmed by running the
real 8.3.2 images against our own compose files (not transcribed from
upstream text) plus the two "known already" items the ruling names.

## What we verified directly (config-name-exact, with the boot evidence)

- **ZooKeeper removed; KRaft only.** Confirmed: `clinic/docker-compose.yml`'s
  `kafka-controller`/`kafka` services already run pure KRaft
  (`KAFKA_PROCESS_ROLES=controller` / `broker`, `KAFKA_CONTROLLER_QUORUM_VOTERS`,
  no `KAFKA_ZOOKEEPER_CONNECT` anywhere), and the 8.3.2 image booted and
  finalized `metadata.version=4.3-IV0` with no ZK dependency (`kafka-features
  --bootstrap-server kafka:29092 describe`, see report). No config change
  needed here; noted only to confirm the "known already" item.
- **Java floor.** The `confluentinc/cp-kafka:8.3.2` and
  `confluentinc/cp-schema-registry:8.3.2` images both ship Java 21
  (`quay.io/debezium/connect:3.6.2.Final` ships Java 17+, already pinned by
  Task 2). No broker/Connect config change needed; both floors are already
  met by the pinned images.
- **`connect.internal.key.converter` / `connect.internal.value.converter`
  were removed from Kafka Connect (long before 4.0, KIP-...; these keys have
  been ignored since Connect started hardcoding `JsonConverter` with
  `schemas.enable=false` for its internal topics).** The clinic compose's
  `kafka-connect` service still set `CONNECT_INTERNAL_KEY_CONVERTER` /
  `CONNECT_INTERNAL_VALUE_CONVERTER` (was `clinic/docker-compose.yml:409-410`)
  — dead, noise. **Deleted** in this change. Left `mirrormaker-connect`'s own
  copy of the same two keys alone (out of the brief's stated scope — that
  service's dead keys are a candidate follow-up, not fixed here).

## Config the 8.3.2 broker/Connect rejected at boot (found by booting, not by doc text) — and the fix applied

1. **`kafka-controller` (KRaft controller-only node): `advertised.listeners`
   must not be empty.**
   First boot attempt (no `KAFKA_ADVERTISED_LISTENERS` set at all, matching
   the working 7.6 config) failed:
   ```
   Exception in thread "main" org.apache.kafka.common.config.ConfigException:
   Configuration 'advertised.listeners' must not be empty. Valid values
   include: any non-empty value
   ```
   thrown from `kafka.tools.StorageTool` during the image's preflight
   `kafka-storage format` step. Root cause (confirmed by extracting and
   running `/etc/confluent/docker/configure` from the `confluentinc/cp-kafka:8.3.2`
   image standalone): the image bakes `ENV KAFKA_ADVERTISED_LISTENERS=""`
   (present, empty — not unset). `configure` explicitly **refuses** a
   non-empty `KAFKA_ADVERTISED_LISTENERS` on a controller-only node
   (`KAFKA_PROCESS_ROLES == "controller"`) with "KAFKA_ADVERTISED_LISTENERS
   is not supported on a KRaft controller." — so setting it is not an option.
   But its `envToProps` template dump still emits the baked-in *empty* value
   as `advertised.listeners=` (key present, empty) into `kafka.properties`
   regardless of role, and AK 4.3's `StorageTool`/`AbstractKafkaConfig` now
   rejects that with the "must not be empty" `ConfigException` — 7.6/AK 3.6
   tolerated it. This is a real gap between the Confluent 8.3.2 packaging
   script and the underlying Apache Kafka 4.3 validation for a
   controller-only node; neither "set it" nor "leave it alone" works through
   the documented env-var surface.
   **Fix applied** (`clinic/docker-compose.yml`, `kafka-controller` service):
   override `command` to unset the var before exec'ing the real entrypoint,
   so it is truly absent (not empty) when the properties file is rendered:
   ```yaml
   command: ["/bin/bash", "-c", "unset KAFKA_ADVERTISED_LISTENERS; exec /etc/confluent/docker/run"]
   ```
   Verified directly: `docker run --entrypoint /etc/confluent/docker/configure`
   against the image with the var present-but-empty (fails, `advertised.listeners=`
   line present) vs. actually unset (`advertised.listeners` line absent
   entirely, `configure` exits 0) — then a full standalone boot with the
   `unset` wrapper reached normal controller startup (`Recorded new KRaft
   controller`) with no `ConfigException`.

2. **`confluentinc/cp-schema-registry:8.3.2` no longer ships `curl` or
   `wget`.** The clinic compose's `schema-registry` healthcheck
   (`test: ["CMD", "curl", "-f", "http://localhost:8081/subjects"]`, worked
   on 7.6.0) permanently failed:
   ```
   OCI runtime exec failed: exec failed: unable to start container process:
   exec: "curl": executable file not found in $PATH: unknown
   ```
   even though the app itself came up fine and answered 200 on `/subjects`
   the whole time (confirmed with `curl` from the host against the published
   port while the container sat "unhealthy"). Because `kafka-connect`
   `depends_on: schema-registry: condition: service_healthy`, this silently
   blocked `kafka-connect` — and therefore the whole sync profile — from ever
   starting on 8.3.2, with no error pointing at schema-registry itself. Same
   defect exists in `confluentinc/cp-kafka-connect:8.3.2` (used by
   `mirrormaker-connect`, which has no healthcheck defined so it wasn't hit
   here, but a future healthcheck added to that service would hit the same
   wall). `quay.io/debezium/connect:3.6.2.Final` (the `kafka-connect` service
   image) still ships `curl`, so `kafka-connect`'s own healthcheck needed no
   change.
   **Fix applied** (`clinic/docker-compose.yml`, `schema-registry`
   healthcheck): replaced the `curl` probe with a `bash`+`/dev/tcp` TCP-connect
   check (bash is present in the image; no external binary required):
   ```yaml
   test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8081"]
   ```
   Verified: after this change `k83probe-schema-registry` reported `(healthy)`
   and `kafka-connect` started normally.

3. **`kafka-features` CLI: `--bootstrap-server` must precede the subcommand.**
   Not a broker rejection, but a brief-command breakage worth recording: the
   brief's literal `kafka-features describe --bootstrap-server kafka:29092`
   errors with `Command line error: unrecognized arguments: '--bootstrap-server'`
   on 8.3.2's argparse-based CLI. Correct form:
   `kafka-features --bootstrap-server kafka:29092 describe`. Used the
   corrected form for the acceptance check (task-3-report.md has the output).

## MirrorMaker 2 — proof, not upstream doc

No MM2-specific removed/renamed config was found by inspection or by the
boot (the same `mm2.properties.template` fields used against 7.6.0 rendered
and ran unchanged against 8.3.2's `connect-mirror-maker`). The proof that
matters here is functional: an 8.3.2 (AK 4.3) MM2 client authenticated over
SASL_PLAINTEXT against the still-7.6.0 hub broker, created
`k83probe.heartbeats` and the `mm2-*.k83probe.internal` bookkeeping topics on
the hub, and produced with zero `Expiring|SaslAuthenticationException|UnsupportedVersion`
matches across the run. See `task-3-report.md` for the exact log lines and
the hub topic list before/after cleanup.

## Client protocol floor

Not independently verifiable from fetched upstream text (see above). What we
can state from the boot: the 8.3.2 client successfully negotiated a produce/
consume session against the 7.6.0 (AK 3.6-era) hub broker with no
`UnsupportedVersion` in the logs, so whatever AK 4.3's client protocol floor
is, it did not break interop with the 7.6 hub in practice for the
request/response types MM2 uses (metadata, produce, offset commit/fetch,
topic create). This is the load-bearing fact for the fleet's mixed-version
window (clinics on 8.3.2, hub still 7.6.0); a stricter statement would need
the upstream doc we could not fetch.
