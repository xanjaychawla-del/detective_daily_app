-- One-off test aid: marks 3 cases "solved" for the current dev guest
-- session so the guest 3-case cap can be verified without actually
-- playing through 3 full cases. Not idempotent/reusable -- delete after
-- verifying.
insert into public.plays (user_id, case_id, status, updated_at, opened_at)
values
  ('d77bf956-2140-4fd6-b805-2ad217c02597', 'museum-diamond', 'solved', now(), now()),
  ('d77bf956-2140-4fd6-b805-2ad217c02597', 'flight-914-poisoning', 'solved', now(), now()),
  ('d77bf956-2140-4fd6-b805-2ad217c02597', 'meridian-station-sabotage', 'solved', now(), now())
on conflict (user_id, case_id) do update set status = 'solved';
