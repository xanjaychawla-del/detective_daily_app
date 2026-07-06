// Generate Case -- the one place in Detective Daily where AI *authors*
// content instead of just phrasing pre-written facts. That's a deliberate,
// user-approved exception to the rest of the app's "AI performs, never
// creates" rule, so this function carries the compensating control: every
// response is structurally validated before it's trusted or saved. A
// structurally valid case is not the same as a good one -- this catches
// broken references and missing pieces, not weak writing or a solvable
// puzzle. Narrative quality is not verified here.
//
// Secrets: GEMINI_API_KEY
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy with --no-verify-jwt: this prototype has no real auth, and the
// device-scoped `plays` table already accepts anonymous writes on the same
// basis (see supabase/migrations/001_plays.sql).
//
// Uses Gemini (Google AI Studio's free tier) rather than a paid API, matching
// the provider already used by cat_rarity_app's chat-with-kitty/gemini-scan
// functions.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MODEL = "gemini-2.5-flash";
const MAX_ATTEMPTS = 2;

// The worked example given to the model is the actual "Missing Diamond"
// case already shipped in the app -- real, schema-valid content, not a
// synthetic stub.
const EXAMPLE_CASE = {"id":"museum-diamond","title":"The Missing Diamond","briefing":"Tonight's gala at the Aldermere Museum ended with the Vesper Star — a 40-carat blue diamond on loan for the season — gone from its case. Five people were on the premises when the lights flickered in the east wing. One of them is not who they say they are.","startingFocus":12,"costs":{"unlockEvidence":2,"backgroundCheck":3,"wrongAccusation":3},"suspects":[{"id":"grace_marlowe","name":"Grace Marlowe","role":"Museum Curator","persona":"Poised and precise, chooses her words like she's citing a catalog entry. Protective of the museum's reputation and quietly mortified by any suggestion she was careless. Formal, a little clipped when defensive, warms slightly when talking about the collection itself.","facts":{"timeline":[{"id":"gm_t1","text":"The gala opened at seven. I did a final walkthrough of the east wing myself just after seven-forty, everything was in order.","isLie":false},{"id":"gm_t2","text":"At nine-ten I went back to check on the case before closing remarks and found it empty. I sealed the wing and called security immediately.","isLie":false}],"motive":[{"id":"gm_m1","text":"The Vesper Star was on loan — if anything, its disappearance is a disaster for this museum's insurance and our lending relationships for years to come. I have every reason to want it found, none to want it gone.","isLie":false},{"id":"gm_m2","text":"I fought hard to bring that piece here. I don't lose things I fight for.","isLie":false}],"relationships":[{"id":"gm_r1","text":"I hired Dana Whitfield three weeks ago through a conservation placement agency. Strong references, remote interview — we're short-staffed after the renovation, I didn't have the luxury of being precious about it.","isLie":false},{"id":"gm_r2","text":"Marcus Foley has wanted that diamond in his own collection for years. I blocked his acquisition bid myself last spring. He hasn't let me forget it.","isLie":false}],"alibi":[{"id":"gm_a1","text":"From about a quarter to nine until five past, I was in my office going over the insurance paperwork for the loan. Alone, unfortunately for how this looks.","isLie":false},{"id":"gm_a2","text":"There's a hallway camera outside my office. If I'd left, it would show it.","isLie":false}],"evidenceReactions":[{"id":"gm_e_maintenance_log","evidenceId":"maintenance_log","text":"...I disabled sensor four myself at half past six, to get the new display mount installed without setting it off all evening. I meant to re-enable it. I should have logged it. That's on me, not on anyone else.","isLie":false}]},"backgroundCheck":{"flagged":false,"text":"Fifteen years with the museum, spotless record. One internal note: repeatedly cited for over-cautious insurance protocols on loaned pieces — if anything, she errs toward paranoid."},"initialLie":{"id":"gm_lie_sensors","text":"Every sensor in that corridor was live and working all night, I'd stake my job on it.","contradictedByEvidenceId":"maintenance_log"}},{"id":"owen_castell","name":"Owen Castell","role":"Head of Security","persona":"Gruff, clipped sentences, treats every question about his team's performance as a personal attack. Proud of a clean record he's about to have to complicate. Warms up only when talking about protocol and procedure in the abstract.","facts":{"timeline":[{"id":"oc_t1","text":"Routine sweep of the vault corridor logged clear at seven forty-two. Standard rotation, nothing flagged.","isLie":false},{"id":"oc_t2","text":"Vault alarm tripped silent at nine-oh-three — no audible alert, just a log entry. That's normal for a case-weight sensor, it doesn't scream the building down.","isLie":false}],"motive":[{"id":"oc_m1","text":"I've run this floor's security for six years without an incident. Whatever happened tonight happened on my watch. That's not a motive, that's just going to be a bad quarter for me.","isLie":false}],"relationships":[{"id":"oc_r1","text":"I run background checks on every gala staffer and vendor myself, no exceptions. Dana Whitfield's paperwork came back clean when I checked it three weeks ago.","isLie":false},{"id":"oc_r2","text":"Marcus Foley's been on my radar for years, not for anything criminal — he just likes wandering into the wings he's not supposed to be in. Museum charm, I call it.","isLie":false}],"alibi":[{"id":"oc_a1","text":"I was in the security office the whole time, eight-forty to nine-ten, eyes on the feeds.","isLie":false}],"evidenceReactions":[{"id":"oc_e_camera_outage","evidenceId":"camera_outage_report","text":"...Camera seven dropped for fourteen minutes during the power blip. Half the east wing flickered that night, I logged it as a building issue and moved on. I should have flagged the gap and had someone physically walk the corridor. That's a mistake I'll own.","isLie":false}]},"backgroundCheck":{"flagged":false,"text":"Licensed, bonded, no red flags. One internal reprimand two years ago for a late shift-log filing — unrelated to tonight."},"initialLie":{"id":"oc_lie_feeds","text":"I had eyes on every camera feed personally, all night, zero blind spots. Nothing got past this office.","contradictedByEvidenceId":"camera_outage_report"}},{"id":"priya_nandan","name":"Priya Nandan","role":"Gala Patron & Board Donor","persona":"Warm and social on the surface, sharp underneath, used to being the most important person in any room she funds. Mentions her donations more than strictly necessary. Gets guarded, not hostile, when personal questions come up.","facts":{"timeline":[{"id":"pn_t1","text":"I was mingling most of the night — this gala only happens because people like me keep showing up and writing checks, so I make a point of being visible.","isLie":false}],"motive":[{"id":"pn_m1","text":"I've funded half the acquisitions budget for that wing over the last three years. I have absolutely no reason to want to see it robbed.","isLie":false}],"relationships":[{"id":"pn_r1","text":"Marcus Foley and I have gone head to head at auction more than once. It's competitive, not personal — though he takes it a bit more personally than I do.","isLie":false},{"id":"pn_r2","text":"I don't know the new conservator at all. Never met her before tonight, just saw her name on the gala program.","isLie":false}],"alibi":[{"id":"pn_a1","text":"I was near the string quartet basically all evening. Ask anyone, I was impossible to miss in this dress.","isLie":false}],"evidenceReactions":[{"id":"pn_e_coat_check","evidenceId":"coat_check_log","text":"...Fine. I stepped out to the coat check hallway for about ten minutes to take a phone call I didn't want overheard. It was personal, a family matter, nothing to do with any of this. I'd rather not say more than that.","isLie":false}]},"backgroundCheck":{"flagged":false,"text":"Donor and board records in order, verified annually by the museum's own finance committee. Nothing irregular."},"initialLie":{"id":"pn_lie_floor","text":"I never once left the gala floor all night, I was right there the entire time.","contradictedByEvidenceId":"coat_check_log"}},{"id":"marcus_foley","name":"Marcus Foley","role":"Private Gem Collector","persona":"Smooth, name-drops his collection like small talk, tries to charm his way past uncomfortable questions with a joke. Underneath it, genuinely stung about losing the Vesper Star acquisition and doesn't hide his opinions about the museum's judgment.","facts":{"timeline":[{"id":"mf_t1","text":"I'll admit I spent a good part of the evening near the east wing. Once you've seen that diamond up close, it's hard to stay away.","isLie":false}],"motive":[{"id":"mf_m1","text":"I wanted that stone for my collection, everyone here knows it. Grace outbid me, fair and square, if you can call museum politics fair. I won't pretend that didn't sting.","isLie":false}],"relationships":[{"id":"mf_r1","text":"Priya Nandan and I have crossed paths at every major auction for a decade. She usually wins. I usually sulk about it for a week.","isLie":false},{"id":"mf_r2","text":"I don't know the museum's staff personally, I deal with the board, not the conservation department.","isLie":false}],"alibi":[{"id":"mf_a1","text":"I was talking with a group of other guests near the entrance from eight-thirty onward. Ask around, someone will remember.","isLie":true}],"evidenceReactions":[{"id":"mf_e_valet_log","evidenceId":"valet_log","text":"...Alright. I didn't leave at eight-thirty. I was in the east corridor hoping for one more look at the case before it closed for the night. I know how that sounds. I didn't touch anything, I just wanted to look.","isLie":false}]},"backgroundCheck":{"flagged":true,"text":"A civil dispute over a contested acquisition, filed three years ago by a rival collector, settled out of court. No criminal record."},"initialLie":{"id":"mf_lie_left","text":"I left the gala around eight-thirty, well before any of this happened. Ask the valet.","contradictedByEvidenceId":"valet_log"}},{"id":"dana_whitfield","name":"Dana Whitfield","role":"Junior Conservator","persona":"Quiet, competent, a little too eager to be helpful. Gives detailed, confident answers about conservation technique but goes vague and short whenever the conversation turns to her own history — not evasive exactly, just deflecting, like she's redirecting a conversation she's had to redirect before.","facts":{"timeline":[{"id":"dw_t1","text":"I've mostly been in the conservation lab this week, getting ready for the loan's condition report. Tonight I was mostly keeping to myself, this isn't really my crowd yet.","isLie":false}],"motive":[{"id":"dw_m1","text":"I just started three weeks ago, I'm still learning where everything is. I don't think I'm anyone's first thought for something like this.","isLie":false}],"relationships":[{"id":"dw_r1","text":"I did my interview and paperwork remotely — this is actually the first time I've met most of the staff in person.","isLie":false},{"id":"dw_r2","text":"I'd rather focus on the work than my resume, if it's all the same to you.","isLie":false}],"alibi":[{"id":"dw_a1","text":"I told myself I'd finish a condition report tonight instead of mingling, so I was in the lab, on and off, for most of the evening.","isLie":true}],"evidenceReactions":[{"id":"dw_e_keycard_log","evidenceId":"keycard_log","text":"...That's my badge, yes. I stepped into the corridor for a minute, I thought I heard something odd near the case and wanted to check it wasn't a display fault. I didn't see anything.","isLie":false}]},"backgroundCheck":{"flagged":true,"text":"No professional registry lists a conservator named Dana Whitfield matching this employment history prior to three weeks ago. The prior workplaces listed on the original hiring paperwork could not be independently verified."},"initialLie":{"id":"dw_lie_lab","text":"I was in the conservation lab the whole window between eight-forty and nine-ten, finishing a report.","contradictedByEvidenceId":"keycard_log"}}],"evidence":[{"id":"maintenance_log","suspectId":"grace_marlowe","label":"Facilities maintenance log","description":"Sensor four on the east vault corridor was manually disabled at 6:30 PM for a display mount installation and was never re-enabled before the gala's end.","unlockCost":2},{"id":"camera_outage_report","suspectId":"owen_castell","label":"Security camera outage report","description":"Corridor camera seven went dark for fourteen minutes, from 8:50 to 9:04 PM, coinciding with a reported power fluctuation in the east wing.","unlockCost":2},{"id":"coat_check_log","suspectId":"priya_nandan","label":"Coat check hallway log","description":"A guest matching Priya Nandan's description was seen in the coat check hallway, away from the main gala floor, between 8:52 and 9:02 PM.","unlockCost":2},{"id":"valet_log","suspectId":"marcus_foley","label":"Valet retrieval log","description":"Marcus Foley's car was not retrieved from valet until 9:20 PM, well after he claimed to have already left the gala.","unlockCost":2},{"id":"keycard_log","suspectId":"dana_whitfield","label":"Keycard access log","description":"A staff keycard badge registered entry to the east vault corridor door at 8:51 PM, during the exact window the corridor camera was dark.","unlockCost":2}],"timeline":[{"time":"7:00 PM","type":"confirmed","text":"The gala opens; guests begin arriving in the main hall."},{"time":"7:42 PM","type":"confirmed","text":"Routine security sweep of the east vault corridor logged clear."},{"time":"8:15 PM","type":"confirmed","text":"The Vesper Star is confirmed in its case during a guard rotation check."},{"time":"8:45 PM","type":"claimed","suspectId":"grace_marlowe","text":"Grace Marlowe says she was reviewing insurance paperwork in her office."},{"time":"8:30 PM","type":"claimed","suspectId":"marcus_foley","text":"Marcus Foley says he had already left the gala by this point."},{"time":"8:40 PM","type":"claimed","suspectId":"dana_whitfield","text":"Dana Whitfield says she was in the conservation lab finishing a report."},{"time":"8:40 PM","type":"claimed","suspectId":"owen_castell","text":"Owen Castell says he was personally watching every camera feed, no gaps."},{"time":"8:50 PM","type":"confirmed","text":"A brief power fluctuation is reported in the east wing; corridor camera seven goes dark."},{"time":"8:51 PM","type":"confirmed","text":"A staff keycard badge registers entry to the east vault corridor door."},{"time":"8:52 PM","type":"claimed","suspectId":"priya_nandan","text":"Priya Nandan says she never left the main gala floor all night."},{"time":"9:03 PM","type":"confirmed","text":"The vault's case-weight alarm trips silently — no audible alert."},{"time":"9:10 PM","type":"confirmed","text":"Grace Marlowe's final walkthrough finds the case empty; the wing is sealed."}],"solution":{"culpritId":"dana_whitfield","narrative":"\"Dana Whitfield\" is not the name on any real conservator's degree. The woman behind it is Elena Voss, a former assistant curator at the Aldermere who was quietly fired and blacklisted three years ago after being framed for a minor theft she didn't commit — a case that was never solved and a name that never got cleared. When Grace's understaffed department posted a remote conservation opening, Elena saw a way back in: a stolen identity good enough to survive a standard background check, but not a real one.\n\nOnce inside, she spent three weeks learning the building and quietly building a convincing replica of the Vesper Star in the conservation lab, under cover of her actual, legitimate conservation work. The gala night gave her a real target of opportunity: Grace's unlogged, disabled sensor on the east corridor and a building-wide power flicker that took camera seven down for fourteen minutes were lucky breaks, not her doing — but she recognized the gap the instant it opened. At 8:51 PM she used her own legitimate staff badge to slip into the corridor, swapped the Vesper Star for the replica she'd built, and was back in the lab well before anyone thought to look for her.\n\nIt wasn't a heist crew or a smash-and-grab. It was patience, a fake résumé good enough to pass a first glance, and someone the room had already decided to stop watching."}};

