// Reads the Evidence Board's case timeline aloud, split into independent
// segments so a player is never told a suspect's claimed alibi before
// they've actually interviewed that suspect: one "confirmed" segment
// (always safe to hear), one segment per suspect with claimed timeline
// entries, and a "pending:<comma-separated-suspect-ids>" segment that
// closes the narration with a reminder of who's still worth interviewing.
// Gemini writes the confirmed/suspect segments -- preserving every fact,
// time, and (for suspect segments) framing it clearly as that suspect's
// claim, never inventing or concluding anything; the pending reminder is
// plain deterministic text, no Gemini needed. Google Cloud TTS narrates
// whichever script was produced. Each segment is cached once per (case,
// segment) in timeline_segment_narration and stitched together client-side
// based on the player's interview progress.
//
// Secrets: GEMINI_API_KEY, GOOGLE_TTS_API_KEY
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy with --no-verify-jwt, matching the rest of this project's functions.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { INSPECTOR_VOICE, synthesizeSpeech } from "../_shared/google-tts.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MODEL = "gemini-2.5-flash";

interface TimelineEntry {
  time: string;
  type: "confirmed" | "claimed";
  text: string;
  suspectId?: string;
}

interface SuspectRow {
  id: string;
  name: string;
}

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function buildFactSheet(entries: TimelineEntry[]): string {
  return entries.map((entry) => `${entry.time}: ${entry.text}`).join("\n");
}

async function phraseConfirmed(apiKey: string, factSheet: string): Promise<string> {
  const systemPrompt =
    `You are a detective's assistant narrating the confirmed, verified events of a case timeline out loud for the player.

STRICT RULES:
- Use ONLY the events given below. Do not invent, omit, or reorder events, and do not change any times.
- Do not draw conclusions, accuse anyone, or speculate about who is responsible -- just lay out what happened.
- Write it as natural, flowing spoken narration (not a bullet list or a recitation of times), 2-5 sentences, as if briefing a detective.
- No stage directions, no headers, no quotation marks -- just the narration text itself.

The confirmed events:
"""
${factSheet}
"""`;
  return callGemini(apiKey, systemPrompt, "Narrate the confirmed events above now.");
}

async function phraseSuspectClaims(apiKey: string, suspectName: string, factSheet: string): Promise<string> {
  const systemPrompt =
    `You are a detective's assistant narrating what one suspect, ${suspectName}, told the detective during questioning, out loud for the player.

STRICT RULES:
- Use ONLY the claims given below. Do not invent, omit, or reorder claims, and do not change any times.
- This is ${suspectName}'s claim, not a verified fact -- make that clear throughout (e.g. "According to ${suspectName}..." or "${suspectName} claims..."). Never state it as established truth.
- Do not draw conclusions, accuse anyone, or speculate about whether ${suspectName} is telling the truth -- just report what they said.
- Write it as natural, flowing spoken narration (not a bullet list or a recitation of times), 1-3 sentences, as if briefing a detective.
- No stage directions, no headers, no quotation marks -- just the narration text itself.

${suspectName}'s claims:
"""
${factSheet}
"""`;
  return callGemini(apiKey, systemPrompt, `Narrate ${suspectName}'s claims above now.`);
}

// Deterministic, no Gemini needed -- just a plain list of names. Keeps the
// closing reminder cheap to regenerate for every distinct combination of
// still-uninterviewed suspects a player can reach.
function buildPendingReminder(names: string[]): string {
  if (names.length === 1) {
    return `We could get an updated timeline once we've interviewed ${names[0]}.`;
  }
  const allButLast = names.slice(0, -1).join(", ");
  const last = names[names.length - 1];
  return `We could get an updated timeline once we've interviewed ${allButLast}, and ${last}.`;
}

