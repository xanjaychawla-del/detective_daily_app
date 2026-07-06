-- Case Repository: one row per case. Full Truth Engine content lives here
-- as jsonb, mirroring Case.fromJson exactly so the Flutter client can parse
-- a row straight into a Case with no reshaping.
create table if not exists public.cases (
  id text primary key,
  title text not null,
  briefing text not null,
  starting_focus int not null,
  costs jsonb not null,
  suspects jsonb not null,
  evidence jsonb not null,
  timeline jsonb not null,
  solution jsonb not null,
  source text not null default 'authored' check (source in ('authored', 'ai_generated')),
  created_at timestamptz not null default now()
);

alter table public.cases enable row level security;

-- Cases are public content -- anyone (anon) can read the list.
create policy "cases are publicly readable"
  on public.cases for select
  using (true);

-- Only the generate-case Edge Function (service role, bypasses RLS) inserts
-- rows. No anon insert/update/delete policy exists, so the anon key cannot
-- write to this table at all.
