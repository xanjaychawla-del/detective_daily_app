-- Timeline narration is now split into per-segment audio so a player never
-- hears a suspect's claimed alibi before they've actually interviewed that
-- suspect (see generate-timeline-audio). One segment covers the always-
-- visible confirmed events; one segment per suspect covers their claims.
-- Each segment is phrased once (Gemini) and narrated once (Google TTS),
-- then cached here and stitched together client-side based on interview
-- progress -- same cache pattern as fact_narration.
create table public.timeline_segment_narration (
  id uuid primary key default gen_random_uuid(),
  case_id text not null references public.cases (id) on delete cascade,
  segment_key text not null, -- 'confirmed' or a suspect id
  phrased_text text not null,
  audio_url text not null,
  created_at timestamptz not null default now(),
  unique (case_id, segment_key)
);

alter table public.timeline_segment_narration enable row level security;

create policy "timeline segment narration is publicly readable"
  on public.timeline_segment_narration for select
  using (true);

-- Superseded by per-segment narration above.
alter table public.cases drop column timeline_audio_url;
