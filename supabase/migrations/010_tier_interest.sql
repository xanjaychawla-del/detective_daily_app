-- Tracks how many users tap "Select Lite" / "Select Premium" on the
-- registration screen, to gauge demand for tiers that aren't purchasable
-- yet. Individual rows carry a user_id so a query can dedupe if needed,
-- but only the aggregate view is meant to be read day-to-day.
create table public.tier_interest (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  tier text not null check (tier in ('lite', 'premium')),
  created_at timestamptz not null default now()
);

alter table public.tier_interest enable row level security;

create policy "users can log their own tier interest"
  on public.tier_interest for insert
  with check (auth.uid() = user_id);

-- No select policy on the base table -- individual taps aren't meant to
-- be browsable over the REST API, only this aggregate.
create or replace view public.tier_interest_stats as
  select tier, count(*) as tap_count, count(distinct user_id) as unique_users
  from public.tier_interest
  group by tier;
