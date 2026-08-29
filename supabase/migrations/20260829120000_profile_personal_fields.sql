-- Personal setup fields for signed-in profiles.
-- Ages 16–90 are enforced in the iOS app using calendar dates
-- (today minus 16 years / today minus 90 years), not year-only math.

alter table public.profiles
  add column if not exists date_of_birth date,
  add column if not exists language text,
  add column if not exists time_zone text;

comment on column public.profiles.date_of_birth is
  'Calendar date of birth. The app allows ages 16 through 90.';
comment on column public.profiles.language is
  'UI language/locale code (en, pt, es, fr).';
comment on column public.profiles.time_zone is
  'IANA time zone identifier.';

create or replace function public.set_profiles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_profiles_updated_at();
