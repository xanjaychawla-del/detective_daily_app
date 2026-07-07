// The incoming-call briefing script is identical for every player of a
// given case (same title, briefing, and deterministically-picked inspector
// name), so it's synthesized once via Amazon Polly and cached on the case
// row + Supabase Storage rather than re-synthesized (and re-billed) on
// every play. First caller for a case pays the latency of generation;
// everyone after gets the cached URL back immediately.
//
// Polly over ElevenLabs specifically for the free tier headroom: 1M
// characters/month free for Neural voices (first 12 months) vs a few
// thousand on ElevenLabs' free tier -- comfortable margin even before
// caching, and caching means the real lifetime usage stays tiny anyway.
//
// Secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy with --no-verify-jwt, matching narrate/generate-case.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PollyClient, SynthesizeSpeechCommand } from "https://esm.sh/@aws-sdk/client-polly@3";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// "Matthew" -- a standard Polly Neural voice (US English), warm/clear,
// fits an inspector calling with case details.
const VOICE_ID = "Matthew";
const AWS_REGION = "us-east-1";

// Mirrors lib/screens/incoming_call_overlay.dart's _kInspectorNames and
// hash exactly, so the name spoken in the cached audio always matches the
// name shown on screen for the same case id. A simple char-code sum is
// used (not Dart's String.hashCode, which Deno/JS can't reproduce).
const INSPECTOR_NAMES = [
  "Reyes",
  "Okafor",
  "Chen",
  "Whitfield",
  "Alvarez",
  "Novak",
  "Sato",
  "Bianchi",
  "Kowalski",
  "Adebayo",
];

function pickInspectorName(caseId: string): string {
  let sum = 0;
  for (let i = 0; i < caseId.length; i++) sum += caseId.charCodeAt(i);
  return INSPECTOR_NAMES[sum % INSPECTOR_NAMES.length];
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

  const awsAccessKeyId = Deno.env.get("AWS_ACCESS_KEY_ID");
  const awsSecretAccessKey = Deno.env.get("AWS_SECRET_ACCESS_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!awsAccessKeyId || !awsSecretAccessKey || !supabaseUrl || !serviceRoleKey) {
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
    const polly = new PollyClient({
      region: AWS_REGION,
      credentials: { accessKeyId: awsAccessKeyId, secretAccessKey: awsSecretAccessKey },
    });
    const response = await polly.send(new SynthesizeSpeechCommand({
      Text: script,
      OutputFormat: "mp3",
      VoiceId: VOICE_ID,
      Engine: "neural",
    }));
    if (!response.AudioStream) throw new Error("empty_audio_stream");
    audioBytes = await response.AudioStream.transformToByteArray();
  } catch (err) {
    console.error("Polly call failed:", (err as Error)?.message ?? err);
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
