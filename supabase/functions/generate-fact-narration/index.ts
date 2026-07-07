// Phrases ONE suspect fact via Gemini and caches it permanently per
// (case, fact) -- every player gets the identical line, phrased exactly
// once, not once per play. See migration 011 for why this replaces the
// old narrate function's live, history-aware phrasing.
//
// Audio synthesis (Polly) is parked for now -- the client speaks the
// returned text via on-device TTS instead, deliberately mechanical
// sounding until there's enough traffic to justify the cloud-voice cost.
// fact_narration.audio_url stays nullable and unused here; wiring Polly
// back in later just means filling it in alongside phrased_text below.
//
// Secrets: GEMINI_API_KEY
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy with --no-verify-jwt, matching the rest of this project's functions.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MODEL = "gemini-2.5-flash";

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

async function phraseWithGemini(
  apiKey: string,
  { suspectName, persona, fact, category }: { suspectName: string; persona: string; fact: string; category: string },
): Promise<string> {
  const systemPrompt =
    `You are voicing ONE character, ${suspectName}, who is being interviewed as a suspect in a detective mystery game.

Persona: ${persona || "A person being questioned in a mystery investigation."}

STRICT RULES:
- Phrase ONLY the single fact given below, in character. Do not invent any new facts, names, times, evidence, or details that are not present in the fact.
- Do not add new claims about guilt or innocence, and do not confirm or deny being responsible for anything -- that is not something this character would know to signal one way or the other.
- Keep it to 1-4 sentences of natural spoken dialogue. No stage directions, no quotation marks, no narration -- just what the character says out loud.

The fact to phrase (do not add to or deviate from its content):
"""
${fact.trim()}
"""`;

  const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;
  const response = await fetch(geminiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: systemPrompt }] },
      contents: [{ role: "user", parts: [{ text: `Category: ${category}. Say the fact above, in character, now.` }] }],
      generationConfig: { temperature: 0.7, maxOutputTokens: 200, thinkingConfig: { thinkingBudget: 0 } },
    }),
  });
  const raw = await response.text();
  if (!response.ok) throw new Error(`gemini_upstream_error: ${response.status} ${raw}`);
  const outer = JSON.parse(raw);
  const text = outer.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("empty_gemini_text");
  return (text as string).trim();
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

  const body = await req.json().catch(() => null);
  const caseId = body?.caseId;
  const suspectId = body?.suspectId;
  const factId = body?.factId;
  const factText = body?.factText;
  const category = body?.category;
  const persona = body?.persona;
  const suspectName = body?.suspectName;

  if (
    typeof caseId !== "string" || typeof suspectId !== "string" || typeof factId !== "string" ||
    typeof factText !== "string" || !factText.trim() || typeof suspectName !== "string"
  ) {
    return jsonResponse({ error: "missing_fields" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { data: existing } = await supabase
    .from("fact_narration")
    .select("phrased_text")
    .eq("case_id", caseId)
    .eq("fact_id", factId)
    .maybeSingle();

  if (existing) {
    return jsonResponse({ ok: true, phrasedText: existing.phrased_text }, 200);
  }

  let phrasedText: string;
  try {
    phrasedText = await phraseWithGemini(geminiApiKey, {
      suspectName,
      persona: typeof persona === "string" ? persona : "",
      fact: factText,
      category: typeof category === "string" ? category : "general",
    });
  } catch (err) {
    console.error("Gemini phrasing failed:", (err as Error)?.message ?? err);
    return jsonResponse({ error: "phrasing_failed" }, 502);
  }

  const { error: insertError } = await supabase
    .from("fact_narration")
    .insert({ case_id: caseId, suspect_id: suspectId, fact_id: factId, phrased_text: phrasedText });
  if (insertError) {
    console.error("Failed to cache fact narration:", insertError.message);
    // Not fatal -- still return what was generated for this call.
  }

  return jsonResponse({ ok: true, phrasedText }, 200);
});
