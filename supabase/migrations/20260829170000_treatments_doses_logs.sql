-- Phase 3: treatments, medicines, dose schedules, and dose logs.
-- Local SwiftData is the UI source of truth; these tables are the signed-in replica.
-- Do not drop or alter existing profiles columns.

create table if not exists public.treatments (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  status text not null default 'active',
  start_date date not null default current_date,
  end_date date,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.medicines (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  treatment_id uuid not null references public.treatments (id) on delete cascade,
  name text not null,
  dose_label text not null default '',
  frequency text not null default '',
  duration text not null default '',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.dose_schedules (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  medicine_id uuid not null references public.medicines (id) on delete cascade,
  time_of_day text not null,
  period text not null default 'Morning',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.dose_logs (
  id uuid primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  schedule_id uuid not null references public.dose_schedules (id) on delete cascade,
  scheduled_at timestamptz not null,
  status text not null default 'pending',
  logged_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists dose_logs_schedule_slot
  on public.dose_logs (schedule_id, scheduled_at)
  where deleted_at is null;

create index if not exists treatments_owner_id_idx on public.treatments (owner_id);
create index if not exists medicines_owner_id_idx on public.medicines (owner_id);
create index if not exists dose_schedules_owner_id_idx on public.dose_schedules (owner_id);
create index if not exists dose_logs_owner_id_idx on public.dose_logs (owner_id);

alter table public.treatments enable row level security;
alter table public.medicines enable row level security;
alter table public.dose_schedules enable row level security;
alter table public.dose_logs enable row level security;

drop policy if exists treatments_select_own on public.treatments;
create policy treatments_select_own
  on public.treatments for select
  using (auth.uid() = owner_id);

drop policy if exists treatments_insert_own on public.treatments;
create policy treatments_insert_own
  on public.treatments for insert
  with check (auth.uid() = owner_id);

drop policy if exists treatments_update_own on public.treatments;
create policy treatments_update_own
  on public.treatments for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists treatments_delete_own on public.treatments;
create policy treatments_delete_own
  on public.treatments for delete
  using (auth.uid() = owner_id);

drop policy if exists medicines_select_own on public.medicines;
create policy medicines_select_own
  on public.medicines for select
  using (auth.uid() = owner_id);

drop policy if exists medicines_insert_own on public.medicines;
create policy medicines_insert_own
  on public.medicines for insert
  with check (auth.uid() = owner_id);

drop policy if exists medicines_update_own on public.medicines;
create policy medicines_update_own
  on public.medicines for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists medicines_delete_own on public.medicines;
create policy medicines_delete_own
  on public.medicines for delete
  using (auth.uid() = owner_id);

drop policy if exists dose_schedules_select_own on public.dose_schedules;
create policy dose_schedules_select_own
  on public.dose_schedules for select
  using (auth.uid() = owner_id);

drop policy if exists dose_schedules_insert_own on public.dose_schedules;
create policy dose_schedules_insert_own
  on public.dose_schedules for insert
  with check (auth.uid() = owner_id);

drop policy if exists dose_schedules_update_own on public.dose_schedules;
create policy dose_schedules_update_own
  on public.dose_schedules for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists dose_schedules_delete_own on public.dose_schedules;
create policy dose_schedules_delete_own
  on public.dose_schedules for delete
  using (auth.uid() = owner_id);

drop policy if exists dose_logs_select_own on public.dose_logs;
create policy dose_logs_select_own
  on public.dose_logs for select
  using (auth.uid() = owner_id);

drop policy if exists dose_logs_insert_own on public.dose_logs;
create policy dose_logs_insert_own
  on public.dose_logs for insert
  with check (auth.uid() = owner_id);

drop policy if exists dose_logs_update_own on public.dose_logs;
create policy dose_logs_update_own
  on public.dose_logs for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists dose_logs_delete_own on public.dose_logs;
create policy dose_logs_delete_own
  on public.dose_logs for delete
  using (auth.uid() = owner_id);
