// Shared Google Cloud Text-to-Speech helper used by generate-briefing-audio,
// generate-fact-narration, and generate-timeline-audio. Auth is a plain API
// key (created in Google Cloud Console under APIs & Services > Credentials)
// passed as a query param -- simpler than the OAuth/service-account flow
// Google's client libraries default to, and sufficient for a
// server-to-server call like this one.
//
// Secret: GOOGLE_TTS_API_KEY

export interface GoogleVoice {
  languageCode: string;
  name: string;
}

// "Neural2" over the newer "Chirp3-HD" tier here specifically because
// Chirp3-HD's en-IN coverage isn't confirmed -- Neural2 has been
// generally available for en-IN for years. Revisit if Chirp3-HD adds
// solid en-IN support later.
export const INSPECTOR_VOICE: GoogleVoice = { languageCode: "en-IN", name: "en-IN-Neural2-B" };

// Mixed region/gender pool for suspects, deliberately excluding
// INSPECTOR_VOICE so no suspect ever sounds like the calling inspector.
export const SUSPECT_VOICE_POOL: GoogleVoice[] = [
  { languageCode: "en-IN", name: "en-IN-Neural2-A" },
  { languageCode: "en-IN", name: "en-IN-Neural2-C" },
  { languageCode: "en-IN", name: "en-IN-Neural2-D" },
  { languageCode: "en-US", name: "en-US-Neural2-A" },
  { languageCode: "en-US", name: "en-US-Neural2-C" },
  { languageCode: "en-US", name: "en-US-Neural2-D" },
  { languageCode: "en-US", name: "en-US-Neural2-F" },
  { languageCode: "en-GB", name: "en-GB-Neural2-B" },
];

export function pickSuspectVoice(suspectId: string): GoogleVoice {
  let sum = 0;
  for (let i = 0; i < suspectId.length; i++) sum += suspectId.charCodeAt(i);
  return SUSPECT_VOICE_POOL[sum % SUSPECT_VOICE_POOL.length];
}

export async function synthesizeSpeech(apiKey: string, text: string, voice: GoogleVoice): Promise<Uint8Array> {
  const response = await fetch(
    `https://texttospeech.googleapis.com/v1/text:synthesize?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({
        input: { text },
        voice: { languageCode: voice.languageCode, name: voice.name },
        audioConfig: { audioEncoding: "MP3" },
      }),
    },
  );
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`google_tts_upstream_error: ${response.status} ${detail}`);
  }
  const data = await response.json();
  const audioContent = data.audioContent as string | undefined;
  if (!audioContent) throw new Error("empty_audio_content");
  // Response is base64-encoded audio, not raw bytes -- decode before
  // handing it to Supabase Storage.
  const binary = atob(audioContent);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
