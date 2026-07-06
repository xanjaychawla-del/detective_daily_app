-- Switches play-status tracking from a client-generated device_id
-- (persisted via shared_preferences, wiped on reinstall) to Supabase
-- Auth's user id, now that anonymous sign-in is enabled. This ties
-- progress to a real identity Supabase manages, which also survives
-- reinstalls and gives every row a real path to upgrade into a
-- registered account later.
--
-- Existing rows reference locally-generated device_ids that happen to
-- already be valid UUID strings, so the type change below succeeds
-- without touching the data. They won't match any real auth.uid()
-- going forward, so they're simply inert under the new RLS policies
-- rather than being deleted.
alter table public.plays rename column device_id to user_id;
alter table public.plays alter column user_id type uuid using user_id::uuid;

drop policy if exists "plays are publicly readable" on public.plays;
drop policy if exists "plays are publicly insertable" on public.plays;
drop policy if exists "plays are publicly updatable" on public.plays;

create policy "users can read their own plays"
  on public.plays for select
  using (auth.uid() = user_id);

create policy "users can insert their own plays"
  on public.plays for insert
  with check (auth.uid() = user_id);

create policy "users can update their own plays"
  on public.plays for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
