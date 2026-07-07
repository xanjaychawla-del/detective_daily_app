-- The incoming-call briefing script (title + briefing + a deterministic
-- "Inspector <name>" per case) is identical for every player of a given
-- case, so the synthesized audio is generated once via ElevenLabs and
-- cached here rather than re-synthesized (and re-billed) per play.
alter table public.cases add column briefing_audio_url text;

insert into storage.buckets (id, name, public)
values ('case-audio', 'case-audio', true)
on conflict (id) do nothing;

create policy "case audio is publicly readable"
  on storage.objects for select
  using (bucket_id = 'case-audio');
