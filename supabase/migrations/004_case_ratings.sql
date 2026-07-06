-- One rating per (user, case), prompted on the case outcome screen after
-- solving or giving up. Ratings themselves carry no sensitive info, so the
-- base table is publicly readable -- this also keeps the aggregate view
-- below simple to query from the client.
create table if not exists public.case_ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  case_id text not null references public.cases (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, case_id)
);

alter table public.case_ratings enable row level security;

create policy "ratings are publicly readable"
  on public.case_ratings for select
  using (true);

create policy "users can insert their own rating"
  on public.case_ratings for insert
  with check (auth.uid() = user_id);

create policy "users can update their own rating"
  on public.case_ratings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Precomputed average + count per case, shown on the case card in the
-- Case Files list. Exposed as a normal read-only view over the REST API.
create or replace view public.case_rating_stats as
  select case_id, avg(rating)::numeric(3, 2) as avg_rating, count(*) as rating_count
  from public.case_ratings
  group by case_id;