const SYSTEM_PROMPT = `You author a brand-new detective mystery "case file" for a game called
Detective Daily, as a single JSON object. You are the Truth Engine author for
this case: everything you write becomes fixed, immutable ground truth that a
separate game engine will enforce -- you are not writing dialogue or prose
for a player to read directly, you are writing structured facts.

FAIRNESS RULES (hard requirements, not stylistic suggestions):
- Invent a new setting, victim/incident, and 5 suspects each time. Do not
  reuse the sample case's setting, names, or plot.
- The culprit must have an ordinary name and role like every other suspect --
  never a name, title, or description that would tip off a player before
  they've earned the information.
- Exactly one suspect is the culprit, referenced by solution.culpritId.
- Every suspect needs at least one entry in every facts category (timeline,
  motive, relationships, alibi) -- most suspects should have an innocent
  reason for their evasions or lies, not just the culprit.
- Every suspect has exactly one piece of evidence scoped to them
  (evidence[].suspectId), and most suspects' background checks come back
  clean -- flag at most 1-2 as suspicious, and at least one of those
  should be a red herring, not the actual culprit.
- Each suspect may have an "initialLie" (their opening false claim in an
  interview) with a "contradictedByEvidenceId" pointing at a real evidence
  id. The lie should be something a person might plausibly conceal that
  ISN'T necessarily proof of the crime itself (only the true culprit's lie
  should actually implicate them once combined with their background
  check) -- innocent suspects' lies should turn out to be embarrassing or
  irrelevant to the crime, not incriminating.
- timeline mixes "confirmed" entries (verified facts/logs, never naming who
  did a suspicious act before it's earned -- describe the raw event only)
  and "claimed" entries (a named suspect's own alibi statement, which may
  later be shown false).
- solution.narrative is a full explanation of how and why the culprit did
  it, written as prose (2-4 paragraphs), consistent with every fact and
  piece of evidence you wrote elsewhere in the case.
- Keep tone consistent with a casual mobile mystery game: intriguing, not
  graphic. No lethal violence description -- injury/peril can be implied
  and survived, not depicted.

SCHEMA -- return ONLY a single JSON object with exactly this shape (no
markdown fences, no commentary, no trailing text):

{
  "title": string,
  "briefing": string (2-4 sentences setting up the mystery for the player),
  "startingFocus": number (use 12),
  "costs": { "unlockEvidence": number, "backgroundCheck": number, "wrongAccusation": number } (use 2, 3, 3),
  "suspects": [
    {
      "id": string (snake_case, unique within this case),
      "name": string,
      "role": string,
      "persona": string (voice/tone notes for an actor playing this character),
      "facts": {
        "timeline": [{ "id": string, "text": string, "isLie": boolean }],
        "motive": [{ "id": string, "text": string, "isLie": boolean }],
        "relationships": [{ "id": string, "text": string, "isLie": boolean }],
        "alibi": [{ "id": string, "text": string, "isLie": boolean }],
        "evidenceReactions": [{ "id": string, "evidenceId": string, "text": string, "isLie": boolean }]
      },
      "backgroundCheck": { "flagged": boolean, "text": string },
      "initialLie": { "id": string, "text": string, "contradictedByEvidenceId": string } (optional)
    }
  ],
  "evidence": [
    { "id": string, "suspectId": string, "label": string, "description": string, "unlockCost": number (use 2) }
  ],
  "timeline": [
    { "time": string, "type": "confirmed" | "claimed", "text": string, "suspectId": string (required only when type is "claimed") }
  ],
  "solution": { "culpritId": string, "narrative": string }
}

Here is one real, already-shipped case as a structural reference for shape,
tone, and level of detail (do NOT reuse its content):

${JSON.stringify(EXAMPLE_CASE)}`;

