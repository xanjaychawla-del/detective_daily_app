-- One-off cleanup: two independent Gemini generations produced the same
-- "The Missing Meteorite" title/premise before the duplicate-title guard
-- in generate-case/index.ts existed. Removes the older of the two rows;
-- the newer one (ai-69a3d3ba-...) and every other case is untouched.
delete from public.cases where id = 'ai-a01c9f3c-76a6-4442-8426-2baa28a11e0f';
