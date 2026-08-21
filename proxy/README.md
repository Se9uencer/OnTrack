# FitTrack AI proxy

A tiny Cloudflare Worker that holds the Google Gemini API key and forwards the
app's requests to Gemini's OpenAI-compatible endpoint. The key never ships in
the app, so it can't be extracted from the IPA.

## One-time setup

1. **Enable billing on your Gemini key (paid tier).** In Google AI Studio /
   Cloud console, enable billing for the project and **set a budget cap** (e.g.
   $5/mo). This is required so user data (meal photos, fitness summaries) is
   **not used to train Google's models** — the free tier does use it, which the
   privacy policy forbids. Regenerate the key you pasted earlier; it's exposed.

2. **Install + log in:**
   ```bash
   npm install -g wrangler
   wrangler login
   ```

3. **Set secrets** (from this `proxy/` folder):
   ```bash
   wrangler secret put GEMINI_KEY      # paste your Gemini key
   wrangler secret put APP_TOKEN       # optional: any random string
   ```

4. **Deploy:**
   ```bash
   wrangler deploy
   ```
   Wrangler prints your Worker URL, e.g. `https://fittrack-ai.<subdomain>.workers.dev`.

5. **Point the app at it.** In `FitTrack/Sources/Services/AIClient.swift`, set
   `endpoint` to that URL. If you set an `APP_TOKEN`, set `appToken` to the same
   value.

## Cost & abuse control

Two layers protect your bill:

1. **Per-IP rate limit** (in `worker.js` / `wrangler.toml`) — 20 requests/minute
   per IP, so one user or bot can't hammer the proxy. Tune `limit` there.
2. **Google budget cap** — set one in the Cloud console. This is your hard
   ceiling. If it's hit, AI requests fail gracefully in the app ("AI is busy
   right now") and everything else keeps working.

Gemini 2.5 Flash is cheap (~$0.002–0.01 per coach message or meal photo). Costs
scale with active users, so pick a cap you're comfortable funding for a free
app. If usage grows enough to matter, that's the signal to add BYOK or a paid
tier — the app only talks to this proxy, so that's a proxy/app change, not a
rearchitecture.

## Swapping models or providers later

Change `MODEL` (or the whole upstream) in `worker.js` and redeploy — no app
update or App Store review needed, because the app only knows about the proxy.
