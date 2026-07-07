-- Reverts the 3 fake "solved" rows inserted by migration 007 for manual
-- guest-cap testing, now that the block has been verified end-to-end.
delete from public.plays
where user_id = 'd77bf956-2140-4fd6-b805-2ad217c02597'
  and case_id in ('museum-diamond', 'flight-914-poisoning', 'meridian-station-sabotage');
