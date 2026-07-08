// Reads the Evidence Board's case timeline aloud, exactly as already
// written (no new AI writing involved -- the timeline text is static
// Truth Engine data, not phrased). Cached once per case on
// cases.timeline_audio_url and reused by every player, same pattern as
// generate-briefing-audio.
//
// Secrets: GOOGLE_TTS_API_KEY
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy with --no-verify-jwt, matching the rest of this project's functions.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { INSPECTOR_VOICE, synthesizeSpeech } from "../_shared/google-tts.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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

function buildScript(timeline: TimelineEntry[], suspects: SuspectRow[]): string {
  const nameById = new Map(suspects.map((s) => [s.id, s.name]));
  const lines = timeline.map((entry) => {
    if (entry.type === "confirmed") {
      return `At ${entry.time}, ${entry.text}`;
    }
    const name = (entry.suspectId && nameById.get(entry.suspectId)) || "one witness";
    return `At ${entry.time}, according to ${name}, ${entry.text}`;
  });
  return `Here's what we know about the timeline of events. ${lines.join(" ")} That's everything on record so far.`;
}

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const googleTtsApiKey = Deno.env.get("GOOGLE_TTS_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!googleTtsApiKey || !supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const body = await req.json().catch(() => null);
  const caseId = body?.caseId;
  if (typeof caseId !== "string" || !caseId.trim()) {
    return jsonResponse({ error: "missing_case_id" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { data: caseRow, error: fetchError } = await supabase
    .from("cases")
    .select("timeline, suspects, timeline_audio_url")
    .eq("id", caseId)
    .single();

  if (fetchError || !caseRow) {
    return jsonResponse({ error: "case_not_found" }, 404);
  }

  if (caseRow.timeline_audio_url) {
    return jsonResponse({ ok: true, audioUrl: caseRow.timeline_audio_url }, 200);
  }

  const script = buildScript(caseRow.timeline as TimelineEntry[], caseRow.suspects as SuspectRow[]);

  let audioBytes: Uint8Array;
  try {
    audioBytes = await synthesizeSpeech(googleTtsApiKey, script, INSPECTOR_VOICE);
  } catch (err) {
    console.error("Google TTS call failed:", (err as Error)?.message ?? err);
    return jsonResponse({ error: "tts_failed" }, 502);
  }

  const path = `${caseId}-timeline.mp3`;
  const { error: uploadError } = await supabase.storage
    .from("case-audio")
    .upload(path, audioBytes, { contentType: "audio/mpeg", upsert: true });
  if (uploadError) {
    console.error("Storage upload failed:", uploadError.message);
    return jsonResponse({ error: "upload_failed" }, 500);
  }

  const { data: publicUrlData } = supabase.storage.from("case-audio").getPublicUrl(path);
  const audioUrl = publicUrlData.publicUrl;

  const { error: updateError } = await supabase
    .from("cases")
    .update({ timeline_audio_url: audioUrl })
    .eq("id", caseId);
  if (updateError) {
    console.error("Failed to cache timeline audio URL:", updateError.message);
  }

  return jsonResponse({ ok: true, audioUrl }, 200);
});
