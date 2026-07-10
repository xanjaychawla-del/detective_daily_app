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

function v(languageCode: string, suffix: string): GoogleVoice {
  return { languageCode, name: `${languageCode}-${suffix}` };
}

// Every suspect's dialogue is authored in English, so the narration voice
// must actually speak English fluently -- a suspect's country maps to the
// closest of Google's four English Neural2 locales, not to their own
// native-language voice (feeding English text to e.g. a French or Hindi
// voice mispronounces it badly). This is a deliberate approximation: there
// is no dedicated voice for every nationality, only an accent grouping.
// Confirmed against the live Google Cloud TTS voices:list Neural2 catalog.
type Accent = "en-IN" | "en-US" | "en-GB" | "en-AU";

const ACCENT_BY_COUNTRY: Record<string, Accent> = {
  "india": "en-IN",
  "pakistan": "en-IN",
  "bangladesh": "en-IN",
  "sri lanka": "en-IN",
  "nepal": "en-IN",
  "united states": "en-US",
  "usa": "en-US",
  "america": "en-US",
  "canada": "en-US",
  "mexico": "en-US",
  "philippines": "en-US",
  "united kingdom": "en-GB",
  "england": "en-GB",
  "scotland": "en-GB",
  "wales": "en-GB",
  "ireland": "en-GB",
  "nigeria": "en-GB",
  "south africa": "en-GB",
  "kenya": "en-GB",
  "ghana": "en-GB",
  "singapore": "en-GB",
  "australia": "en-AU",
  "new zealand": "en-AU",
};

export function accentForCountry(country: string | undefined | null): Accent {
  if (!country) return "en-US";
  return ACCENT_BY_COUNTRY[country.trim().toLowerCase()] ?? "en-US";
}

// One voice per accent+gender group is reserved for INSPECTOR_VOICES below
// (never listed here) so a suspect never sounds identical to the calling
// inspector within the same case.
const SUSPECT_VOICES: Record<Accent, { male: GoogleVoice[]; female: GoogleVoice[] }> = {
  "en-IN": {
    male: [v("en-IN", "Neural2-C")],
    female: [v("en-IN", "Neural2-A"), v("en-IN", "Neural2-D")],
  },
  "en-US": {
    male: [v("en-US", "Neural2-A"), v("en-US", "Neural2-D"), v("en-US", "Neural2-J")],
    female: [
      v("en-US", "Neural2-C"),
      v("en-US", "Neural2-E"),
      v("en-US", "Neural2-F"),
      v("en-US", "Neural2-G"),
      v("en-US", "Neural2-H"),
    ],
  },
  "en-GB": {
    male: [v("en-GB", "Neural2-B"), v("en-GB", "Neural2-D")],
    female: [
      v("en-GB", "Neural2-A"),
      v("en-GB", "Neural2-C"),
      v("en-GB", "Neural2-F"),
      v("en-GB", "Neural2-N"),
    ],
  },
  "en-AU": {
    male: [v("en-AU", "Neural2-B")],
    female: [v("en-AU", "Neural2-A"), v("en-AU", "Neural2-C")],
  },
};

export function hashSum(s: string): number {
  let sum = 0;
  for (let i = 0; i < s.length; i++) sum += s.charCodeAt(i);
  return sum;
}

// Picks a voice matching this suspect's country (accent) and sex, varying
// deterministically within that group by suspect id so two suspects who
// share a country+sex still sound different from each other.
export function pickSuspectVoice(suspectId: string, country: string | undefined, sex: string | undefined): GoogleVoice {
  const accent = accentForCountry(country);
  const group = SUSPECT_VOICES[accent];
  const pool = sex?.trim().toLowerCase() === "female" ? group.female : group.male;
  return pool[hashSum(suspectId) % pool.length];
}

// The rotating cast of inspector names used for the incoming-call briefing
// (see lib/screens/incoming_call_overlay.dart's _kInspectorNames -- keep
// both lists identical) paired one-for-one with a reserved voice so the
// same case always hears the same name+voice combo, and different names
// don't all default to the same accent (previously every case's inspector
// used a single hardcoded en-IN voice regardless of which name was picked).
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

const INSPECTOR_VOICES: GoogleVoice[] = [
  v("en-US", "Neural2-I"), // Reyes
  v("en-GB", "Neural2-O"), // Okafor
  v("en-AU", "Neural2-D"), // Chen
  v("en-GB", "Neural2-O"), // Whitfield
  v("en-US", "Neural2-I"), // Alvarez
  v("en-GB", "Neural2-O"), // Novak
  v("en-AU", "Neural2-D"), // Sato
  v("en-US", "Neural2-I"), // Bianchi
  v("en-GB", "Neural2-O"), // Kowalski
  v("en-IN", "Neural2-B"), // Adebayo
];

function pickInspectorIndex(caseId: string): number {
  return hashSum(caseId) % INSPECTOR_NAMES.length;
}

export function pickInspectorName(caseId: string): string {
  return INSPECTOR_NAMES[pickInspectorIndex(caseId)];
}

export function pickInspectorVoice(caseId: string): GoogleVoice {
  return INSPECTOR_VOICES[pickInspectorIndex(caseId)];
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
