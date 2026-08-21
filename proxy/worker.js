// FitTrack AI proxy — Cloudflare Worker.
//
// Injects the Google Gemini API key (never shipped in the app) and forwards
// requests to Gemini's OpenAI-compatible endpoint. The app sends OpenAI-style
// chat/completions bodies (including base64 image_url for meal photos); this
// only adds auth + pins the model, then streams the response straight back.
//
// Secrets (set with `wrangler secret put NAME`):
//   GEMINI_KEY  — your Gemini API key (billing enabled so data isn't used for training)
//   APP_TOKEN   — optional shared token; if set, requests must send matching x-app-token

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";
// Tried in order — lite is the default (noticeably faster + more spare capacity);
// if it's overloaded (503) we fall through to full flash. Both are multimodal
// (coach chat + meal photos); "latest" aliases avoid version churn.
const MODELS = ["gemini-flash-lite-latest", "gemini-flash-latest"];

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("Not found", { status: 404 });
    }
    // ponytail: the app token is a speed bump only — it ships in the binary and
    // is extractable. Real cost control is rate limiting + the Google budget cap.
    if (env.APP_TOKEN && request.headers.get("x-app-token") !== env.APP_TOKEN) {
      return new Response("Unauthorized", { status: 401 });
    }

    // Per-IP rate limit so one user/bot can't drain the budget. The app turns a
    // 429 into "AI is busy right now". Tune the limit in wrangler.toml — 20/min
    // is generous for real use; raise it if legit users behind shared IPs (CGNAT)
    // get limited. Real users route through here; abuse gets capped cheaply.
    const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
    const { success } = await env.AI_RATE_LIMIT.limit({ key: ip });
    if (!success) {
      return new Response("Rate limited — slow down and try again.", { status: 429 });
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response("Bad request", { status: 400 });
    }
    // Keep "thinking" minimal by default — this app's tasks (fitness advice, meal JSON)
    // don't need it, and heavy reasoning ~10x's token cost and can truncate short outputs.
    // The app can override by sending its own reasoning_effort.
    // NOTE (2026-07-22): "none" used to work but Gemini now rejects it with
    // 400 INVALID_ARGUMENT — "minimal" is the lowest value it still accepts.
    if (body.reasoning_effort === undefined) body.reasoning_effort = "minimal";

    // Gemini returns 503 UNAVAILABLE on demand spikes. For each model, retry once
    // with backoff; if it's still overloaded, fall through to the next model. The
    // 503 body is small JSON (not the SSE stream), so retrying is safe for both
    // streaming and non-streaming requests. Any non-503 (success or a real error)
    // is returned immediately.
    let upstream;
    outer: for (const model of MODELS) {
      body.model = model; // pin server-side so provider/model swaps need no app update
      const payload = JSON.stringify(body);
      for (let attempt = 0; attempt < 2; attempt++) {
        upstream = await fetch(GEMINI_URL, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${env.GEMINI_KEY}`,
            "Content-Type": "application/json",
          },
          body: payload,
        });
        if (upstream.status !== 503) break outer;
        if (attempt === 0) await new Promise((r) => setTimeout(r, 500));
      }
    }

    // Pass the response (including the SSE stream) straight back.
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        "Content-Type": upstream.headers.get("Content-Type") ?? "application/json",
      },
    });
  },
};
