# Detective Daily narration proxy (DEPRECATED, unused)

The app no longer calls this server. Narration now runs through the
`supabase/functions/narrate` Edge Function instead, because this local
proxy was only reachable from an Android emulator (via its `10.0.2.2`
loopback alias) or another device on the developer's own network -- a
real phone anywhere else would hang for the full request timeout on
every line of suspect dialogue before falling back to unnarrated text.
This directory is kept only as a historical reference and can be
deleted; nothing in the Flutter app points to it anymore.

---

Holds the Gemini API key server-side so it never ships inside the Flutter
app bundle. This is the **AI Adapter** layer: it receives one Truth Engine
fact plus a suspect's persona and returns only a natural phrasing of that
fact — it never invents facts or reveals guilt.

Uses Gemini (via Google AI Studio's free tier, `gemini-2.5-flash` by default)
rather than a paid API, matching the same provider already used by
`cat_rarity_app`'s `chat-with-kitty` and `gemini-scan` edge functions.

## Setup

```
cd server
npm install
cp .env.example .env   # then fill in GEMINI_API_KEY (get one at aistudio.google.com)
npm start
```

Runs on `http://localhost:8787` by default. From the Android emulator, the
Flutter app reaches it via `http://10.0.2.2:8787` (the emulator's alias for
the host machine's localhost).

## Not for distribution

This is a local, unauthenticated dev server. Before shipping this app to
real users, replace it with a properly authenticated backend (e.g. a
Supabase Edge Function like `chat-with-kitty` in the cat_rarity_app repo,
which keeps the LLM key in server-side secrets and requires a signed-in
user) rather than exposing this endpoint publicly.
