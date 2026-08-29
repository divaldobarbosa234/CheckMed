-- How to address you: pronouns and gender on profiles.
-- Name, date_of_birth, language, and time_zone were added in profile_personal_fields.

alter table public.profiles
  add column if not exists pronouns text,
  add column if not exists gender text;

comment on column public.profiles.pronouns is
  'How to address the person: she_her, he_him, they_them, prefer_not, or a custom label.';
comment on column public.profiles.gender is
  'Gender: woman, man, non_binary, prefer_not, or a self-described label.';
