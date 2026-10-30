import { describe, it, expect, vi, afterEach } from "vitest";
import worker, { isRetryableStatus, computeBackoffMs, fetchWithTimeout } from "./worker.js";

function makeRequest(body = { messages: [{ role: "user", content: "hi" }] }, headers = {}) {
  return new Request("https://fittrack-ai.example.workers.dev/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.5", ...headers },
    body: JSON.stringify(body),
  });
}

function jsonResponse(status, body = {}) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// The Miniflare version bundled with this vitest-pool-workers release doesn't simulate the
// [[ratelimits]] binding declared in wrangler.toml, so tests that don't care about rate
// limiting get an always-allow fake; the "rate limiting" suite below injects a fake that
// mirrors the real binding's documented contract (`limit({key}) -> {success}`) to exercise
// our own integration with it.
const alwaysAllow = { limit: async () => ({ success: true }) };
const baseEnv = (overrides = {}) => ({
  GEMINI_KEY: "test-gemini-key",
  APP_TOKEN: undefined,
  AI_RATE_LIMIT: alwaysAllow,
  ...overrides,
});

function makeFakeRateLimiter(limitPerWindow) {
  const counts = new Map();
  return {
    limit: async ({ key }) => {
      const count = (counts.get(key) ?? 0) + 1;
      counts.set(key, count);
      return { success: count <= limitPerWindow };
    },
  };
}

describe("pure helpers", () => {
  it("isRetryableStatus treats 429 and any 5xx as retryable, other statuses as not", () => {
    expect(isRetryableStatus(429)).toBe(true);
    expect(isRetryableStatus(500)).toBe(true);
    expect(isRetryableStatus(503)).toBe(true);
    expect(isRetryableStatus(599)).toBe(true);
    expect(isRetryableStatus(400)).toBe(false);
    expect(isRetryableStatus(404)).toBe(false);
    expect(isRetryableStatus(200)).toBe(false);
  });

  it("computeBackoffMs grows exponentially and caps at 4000ms, with full jitter", () => {
    const spy = vi.spyOn(Math, "random").mockReturnValue(1); // deterministic: max jitter
    expect(computeBackoffMs(0)).toBeCloseTo(300);
    expect(computeBackoffMs(1)).toBeCloseTo(600);
    expect(computeBackoffMs(2)).toBeCloseTo(1200);
    expect(computeBackoffMs(3)).toBeCloseTo(2400);
    expect(computeBackoffMs(4)).toBeCloseTo(4000); // 300*2^4=4800, capped to 4000
    expect(computeBackoffMs(5)).toBeCloseTo(4000);
    spy.mockReturnValue(0);
    expect(computeBackoffMs(0)).toBe(0); // jitter floor
    spy.mockRestore();
  });

  it("fetchWithTimeout aborts the underlying fetch via AbortController once the timeout elapses", async () => {
    vi.useFakeTimers();
    const hangingFetch = vi.fn(
      (url, options) =>
        new Promise((_, reject) => {
          options.signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")));
        })
    );
    vi.stubGlobal("fetch", hangingFetch);

    const pending = fetchWithTimeout("https://example.com", {}, 1000);
    let rejected = false;
    pending.catch(() => {
      rejected = true;
    });

    await vi.advanceTimersByTimeAsync(999);
    expect(rejected).toBe(false); // not yet — timeout hasn't elapsed

    await vi.advanceTimersByTimeAsync(2);
    await expect(pending).rejects.toThrow();

    vi.unstubAllGlobals();
    vi.useRealTimers();
  });
});

describe("method, auth, and body validation", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("rejects non-POST requests with 404", async () => {
    const req = new Request("https://fittrack-ai.example.workers.dev/", { method: "GET" });
    const res = await worker.fetch(req, baseEnv());
    expect(res.status).toBe(404);
  });

  it("rejects requests missing a matching x-app-token when APP_TOKEN is set, without calling Gemini", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const res = await worker.fetch(makeRequest(), baseEnv({ APP_TOKEN: "secret" }));
    expect(res.status).toBe(401);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("accepts requests with a matching x-app-token", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(200, { ok: true })));
    const res = await worker.fetch(makeRequest({}, { "x-app-token": "secret" }), baseEnv({ APP_TOKEN: "secret" }));
    expect(res.status).toBe(200);
  });

  it("rejects malformed JSON bodies with 400", async () => {
    const req = new Request("https://fittrack-ai.example.workers.dev/", {
      method: "POST",
      headers: { "CF-Connecting-IP": "203.0.113.5" },
      body: "not json",
    });
    const res = await worker.fetch(req, baseEnv());
    expect(res.status).toBe(400);
  });
});

describe("reasoning_effort default", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("defaults reasoning_effort to \"minimal\" when the app doesn't set one", async () => {
    let capturedBody;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (_url, options) => {
        capturedBody = JSON.parse(options.body);
        return jsonResponse(200, {});
      })
    );
    await worker.fetch(makeRequest({ messages: [] }), baseEnv());
    expect(capturedBody.reasoning_effort).toBe("minimal");
  });

  it("respects an app-supplied reasoning_effort instead of overriding it", async () => {
    let capturedBody;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (_url, options) => {
        capturedBody = JSON.parse(options.body);
        return jsonResponse(200, {});
      })
    );
    await worker.fetch(makeRequest({ messages: [], reasoning_effort: "high" }), baseEnv());
    expect(capturedBody.reasoning_effort).toBe("high");
  });
});

