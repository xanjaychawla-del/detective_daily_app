-- Supports the guest/Free/Lite/Premium tier system:
--   * A profiles row only exists for a *registered* user (guests never get
--     one) -- its presence is the signal that someone has converted from an
--     anonymous guest to a real account, and `tier` drives their limits.
--   * plays.opened_at records the moment a case was first started
--     (transition to in_progress), separate from updated_at which also
--     moves on solve/give-up. Needed to count "new cases opened today" for
--     the Free tier's daily cap without conflating it with case completion
--     time.

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tier text not null default 'free' check (tier in ('free', 'lite', 'premium')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "users can read their own profile"
  on public.profiles for select
  using (auth.uid() = user_id);

create policy "users can insert their own profile"
  on public.profiles for insert
  with check (auth.uid() = user_id);

create policy "users can update their own profile"
  on public.profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.plays add column opened_at timestamptz;
update public.plays set opened_at = updated_at where opened_at is null;

create or replace function public.set_plays_opened_at()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    new.opened_at := now();
  else
    new.opened_at := old.opened_at;
  end if;
  return new;
end;
$$ language plpgsql;

create trigger plays_set_opened_at
  before insert or update on public.plays
  for each row execute function public.set_plays_opened_at();
