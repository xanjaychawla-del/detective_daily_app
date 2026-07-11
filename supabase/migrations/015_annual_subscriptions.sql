-- Adds annual subscription options alongside the existing monthly ones --
-- each tier is sold as two independent Play Console products (e.g.
-- lite_monthly / lite_annual) rather than multiple base plans on one
-- product, keeping every existing lookup (by product_id) unchanged.

do $$
declare
  v_constraint_name text;
begin
  select conname into v_constraint_name
  from pg_constraint
  where conrelid = 'public.subscriptions'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%product_id%';

  if v_constraint_name is not null then
    execute format('alter table public.subscriptions drop constraint %I', v_constraint_name);
  end if;
end $$;

alter table public.subscriptions
  add constraint subscriptions_product_id_check
  check (product_id in ('lite_monthly', 'lite_annual', 'premium_monthly', 'premium_annual'));

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
    when p_status in ('active', 'in_grace_period', 'on_hold')
      and p_product_id in ('lite_monthly', 'lite_annual') then 'lite'
    when p_status in ('active', 'in_grace_period', 'on_hold')
      and p_product_id in ('premium_monthly', 'premium_annual') then 'premium'
    else 'free'
  end;

  insert into public.profiles (user_id, tier)
  values (p_user_id, v_tier)
  on conflict (user_id) do update set tier = excluded.tier;
end;
$$;