describe("fallback chain", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("returns immediately on a non-retryable 4xx, without retrying or falling back", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(400, { error: "bad request" }));
    vi.stubGlobal("fetch", fetchMock);
    const res = await worker.fetch(makeRequest(), baseEnv());
    expect(res.status).toBe(400);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("falls back to the second model after exhausting retries with a 5xx from the first", async () => {
    vi.spyOn(Math, "random").mockReturnValue(0); // zero jitter delay, keeps the test fast
    const calls = [];
    const fetchMock = vi.fn(async (_url, options) => {
      const payload = JSON.parse(options.body);
      calls.push(payload.model);
      if (payload.model === "gemini-flash-lite-latest") return jsonResponse(503, { error: "overloaded" });
      return jsonResponse(200, { ok: true });
    });
    vi.stubGlobal("fetch", fetchMock);

    const res = await worker.fetch(makeRequest(), baseEnv());
    expect(res.status).toBe(200);
    expect(calls).toEqual(["gemini-flash-lite-latest", "gemini-flash-lite-latest", "gemini-flash-latest"]);
  });

  it("falls back on a 429 from the first model, same as a 5xx", async () => {
    vi.spyOn(Math, "random").mockReturnValue(0);
    const calls = [];
    const fetchMock = vi.fn(async (_url, options) => {
      const payload = JSON.parse(options.body);
      calls.push(payload.model);
      if (payload.model === "gemini-flash-lite-latest") return jsonResponse(429, { error: "rate limited" });
      return jsonResponse(200, { ok: true });
    });
    vi.stubGlobal("fetch", fetchMock);

    const res = await worker.fetch(makeRequest(), baseEnv());
    expect(res.status).toBe(200);
    expect(calls).toEqual(["gemini-flash-lite-latest", "gemini-flash-lite-latest", "gemini-flash-latest"]);
  });

  it("returns the final status after exhausting every model and attempt (429 throughout)", async () => {
    vi.spyOn(Math, "random").mockReturnValue(0);
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(429, { error: "rate limited upstream" }));
    vi.stubGlobal("fetch", fetchMock);

    const res = await worker.fetch(makeRequest(), baseEnv());
    expect(res.status).toBe(429);
    expect(fetchMock).toHaveBeenCalledTimes(4); // 2 models x 2 attempts each
  });

  it("treats a timeout/network error as retryable and returns 504 if every attempt fails that way", async () => {
    vi.spyOn(Math, "random").mockReturnValue(0);
    const fetchMock = vi.fn().mockRejectedValue(new DOMException("Aborted", "AbortError"));
    vi.stubGlobal("fetch", fetchMock);

    const res = await worker.fetch(makeRequest(), baseEnv());
    expect(res.status).toBe(504);
    expect(fetchMock).toHaveBeenCalledTimes(4);
  });

  it("recovers from a timeout on the first attempt if the retry on the same model succeeds", async () => {
    vi.spyOn(Math, "random").mockReturnValue(0);
    let attempt = 0;
    const fetchMock = vi.fn(async () => {
      attempt++;
      if (attempt === 1) throw new DOMException("Aborted", "AbortError");
      return jsonResponse(200, { ok: true });
    });
    vi.stubGlobal("fetch", fetchMock);

    const res = await worker.fetch(makeRequest(), baseEnv());
    expect(res.status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});

describe("SSE passthrough", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("streams an SSE response body straight through, unbuffered, with the same content type", async () => {
    const chunks = [
      'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n',
      'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n',
      "data: [DONE]\n\n",
    ];
    const stream = new ReadableStream({
      start(controller) {
        for (const chunk of chunks) controller.enqueue(new TextEncoder().encode(chunk));
        controller.close();
      },
    });
    const upstream = new Response(stream, { status: 200, headers: { "Content-Type": "text/event-stream" } });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(upstream));

    const res = await worker.fetch(makeRequest({ stream: true }), baseEnv());
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("text/event-stream");
    expect(await res.text()).toBe(chunks.join(""));
  });
});

describe("rate limiting (AI_RATE_LIMIT binding: 20/60s per IP, per wrangler.toml)", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("allows the first 20 requests from one IP and rate-limits the 21st", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(200, { ok: true })));
    const limiter = makeFakeRateLimiter(20);
    const ip = "198.51.100.7";
    const statuses = [];
    for (let i = 0; i < 21; i++) {
      const res = await worker.fetch(makeRequest({}, { "CF-Connecting-IP": ip }), baseEnv({ AI_RATE_LIMIT: limiter }));
      statuses.push(res.status);
    }
    expect(statuses.slice(0, 20).every((s) => s === 200)).toBe(true);
    expect(statuses[20]).toBe(429);
  });

  it("tracks a different IP independently of an already-limited one", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(200, { ok: true })));
    const limiter = makeFakeRateLimiter(20);
    const limitedIp = "198.51.100.8";
    for (let i = 0; i < 20; i++) {
      await worker.fetch(makeRequest({}, { "CF-Connecting-IP": limitedIp }), baseEnv({ AI_RATE_LIMIT: limiter }));
    }
    const blocked = await worker.fetch(makeRequest({}, { "CF-Connecting-IP": limitedIp }), baseEnv({ AI_RATE_LIMIT: limiter }));
    expect(blocked.status).toBe(429);

    const freshIp = "198.51.100.9";
    const fresh = await worker.fetch(makeRequest({}, { "CF-Connecting-IP": freshIp }), baseEnv({ AI_RATE_LIMIT: limiter }));
    expect(fresh.status).toBe(200);
  });
});
