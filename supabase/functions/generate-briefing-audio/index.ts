// The incoming-call briefing script is identical for every player of a
// given case (same title, briefing, and deterministically-picked inspector
// name), so it's synthesized once via Google Cloud TTS and cached on the
// case row + Supabase Storage rather than re-synthesized (and re-billed)
// on every play. First caller for a case pays the latency of generation;
// everyone after gets the cached URL back immediately.
//
// Secrets: GOOGLE_TTS_API_KEY
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy with --no-verify-jwt, matching narrate/generate-case.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { pickInspectorName, pickInspectorVoice, synthesizeSpeech } from "../_shared/google-tts.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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
  const inspectorName = pickInspectorName(caseId);

  const { data: caseRow, error: fetchError } = await supabase
    .from("cases")
    .select("title, briefing, briefing_audio_url")
    .eq("id", caseId)
    .single();

  if (fetchError || !caseRow) {
    return jsonResponse({ error: "case_not_found" }, 404);
  }

  if (caseRow.briefing_audio_url) {
    return jsonResponse({ ok: true, audioUrl: caseRow.briefing_audio_url, inspectorName }, 200);
  }

  const script = `This is Inspector ${inspectorName} speaking. Hello detective, I called to brief you on the case. ` +
    `${caseRow.briefing} The details are sent to your phone under unsolved cases.`;

  let audioBytes: Uint8Array;
  try {
    audioBytes = await synthesizeSpeech(googleTtsApiKey, script, pickInspectorVoice(caseId));
  } catch (err) {
    console.error("Google TTS call failed:", (err as Error)?.message ?? err);
    return jsonResponse({ error: "tts_failed" }, 502);
  }

  const path = `${caseId}.mp3`;
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
    .update({ briefing_audio_url: audioUrl })
    .eq("id", caseId);
  if (updateError) {
    console.error("Failed to cache audio URL on case row:", updateError.message);
    // Not fatal -- the audio was generated and uploaded successfully, it
    // just won't be cache-hit next time. Still return it for this call.
  }

  return jsonResponse({ ok: true, audioUrl, inspectorName }, 200);
});
