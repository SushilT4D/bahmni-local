#!/usr/bin/env node
/**
 * Kafka Connect + Topic Activity Monitor
 *
 * What it does:
 * - Polls Kafka Connect for connectors, configs, and status
 * - Discovers topics from connector configs where possible (topics/topic)
 * - Uses Kafka Admin (kafkajs) to fetch topic end offsets
 * - Tracks "last activity" time when offsets increase (proxy for "last message received")
 *
 * Notes:
 * - "Number of messages" shown is total log-end offsets summed across partitions
 *   (it’s not perfect “current retained messages”, but useful for activity + growth).
 * - If a topic is compacted or retention deletes old data, totals may not reflect "retained".
 */

const { Kafka } = require("kafkajs");

// -------------------- Config --------------------
const CONNECT_URLS = (process.env.CONNECT_URLS || "http://localhost:8083")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const KAFKA_BROKERS = (process.env.KAFKA_BROKERS || "localhost:9092")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const CLIENT_ID = process.env.CLIENT_ID || "connect-monitor";
const INTERVAL_MS = parseInt(process.env.INTERVAL_MS || "10000", 10);

// Optional: seed topics explicitly (comma-separated). These are always monitored.
const EXTRA_TOPICS = new Set(
  (process.env.TOPICS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
);

// Optional SASL/TLS (uncomment/use envs if needed)
function buildKafkaConfig() {
  const cfg = {
    clientId: CLIENT_ID,
    brokers: KAFKA_BROKERS,
  };

  // TLS
  if ((process.env.KAFKA_SSL || "").toLowerCase() === "true") {
    cfg.ssl = true;
  }

  // SASL
  // Supported mechanisms in kafkajs: plain, scram-sha-256, scram-sha-512, oauthbearer
  if (process.env.KAFKA_SASL_MECHANISM && process.env.KAFKA_SASL_USERNAME) {
    cfg.sasl = {
      mechanism: process.env.KAFKA_SASL_MECHANISM,
      username: process.env.KAFKA_SASL_USERNAME,
      password: process.env.KAFKA_SASL_PASSWORD || "",
    };
  }

  return cfg;
}

// -------------------- State --------------------
/**
 * topicState[topic] = {
 *   lastTotalEndOffset: number,
 *   lastActivityAt: number (ms since epoch),
 *   lastSeenAt: number,
 * }
 */
const topicState = new Map();

function nowMs() {
  return Date.now();
}

function fmtDuration(ms) {
  if (ms == null || !Number.isFinite(ms)) return "n/a";
  const sec = Math.floor(ms / 1000);
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (d > 0) return `${d}d ${h}h ${m}m ${s}s`;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

async function fetchJson(url, opts = {}) {
  const res = await fetch(url, {
    ...opts,
    headers: {
      "Accept": "application/json",
      ...(opts.headers || {}),
    },
  });
  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    throw new Error(`HTTP ${res.status} ${res.statusText} for ${url} :: ${txt}`);
  }
  return res.json();
}

// -------------------- Connect Polling --------------------
async function listConnectors(connectBase) {
  return fetchJson(`${connectBase}/connectors`);
}

async function getConnectorStatus(connectBase, name) {
  return fetchJson(`${connectBase}/connectors/${encodeURIComponent(name)}/status`);
}

async function getConnectorConfig(connectBase, name) {
  return fetchJson(`${connectBase}/connectors/${encodeURIComponent(name)}/config`);
}

/**
 * Try to infer topics from a connector config.
 * Covers common cases:
 * - Sink: "topics"
 * - Some source connectors: "topic"
 * - Debezium: "topic.prefix" (not exact topics; we can’t enumerate without schema/history + table mapping)
 */
function inferTopicsFromConfig(cfg) {
  const topics = new Set();

  // Sink connectors typically use: topics=a,b,c
  if (cfg.topics) {
    cfg.topics.split(",").map((s) => s.trim()).filter(Boolean).forEach((t) => topics.add(t));
  }

  // Some source connectors use: topic=foo
  if (cfg.topic) {
    String(cfg.topic).split(",").map((s) => s.trim()).filter(Boolean).forEach((t) => topics.add(t));
  }

  // Sometimes: topics.regex=... (cannot enumerate safely)
  // Debezium: topic.prefix=... (cannot enumerate safely)
  // We’ll just skip those unless user explicitly sets TOPICS env var.

  return topics;
}

async function listAllTopics(admin) {
    // include internal topics so you can optionally watch MM2 internal topics too
    // (e.g., heartbeats, checkpoints). Adjust if you want excludeInternal.
    const topics = await admin.listTopics();
    return topics;
  }
  
  function compileRegex(pattern) {
    // Kafka Connect regex patterns are Java regex; JS is close for common cases.
    // Good enough for typical ".*" / "prefix.*" / "foo|bar" patterns.
    // If you rely on advanced Java regex features, set TOPICS env explicitly.
    return new RegExp(pattern);
  }
  
  async function expandTopicsFromConfig(admin, cfg) {
    const out = new Set();
  
    // 1) Exact topics list
    if (cfg.topics) {
      cfg.topics.split(",").map(s => s.trim()).filter(Boolean).forEach(t => out.add(t));
    }
    if (cfg.topic) {
      String(cfg.topic).split(",").map(s => s.trim()).filter(Boolean).forEach(t => out.add(t));
    }
  
    // 2) Regex topics (MM2 commonly uses topics.regex)
    if (cfg["topics.regex"]) {
      const all = await listAllTopics(admin);
      const re = compileRegex(cfg["topics.regex"]);
      all.filter(t => re.test(t)).forEach(t => out.add(t));
    }
  
    // 3) Debezium topic prefix (topic.prefix)
    // Confluent’s Debezium docs: topic.prefix is used as the prefix for emitted topics. :contentReference[oaicite:2]{index=2}
    if (cfg["topic.prefix"]) {
      const prefix = String(cfg["topic.prefix"]);
      const all = await listAllTopics(admin);
      all.filter(t => t.startsWith(prefix + ".") || t === prefix).forEach(t => out.add(t));
    }
  
    // 4) MM2 default naming often prefixes topics with source alias (e.g., primary.orders). :contentReference[oaicite:3]{index=3}
    // If you monitor the *target* cluster, you can also catch that pattern:
    if (cfg["source.cluster.alias"]) {
      const alias = String(cfg["source.cluster.alias"]);
      const all = await listAllTopics(admin);
      all.filter(t => t.startsWith(alias + ".")).forEach(t => out.add(t));
    }
  
    return out;
  }
  
// -------------------- Kafka Topic Offsets --------------------
async function getTopicTotalEndOffset(admin, topic) {
  // fetchTopicOffsets returns per partition { partition, offset, ... } where offset is high watermark as string
  const partitions = await admin.fetchTopicOffsets(topic);
  let total = 0n;
  for (const p of partitions) {
    // kafkajs uses strings
    const off = BigInt(p.offset);
    total += off;
  }
  return total; // BigInt
}

function updateTopicActivity(topic, totalEndOffsetBigInt) {
  const total = totalEndOffsetBigInt; // BigInt
  const t = nowMs();

  const prev = topicState.get(topic);
  if (!prev) {
    topicState.set(topic, {
      lastTotalEndOffset: total,
      lastActivityAt: t, // treat first sight as "active now"
      lastSeenAt: t,
    });
    return;
  }

  // If end offsets increased, consider "new messages received"
  if (total > prev.lastTotalEndOffset) {
    prev.lastActivityAt = t;
    prev.lastTotalEndOffset = total;
  } else {
    // keep lastTotalEndOffset as-is, but refresh lastSeenAt
    prev.lastTotalEndOffset = total; // still update in case topic shrinks? (rare)
  }
  prev.lastSeenAt = t;
}

// -------------------- Rendering --------------------
function clearScreen() {
  // Works in most terminals
  process.stdout.write("\x1b[2J\x1b[0f");
}

function pad(s, n) {
  s = String(s);
  if (s.length >= n) return s.slice(0, n);
  return s + " ".repeat(n - s.length);
}

function bigIntToString(bi) {
  try {
    return bi.toString();
  } catch {
    return String(bi);
  }
}

function renderDashboard({ connectResults, topicResults, errors }) {
  clearScreen();
  const t = new Date().toISOString();

  console.log(`Kafka Connect + Topic Monitor  |  ${t}`);
  console.log(`Connect: ${CONNECT_URLS.join(", ")}  |  Brokers: ${KAFKA_BROKERS.join(", ")}  |  Interval: ${INTERVAL_MS}ms`);
  console.log("=".repeat(110));

  // ---- Connectors ----
  console.log("\nCONNECTORS");
  console.log(pad("cluster", 18), pad("connector", 35), pad("state", 10), pad("tasks", 18), "error");
  console.log("-".repeat(110));

  for (const cr of connectResults) {
    const cluster = cr.connectBase;
    if (cr.error) {
      console.log(pad(cluster, 18), pad("(connect)", 35), pad("ERROR", 10), pad("-", 18), cr.error);
      continue;
    }

    for (const c of cr.connectors) {
      const tasks = `${c.runningTasks}/${c.totalTasks}`;
      const err = c.error || "";
      console.log(
        pad(cluster, 18),
        pad(c.name, 35),
        pad(c.state, 10),
        pad(tasks, 18),
        err
      );
    }
  }

  // ---- Topics ----
  console.log("\nTOPICS (activity inferred from end-offset growth)");
  console.log(pad("topic", 45), pad("totalEndOffset", 18), pad("sinceLastNewMsg", 18), "notes");
  console.log("-".repeat(110));

  for (const tr of topicResults) {
    if (tr.error) {
      console.log(pad(tr.topic, 45), pad("-", 18), pad("-", 18), tr.error);
      continue;
    }
    const st = topicState.get(tr.topic);
    const since = st ? fmtDuration(nowMs() - st.lastActivityAt) : "n/a";
    console.log(
      pad(tr.topic, 45),
      pad(bigIntToString(tr.totalEndOffset), 18),
      pad(since, 18),
      tr.note || ""
    );
  }

  // ---- Errors ----
  if (errors.length) {
    console.log("\nWARN/ERRORS");
    for (const e of errors.slice(-10)) console.log(`- ${e}`);
  }

  console.log("\n(CTRL+C to stop)");
}

// -------------------- Main Loop --------------------
async function pollOnce(admin) {
  const errors = [];

  // 1) Poll Connect clusters
  const connectResults = [];
  const discoveredTopics = new Set([...EXTRA_TOPICS]);

  for (const connectBase of CONNECT_URLS) {
    const cr = { connectBase, connectors: [], error: null };

    try {
      const names = await listConnectors(connectBase);

      for (const name of names) {
        let status, cfg;
        try {
          // Status
          status = await getConnectorStatus(connectBase, name);
        } catch (e) {
          errors.push(`[${connectBase}] status ${name}: ${e.message}`);
        }

        try {
          // Config -> infer topics
          cfg = await getConnectorConfig(connectBase, name);
          const tset = await expandTopicsFromConfig(admin, cfg);
          for (const t of tset) discoveredTopics.add(t);
        } catch (e) {
          errors.push(`[${connectBase}] config ${name}: ${e.message}`);
        }

        // Summarize connector
        const connectorState = status?.connector?.state || "UNKNOWN";
        const tasksArr = Array.isArray(status?.tasks) ? status.tasks : [];
        const totalTasks = tasksArr.length;
        const runningTasks = tasksArr.filter((t) => t.state === "RUNNING").length;

        // Capture first error from connector/tasks if present
        const connectorTrace = status?.connector?.trace;
        const taskTrace = tasksArr.find((t) => t.trace)?.trace;
        const err = connectorTrace || taskTrace || "";

        cr.connectors.push({
          name,
          state: connectorState,
          totalTasks,
          runningTasks,
          error: err ? String(err).split("\n")[0] : "",
        });
      }
    } catch (e) {
      cr.error = e.message;
      errors.push(`[${connectBase}] list connectors: ${e.message}`);
    }

    // sort connectors for stable output
    cr.connectors.sort((a, b) => a.name.localeCompare(b.name));
    connectResults.push(cr);
  }

  // 2) Poll topics end offsets
  const topics = Array.from(discoveredTopics).sort();
  const topicResults = [];

  for (const topic of topics) {
    try {
      const totalEndOffset = await getTopicTotalEndOffset(admin, topic);
      updateTopicActivity(topic, totalEndOffset);
      topicResults.push({ topic, totalEndOffset });
    } catch (e) {
      // Common if topic doesn’t exist or ACL denies describe
      topicResults.push({ topic, error: e.message });
      errors.push(`[kafka] topic ${topic}: ${e.message}`);
    }
  }

  renderDashboard({ connectResults, topicResults, errors });
}

async function main() {
  const kafka = new Kafka(buildKafkaConfig());
  const admin = kafka.admin();

  process.on("SIGINT", async () => {
    try {
      await admin.disconnect();
    } catch {}
    process.exit(0);
  });

  await admin.connect();

  // Initial render even if poll fails
  while (true) {
    const start = nowMs();
    try {
      await pollOnce(admin);
    } catch (e) {
      clearScreen();
      console.error(`[fatal] ${e.stack || e.message}`);
    }
    const elapsed = nowMs() - start;
    const sleep = Math.max(250, INTERVAL_MS - elapsed);
    await new Promise((r) => setTimeout(r, sleep));
  }
}

main().catch((e) => {
  console.error(e.stack || e.message);
  process.exit(1);
});
