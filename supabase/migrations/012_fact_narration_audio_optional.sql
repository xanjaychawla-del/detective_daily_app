-- Voice narration (Polly) is parked in favor of on-device TTS for now
-- (see generate-fact-narration) -- only the Gemini-phrased text is cached
-- going forward, so audio_url can no longer be required on insert. Column
-- stays in place, ready to be filled in again if/when cloud narration is
-- switched back on.
alter table public.fact_narration alter column audio_url drop not null;