interface ValidationResult {
  ok: boolean;
  errors: string[];
}

function validateCase(data: unknown): ValidationResult {
  const errors: string[] = [];
  const isObj = (v: unknown): v is Record<string, unknown> =>
    typeof v === "object" && v !== null && !Array.isArray(v);

  if (!isObj(data)) {
    return { ok: false, errors: ["top-level value is not a JSON object"] };
  }

  for (const field of ["title", "briefing"]) {
    if (typeof data[field] !== "string" || !(data[field] as string).trim()) {
      errors.push(`missing or empty string field: ${field}`);
    }
  }
  if (typeof data.startingFocus !== "number") errors.push("startingFocus must be a number");

  const costs = data.costs;
  if (!isObj(costs) || typeof costs.unlockEvidence !== "number" || typeof costs.backgroundCheck !== "number" ||
      typeof costs.wrongAccusation !== "number") {
    errors.push("costs must have numeric unlockEvidence, backgroundCheck, wrongAccusation");
  }

  const suspects = data.suspects;
  if (!Array.isArray(suspects) || suspects.length < 4) {
    errors.push("suspects must be an array of at least 4 entries");
    return { ok: false, errors };
  }

  const suspectIds = new Set<string>();
  const evidenceIds = new Set<string>();
  const evidence = data.evidence;
  if (!Array.isArray(evidence) || evidence.length === 0) {
    errors.push("evidence must be a non-empty array");
  } else {
    for (const e of evidence) {
      if (!isObj(e) || typeof e.id !== "string" || typeof e.suspectId !== "string" ||
          typeof e.label !== "string" || typeof e.description !== "string") {
        errors.push("each evidence item needs id, suspectId, label, description");
        continue;
      }
      evidenceIds.add(e.id);
    }
  }

  const categories = ["timeline", "motive", "relationships", "alibi"] as const;
  for (const s of suspects) {
    if (!isObj(s) || typeof s.id !== "string" || typeof s.name !== "string" ||
        typeof s.role !== "string" || typeof s.persona !== "string") {
      errors.push("each suspect needs id, name, role, persona");
      continue;
    }
    suspectIds.add(s.id);

    const facts = s.facts;
    if (!isObj(facts)) {
      errors.push(`suspect ${s.id}: missing facts object`);
      continue;
    }
    for (const cat of categories) {
      const list = facts[cat];
      if (!Array.isArray(list) || list.length === 0) {
        errors.push(`suspect ${s.id}: facts.${cat} must be a non-empty array`);
      }
    }
    if (!Array.isArray(facts.evidenceReactions)) {
      errors.push(`suspect ${s.id}: facts.evidenceReactions must be an array`);
    }

    const bg = s.backgroundCheck;
    if (!isObj(bg) || typeof bg.flagged !== "boolean" || typeof bg.text !== "string") {
      errors.push(`suspect ${s.id}: backgroundCheck needs flagged (boolean) and text (string)`);
    }

    if (s.initialLie !== undefined) {
      const lie = s.initialLie;
      if (!isObj(lie) || typeof lie.text !== "string" || typeof lie.contradictedByEvidenceId !== "string") {
        errors.push(`suspect ${s.id}: initialLie needs text and contradictedByEvidenceId`);
      } else if (!evidenceIds.has(lie.contradictedByEvidenceId)) {
        errors.push(`suspect ${s.id}: initialLie.contradictedByEvidenceId "${lie.contradictedByEvidenceId}" does not match any evidence id`);
      }
    }
  }

  // Cross-reference evidence -> suspects now that suspectIds is populated.
  if (Array.isArray(evidence)) {
    for (const e of evidence) {
      if (isObj(e) && typeof e.suspectId === "string" && !suspectIds.has(e.suspectId)) {
        errors.push(`evidence "${e.id}": suspectId "${e.suspectId}" does not match any suspect`);
      }
    }
  }

  const timeline = data.timeline;
  if (!Array.isArray(timeline) || timeline.length === 0) {
    errors.push("timeline must be a non-empty array");
  } else {
    for (const t of timeline) {
      if (!isObj(t) || typeof t.time !== "string" || typeof t.text !== "string" ||
          (t.type !== "confirmed" && t.type !== "claimed")) {
        errors.push("each timeline entry needs time, text, and type of confirmed|claimed");
        continue;
      }
      if (t.type === "claimed" && (typeof t.suspectId !== "string" || !suspectIds.has(t.suspectId))) {
        errors.push(`claimed timeline entry has missing/invalid suspectId: ${JSON.stringify(t)}`);
      }
    }
  }

  const solution = data.solution;
  if (!isObj(solution) || typeof solution.culpritId !== "string" || typeof solution.narrative !== "string" ||
      !solution.narrative.trim()) {
    errors.push("solution must have culpritId and a non-empty narrative");
  } else if (!suspectIds.has(solution.culpritId)) {
    errors.push(`solution.culpritId "${solution.culpritId}" does not match any suspect id`);
  }

  return { ok: errors.length === 0, errors };
}

