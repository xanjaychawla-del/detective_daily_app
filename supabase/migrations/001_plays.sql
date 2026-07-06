-- Per-device play status for each case. No real auth exists in this
-- prototype yet, so device_id is a client-generated UUID persisted via
-- shared_preferences -- this table's RLS is intentionally permissive
-- (anon read/write) since there's no server-verifiable identity to key
-- policies off of. Known limitation, same class as the local narration
-- proxy's dev-only note: fine for a testing-phase prototype, not
-- production-hardened.
create table if not exists public.plays (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  case_id text not null references public.cases(id) on delete cascade,
  status text not null default 'unopened' check (status in ('unopened', 'in_progress', 'solved', 'gave_up')),
  updated_at timestamptz not null default now(),
  unique (device_id, case_id)
);

alter table public.plays enable row level security;

create policy "plays are publicly readable"
  on public.plays for select
  using (true);

create policy "plays are publicly insertable"
  on public.plays for insert
  with check (true);

create policy "plays are publicly updatable"
  on public.plays for update
  using (true)
  with check (true);
