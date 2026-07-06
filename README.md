# Detective Daily

A daily detective-mystery game for Android/iOS: interview suspects, unlock
evidence, and accuse the culprit -- or give up and see the full solution.
Built in Flutter, backed by Supabase (Postgres + Edge Functions) and
Google Gemini for AI narration and case generation, with Firebase
Analytics/Crashlytics for telemetry.

## Architecture

The game logic is split into four layers, designed so AI can *phrase*
content without ever being trusted to *invent* the puzzle itself:

1. **Truth Engine** (`lib/truth_engine/`) -- immutable case data (suspects,
   facts, evidence, timeline, solution). Pure data, no game logic.
2. **Game Engine** (`lib/game_engine/`) -- a Riverpod `Notifier` holding
   session state: Focus economy, interviewed/ruled-out suspects, unlocked
   evidence, accusation outcome. Enforces the fairness rules (wrong
   accusations never end the game, background checks require a prior
   interview, etc.).
3. **Conversation Engine** (`lib/conversation_engine/`) -- decides which
   fact a suspect is allowed to reveal, when, and to whom.
4. **AI Adapter** (`lib/ai_adapter/`) -- the *only* place an LLM touches
   gameplay. Given one fact plus a persona, it returns a natural-language
   phrasing of that exact fact and nothing else. If the backend is
   unreachable, it falls back to the raw fact text rather than blocking
   play.

One deliberate exception to "AI never invents": the **"Get New Case"**
button on Case Files has Gemini author an entirely new case from scratch
(`supabase/functions/generate-case`). Every generated case is structurally
validated (exactly one culprit, every evidence/timeline reference resolves,
all four fact categories present per suspect) before it's saved -- this
guarantees structural fairness, not narrative quality.

## Project structure

```
lib/
  truth_engine/        Case, Suspect, Evidence, Timeline models (immutable)
  game_engine/          GameState + GameStateNotifier (Focus, accusations, outcome)
  conversation_engine/  Fact-reveal gating logic
  ai_adapter/           Calls the `narrate` Edge Function; raw-text fallback
  case_repository/      Supabase queries: cases, play status, ratings, case generation
  core/                 Theme, env (dart-define config), analytics
  screens/              All UI: Case Files, Suspects/Evidence/Accuse tabs, outcome screen
assets/
  cases/                The 3 hand-authored cases (also seeded into Supabase)
  icon/, images/         App icon source + loading-screen artwork
supabase/
  migrations/           cases, plays, case_ratings tables + RLS policies
  functions/
    generate-case/       AI case authoring (Gemini, validated before saving)
    narrate/              AI Adapter's phrasing endpoint (Gemini)
server/                  DEPRECATED -- old local narration proxy, no longer used
test/                    Unit tests for Game/Conversation Engine fairness rules
```

## Setup

```
flutter pub get
cp dart_defines.example.json dart_defines.dev.json   # fill in your Supabase URL + anon key
flutter run --dart-define-from-file=dart_defines.dev.json
```

Backend (Supabase):
```
supabase link --project-ref <your-project-ref>
supabase db push                      # applies all migrations
supabase secrets set GEMINI_API_KEY=...
supabase functions deploy generate-case --no-verify-jwt
supabase functions deploy narrate --no-verify-jwt
```

Firebase Analytics/Crashlytics config (`lib/firebase_options.dart`,
`android/app/google-services.json`) is already checked in for the
`detective-daily-app` Firebase project. To point at a different project,
run `flutterfire configure` again.

App icon regeneration (after replacing `assets/icon/icon.png`):
```
dart run flutter_launcher_icons
```

## Backend data model

- **`cases`** -- one row per case (authored or AI-generated), full Truth
  Engine content as jsonb, publicly readable.
- **`plays`** -- one row per (user, case): `unopened` / `in_progress` /
  `solved` / `gave_up`. Keyed by Supabase Auth's `auth.uid()` -- every
  player is signed in anonymously (guest) on first launch so progress is
  tracked against a real, verifiable identity rather than a client-supplied
  string, with a clean path to link a real account later.
- **`case_ratings`** + **`case_rating_stats`** (view) -- one optional 1-5
  star rating per (user, case), shown as an average + rater count on each
  case card.

## Known limitations (pre-launch prototype)

- No registration/tiers yet -- every user is an anonymous guest. Real
  sign-up, account linking, and per-tier case limits are a later phase.
- Edge functions are deployed with `--no-verify-jwt` and RLS is the only
  access control -- fine for a prototype with no paid tiers yet, revisit
  before any monetized launch.
- Only mid-case terminal status (solved/gave-up) is synced; Focus/evidence
  progress mid-case is not resumed if you leave and come back.
- iOS has not been built/tested from this (Windows) development machine.

## Development log

- **Prototype** -- four-layer architecture stood up end-to-end with one
  hand-authored case ("The Missing Diamond"), AI narration via a local
  dev proxy, Riverpod state, full unit test coverage of the fairness rules.
- **Second case + polish** -- authored "Turbulence at 30,000 Feet",
  added Play Again/New Case flows to the case outcome screen, set up
  Codemagic CI.
- **Home screen + live case generation** -- added the Case Files launch
  screen backed by a new Supabase project (`cases`/`plays` tables), a
  "Get New Case" action that has Gemini author and validate a brand-new
  case, and a dark theme + pill-badge visual pass across every screen.
- **Claude to Gemini** -- switched both AI call sites (narration + case
  generation) from Anthropic Claude to Google Gemini's free tier, since
  Claude's API has no free tier and this app has no revenue yet. Along
  the way, fixed a real bug where Gemini's default "thinking" was eating
  into the output token budget and intermittently truncating generated
  cases into invalid JSON -- fixed by disabling thinking for these two
  narrow, template-following calls.
- **Case Files tabs + navigation** -- split Case Files into Unsolved/New/
  Archive tabs (swipeable, defaults to New when Unsolved is empty), added
  a back button from inside a case (there was previously no way back
  except finishing the case), app icon and display name set from the
  Detective Daily brand assets, and a full-bleed custom loading screen.
- **Guest auth + ratings** -- migrated play-status tracking from a
  locally-generated device id (reset on reinstall, unverifiable
  server-side) to Supabase anonymous auth (`auth.uid()`, proper RLS).
  Added a 1-5 star case rating prompt on the outcome screen, shown as an
  average + rater count on each case card.
- **Narration moved server-side properly** -- the AI Adapter's narration
  call originally hit a local dev-only proxy reachable only from an
  Android emulator or the developer's own LAN; a real phone anywhere else
  would hang for the full timeout on every line of dialogue before
  falling back to unnarrated text. Replaced with a `narrate` Supabase Edge
  Function, matching `generate-case`'s pattern.
- **Firebase Analytics + Crashlytics** -- new dedicated Firebase project,
  automatic screen-view tracking plus custom events at the core game
  funnel (case opened/generated/solved/gave up), Crashlytics wired to
  Flutter's error handlers.
