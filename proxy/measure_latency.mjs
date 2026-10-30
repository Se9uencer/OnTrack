#!/usr/bin/env node
// Measures time-to-first-token and total latency through the deployed AI proxy's
// streaming chat path. Capped at a fixed request budget and paced below the Worker's
// own rate limit (20/60s/IP, see wrangler.toml) so the numbers reflect real latency,
// not 429s from hammering it. Chat path only — does not touch the meal-photo path.
//
// Usage: node measure_latency.mjs [requestCount]   (default 50, hard-capped at 50)

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ENDPOINT = "https://fittrack-ai.ibrahim-ansari0801.workers.dev";
const HARD_CAP = 50;
const SPACING_MS = 3_200; // keeps 20 requests inside any rolling 60s window, with margin

const __dirname = dirname(fileURLToPath(import.meta.url));

function readAppToken() {
  try {
    const text = readFileSync(join(__dirname, "..", "Config", "Secrets.xcconfig"), "utf8");
    const match = text.match(/^APP_TOKEN\s*=\s*(\S+)/m);
    return match ? match[1] : "";
  } catch {
    return "";
  }
}

function percentile(sortedValues, p) {
  if (sortedValues.length === 0) return NaN;
  const index = Math.min(sortedValues.length - 1, Math.floor((p / 100) * sortedValues.length));
  return sortedValues[index];
}

async function measureOne(appToken) {
  const headers = { "Content-Type": "application/json" };
  if (appToken) headers["x-app-token"] = appToken;

  const t0 = performance.now();
  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers,
      body: JSON.stringify({
        messages: [{ role: "user", content: "In one short sentence, name one benefit of resistance training." }],
        temperature: 0.6,
        max_tokens: 150,
        stream: true,
      }),
    });

    if (res.status !== 200) {
      return { ok: false, status: String(res.status) };
    }

    let firstTokenMs = null;
    let buffer = "";
    for await (const chunk of res.body) {
      const now = performance.now();
      buffer += Buffer.from(chunk).toString("utf8");
      let newlineIndex;
      while ((newlineIndex = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, newlineIndex);
        buffer = buffer.slice(newlineIndex + 1);
        if (!line.startsWith("data: ")) continue;
        const payload = line.slice(6);
        if (payload === "[DONE]") continue;
        try {
          const parsed = JSON.parse(payload);
          const content = parsed.choices?.[0]?.delta?.content;
          if (content && firstTokenMs === null) firstTokenMs = now - t0;
        } catch {
          // partial JSON mid-chunk — ignore, next chunk completes it
        }
      }
    }
    const totalMs = performance.now() - t0;
    return { ok: true, status: "200", firstTokenMs: firstTokenMs ?? totalMs, totalMs };
  } catch (err) {
    // Network-level failure (reset connection, DNS blip, etc.) — count as a failed
    // request rather than aborting the whole run.
    return { ok: false, status: `network error: ${err.cause?.code ?? err.message}` };
  }
}

async function main() {
  const requested = Number.parseInt(process.argv[2] ?? "50", 10);
  const count = Math.min(HARD_CAP, Number.isFinite(requested) && requested > 0 ? requested : HARD_CAP);
  const appToken = readAppToken();

  console.log(`Measuring ${count} chat requests against ${ENDPOINT}, paced ${SPACING_MS}ms apart...`);

  const ttft = [];
  const total = [];
  const failures = [];

  for (let i = 0; i < count; i++) {
    const result = await measureOne(appToken);
    if (result.ok) {
      ttft.push(result.firstTokenMs);
      total.push(result.totalMs);
      console.log(
        `[${i + 1}/${count}] ttft=${result.firstTokenMs.toFixed(0)}ms total=${result.totalMs.toFixed(0)}ms`
      );
    } else {
      failures.push(result.status);
      console.log(`[${i + 1}/${count}] FAILED status=${result.status}`);
    }
    if (i < count - 1) await new Promise((r) => setTimeout(r, SPACING_MS));
  }

  ttft.sort((a, b) => a - b);
  total.sort((a, b) => a - b);

  console.log("\n--- Results ---");
  console.log(`Successful: ${ttft.length}/${count}  Failed: ${failures.length}/${count}`);
  if (failures.length) console.log(`Failure statuses: ${failures.join(", ")}`);
  console.log(`Time to first token — p50: ${percentile(ttft, 50).toFixed(0)}ms  p95: ${percentile(ttft, 95).toFixed(0)}ms`);
  console.log(`Total latency        — p50: ${percentile(total, 50).toFixed(0)}ms  p95: ${percentile(total, 95).toFixed(0)}ms`);
}

main();
