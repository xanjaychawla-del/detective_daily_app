# Detective Daily narration proxy (dev-only)

Holds the Anthropic API key server-side so it never ships inside the Flutter
app bundle. This is the **AI Adapter** layer: it receives one Truth Engine
fact plus a suspect's persona and returns only a natural phrasing of that
fact — it never invents facts or reveals guilt.

## Setup

```
cd server
npm install
cp .env.example .env   # then fill in ANTHROPIC_API_KEY
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
