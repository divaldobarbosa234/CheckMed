-- Extra Super family seat stored on the signed-in profile (one extra member).
alter table public.profiles
  add column if not exists extra_family_id uuid,
  add column if not exists extra_family_name text;

comment on column public.profiles.extra_family_id is
  'Optional second profile slot id for Super. Never mix doses between seats.';
comment on column public.profiles.extra_family_name is
  'Display name for the extra Super family seat.';
