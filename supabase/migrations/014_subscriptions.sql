-- Google Play Billing (monthly subscriptions, Lite/Premium). Purchase
-- tokens and renewal state live here, separate from `profiles`, because
-- this table must never be client-writable -- only verify-subscription-
-- purchase and play-rtdn-webhook (service-role) ever touch it. profiles.tier
-- stays the single source of truth every other feature reads, kept in sync
-- via apply_subscription_state() below.

create table public.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  product_id text not null check (product_id in ('lite_monthly', 'premium_monthly')),
  purchase_token text not null,
  order_id text,
  status text not null check (
    status in ('active', 'canceled', 'in_grace_period', 'on_hold', 'paused', 'expired', 'revoked')
  ),
  auto_renewing boolean not null default true,
  expiry_time timestamptz not null,
  last_notification_type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index subscriptions_purchase_token_key on public.subscriptions (purchase_token);

alter table public.subscriptions enable row level security;

create policy "users can read their own subscription"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- Deliberately no insert/update/delete policy for authenticated users --
-- only the service-role key (used exclusively by verify-subscription-purchase
-- and play-rtdn-webhook) may write this table.

-- Single place tier is ever granted on the strength of a purchase --
-- upserts the subscription row and flips profiles.tier atomically, so both
-- edge functions call one idempotent unit instead of duplicating this logic.
create or replace function public.apply_subscription_state(
  p_user_id uuid,
  p_product_id text,
  p_purchase_token text,
  p_order_id text,
  p_status text,
  p_auto_renewing boolean,
  p_expiry_time timestamptz,
  p_notification_type text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier text;
begin
  insert into public.subscriptions (
    user_id, product_id, purchase_token, order_id, status,
    auto_renewing, expiry_time, last_notification_type, updated_at
  )
  values (
    p_user_id, p_product_id, p_purchase_token, p_order_id, p_status,
    p_auto_renewing, p_expiry_time, p_notification_type, now()
  )
  on conflict (user_id) do update set
    product_id = excluded.product_id,
    purchase_token = excluded.purchase_token,
    order_id = excluded.order_id,
    status = excluded.status,
    auto_renewing = excluded.auto_renewing,
    expiry_time = excluded.expiry_time,
    last_notification_type = excluded.last_notification_type,
    updated_at = now();

  v_tier := case
    when p_status in ('active', 'in_grace_period', 'on_hold') and p_product_id = 'lite_monthly' then 'lite'
    when p_status in ('active', 'in_grace_period', 'on_hold') and p_product_id = 'premium_monthly' then 'premium'
    else 'free'
  end;

  insert into public.profiles (user_id, tier)
  values (p_user_id, v_tier)
  on conflict (user_id) do update set tier = excluded.tier;
end;
$$;