async function callGemini(apiKey: string, systemPrompt: string, userPrompt: string): Promise<string> {
  const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;
  const response = await fetch(geminiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: systemPrompt }] },
      contents: [{ role: "user", parts: [{ text: userPrompt }] }],
      generationConfig: { temperature: 0.6, maxOutputTokens: 400, thinkingConfig: { thinkingBudget: 0 } },
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
  const googleTtsApiKey = Deno.env.get("GOOGLE_TTS_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!geminiApiKey || !googleTtsApiKey || !supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const body = await req.json().catch(() => null);
  const caseId = body?.caseId;
  const segmentKey = body?.segmentKey;
  if (typeof caseId !== "string" || !caseId.trim() || typeof segmentKey !== "string" || !segmentKey.trim()) {
    return jsonResponse({ error: "missing_fields" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { data: existing } = await supabase
    .from("timeline_segment_narration")
    .select("phrased_text, audio_url")
    .eq("case_id", caseId)
    .eq("segment_key", segmentKey)
    .maybeSingle();

  if (existing?.audio_url) {
    return jsonResponse({ ok: true, phrasedText: existing.phrased_text, audioUrl: existing.audio_url }, 200);
  }

  const { data: caseRow, error: fetchError } = await supabase
    .from("cases")
    .select("timeline, suspects")
    .eq("id", caseId)
    .single();

  if (fetchError || !caseRow) {
    return jsonResponse({ error: "case_not_found" }, 404);
  }

  const timeline = caseRow.timeline as TimelineEntry[];
  const suspects = caseRow.suspects as SuspectRow[];

  let script: string;
  if (segmentKey.startsWith("pending:")) {
    const ids = segmentKey.slice("pending:".length).split(",").filter(Boolean);
    const nameById = new Map(suspects.map((s) => [s.id, s.name]));
    const names = ids.map((id) => nameById.get(id)).filter((n): n is string => !!n);
    if (names.length === 0) return jsonResponse({ error: "no_entries_for_segment" }, 404);
    script = buildPendingReminder(names);
  } else {
    try {
      if (segmentKey === "confirmed") {
        const entries = timeline.filter((e) => e.type === "confirmed");
        if (entries.length === 0) return jsonResponse({ error: "no_entries_for_segment" }, 404);
        script = await phraseConfirmed(geminiApiKey, buildFactSheet(entries));
      } else {
        const suspect = suspects.find((s) => s.id === segmentKey);
        const entries = timeline.filter((e) => e.type === "claimed" && e.suspectId === segmentKey);
        if (!suspect || entries.length === 0) return jsonResponse({ error: "no_entries_for_segment" }, 404);
        script = await phraseSuspectClaims(geminiApiKey, suspect.name, buildFactSheet(entries));
      }
    } catch (err) {
      console.error("Gemini phrasing failed:", (err as Error)?.message ?? err);
      return jsonResponse({ error: "phrasing_failed" }, 502);
    }
  }

  let audioBytes: Uint8Array;
  try {
    audioBytes = await synthesizeSpeech(googleTtsApiKey, script, INSPECTOR_VOICE);
  } catch (err) {
    console.error("Google TTS call failed:", (err as Error)?.message ?? err);
    return jsonResponse({ error: "tts_failed" }, 502);
  }

  const safeSegmentKey = segmentKey.replace(/[^a-zA-Z0-9_-]/g, "_");
  const path = `${caseId}-timeline-${safeSegmentKey}.mp3`;
  const { error: uploadError } = await supabase.storage
    .from("case-audio")
    .upload(path, audioBytes, { contentType: "audio/mpeg", upsert: true });
  if (uploadError) {
    console.error("Storage upload failed:", uploadError.message);
    return jsonResponse({ error: "upload_failed" }, 500);
  }

  const { data: publicUrlData } = supabase.storage.from("case-audio").getPublicUrl(path);
  const audioUrl = publicUrlData.publicUrl;

  const { error: upsertError } = await supabase
    .from("timeline_segment_narration")
    .upsert(
      { case_id: caseId, segment_key: segmentKey, phrased_text: script, audio_url: audioUrl },
      { onConflict: "case_id, segment_key" },
    );
  if (upsertError) {
    console.error("Failed to cache timeline segment narration:", upsertError.message);
  }

  return jsonResponse({ ok: true, phrasedText: script, audioUrl }, 200);
});