function extractJson(text: string): unknown {
  const trimmed = text.trim().replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
  return JSON.parse(trimmed);
}

async function callGemini(apiKey: string, userMessage: string): Promise<string> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: "user", parts: [{ text: userMessage }] }],
      generationConfig: {
        maxOutputTokens: 8000,
        responseMimeType: "application/json",
      },
    }),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`gemini_upstream_error: ${response.status} ${body}`);
  }
  const json = await response.json();
  const text = json.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("empty_gemini_response");
  return text as string;
}

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!geminiApiKey || !supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  let prompt = "Author one brand-new case now, following the schema and rules exactly.";
  let lastErrors: string[] = [];
  let parsed: Record<string, unknown> | null = null;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    let raw: string;
    try {
      raw = await callGemini(geminiApiKey, prompt);
    } catch (err) {
      console.error("Gemini call failed:", err);
      return jsonResponse(
        { error: "generation_failed", detail: "upstream_error", message: String((err as Error)?.message ?? err) },
        502,
      );
    }

    let candidate: unknown;
    try {
      candidate = extractJson(raw);
    } catch {
      lastErrors = ["response was not valid JSON"];
      prompt = `Your previous response was not valid JSON (parse failed). Return ONLY the JSON object, no markdown fences, no commentary. Author one brand-new case now.`;
      continue;
    }

    const result = validateCase(candidate);
    if (result.ok) {
      parsed = candidate as Record<string, unknown>;
      break;
    }
    lastErrors = result.errors;
    prompt = `Your previous case had validation errors:\n${result.errors.map((e) => `- ${e}`).join("\n")}\n\nFix these and return the corrected, complete case JSON. Return ONLY the JSON object.`;
  }

  if (!parsed) {
    console.error("Case generation validation failed after retries:", lastErrors);
    return jsonResponse({ error: "generation_failed", detail: "validation_failed", errors: lastErrors }, 502);
  }

  // Server-controlled id -- never trust the model for global uniqueness.
  const id = `ai-${crypto.randomUUID()}`;
  const row = {
    id,
    title: parsed.title,
    briefing: parsed.briefing,
    starting_focus: parsed.startingFocus,
    costs: parsed.costs,
    suspects: parsed.suspects,
    evidence: parsed.evidence,
    timeline: parsed.timeline,
    solution: parsed.solution,
    source: "ai_generated",
  };

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const { error: insertError } = await supabase.from("cases").insert(row);
  if (insertError) {
    console.error("cases insert error:", insertError.message);
    return jsonResponse({ error: "save_failed" }, 500);
  }

  return jsonResponse({
    ok: true,
    case: {
      id,
      title: row.title,
      briefing: row.briefing,
      startingFocus: row.starting_focus,
      costs: row.costs,
      suspects: row.suspects,
      evidence: row.evidence,
      timeline: row.timeline,
      solution: row.solution,
    },
  }, 200);
});
