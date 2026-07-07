-- Suspect dialogue lines are phrased once (Gemini) and narrated once
-- (Polly), then cached here per (case, fact) -- every player hears the
-- same line, and repeat plays never re-pay for generation. This trades
-- away the previous "phrasing varies with conversation history" behavior
-- for consistency and near-zero ongoing cost.
create table public.fact_narration (
  id uuid primary key default gen_random_uuid(),
  case_id text not null references public.cases (id) on delete cascade,
  suspect_id text not null,
  fact_id text not null,
  phrased_text text not null,
  audio_url text not null,
  created_at timestamptz not null default now(),
  unique (case_id, fact_id)
);

alter table public.fact_narration enable row level security;

create policy "fact narration is publicly readable"
  on public.fact_narration for select
  using (true);

-- The Evidence Board's timeline is static per case (unlike dialogue, it's
-- never AI-phrased), so its narration caches the same way the incoming
-- call briefing does: one synthesis per case, reused by everyone.
alter table public.cases add column timeline_audio_url text;
