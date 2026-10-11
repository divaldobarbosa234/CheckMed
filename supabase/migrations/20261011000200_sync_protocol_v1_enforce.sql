-- Batch 2B-3B controlled cutover. Do not apply until:
-- 1. the compatible client is released,
-- 2. subject/orphan/collision validation is clean,
-- 3. the minimum-supported-version boundary is approved, and
-- 4. isolated two-device and legacy-client tests pass.
--
-- Rollback must disable client consumption. It must not automatically restore
-- direct table writes.

do $$
begin
  if exists (
    select 1
    from public.dose_logs
    where logical_medicine_id is null or slot_minute is null
  ) then
    raise exception 'sync cutover blocked: DoseLog slot metadata is incomplete';
  end if;

  if exists (
    select 1
    from public.dose_logs
    where deleted_at is null
    group by owner_id, subject_profile_id, logical_medicine_id, slot_minute
    having count(*) > 1
  ) then
    raise exception 'sync cutover blocked: active logical DoseLog collisions exist';
  end if;

  if exists (
    select 1
    from public.medicines as medicine
    left join public.treatments as treatment
      on treatment.id = medicine.treatment_id
    where treatment.id is null
      or treatment.owner_id is distinct from medicine.owner_id
      or treatment.subject_profile_id is distinct from medicine.subject_profile_id
  ) then
    raise exception 'sync cutover blocked: medicine hierarchy ownership mismatch';
  end if;

  if exists (
    select 1
    from public.dose_schedules as schedule
    left join public.medicines as medicine
      on medicine.id = schedule.medicine_id
    where medicine.id is null
      or medicine.owner_id is distinct from schedule.owner_id
      or medicine.subject_profile_id is distinct from schedule.subject_profile_id
  ) then
    raise exception 'sync cutover blocked: schedule hierarchy ownership mismatch';
  end if;

  if exists (
    select 1
    from public.dose_logs as log
    left join public.dose_schedules as schedule
      on schedule.id = log.schedule_id
    where schedule.id is null
      or schedule.owner_id is distinct from log.owner_id
      or schedule.subject_profile_id is distinct from log.subject_profile_id
  ) then
    raise exception 'sync cutover blocked: DoseLog hierarchy ownership mismatch';
  end if;
end;
$$;

alter table public.treatments
  validate constraint treatments_sync_version_positive;
alter table public.medicines
  validate constraint medicines_sync_version_positive;
alter table public.dose_schedules
  validate constraint dose_schedules_sync_version_positive;
alter table public.dose_logs
  validate constraint dose_logs_sync_version_positive;

alter table public.dose_logs
  alter column logical_medicine_id set not null,
  alter column slot_minute set not null;

alter table public.treatments
  alter column subject_profile_id set not null;
alter table public.medicines
  alter column subject_profile_id set not null;
alter table public.dose_schedules
  alter column subject_profile_id set not null;
alter table public.dose_logs
  alter column subject_profile_id set not null;

create unique index if not exists dose_logs_owner_subject_logical_slot_active
  on public.dose_logs (
    owner_id,
    subject_profile_id,
    logical_medicine_id,
    slot_minute
  )
  where deleted_at is null;

revoke insert, update, delete, truncate, references, trigger
  on table public.treatments
  from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.medicines
  from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.dose_schedules
  from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.dose_logs
  from anon, authenticated;

grant select on table public.treatments to authenticated;
grant select on table public.medicines to authenticated;
grant select on table public.dose_schedules to authenticated;
grant select on table public.dose_logs to authenticated;

create or replace function public.sync_protocol_capabilities_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'protocol_version', 1,
    'mutation_rpc_available', true,
    'direct_writes_enforced',
      not (
        has_table_privilege('authenticated', 'public.treatments', 'INSERT,UPDATE,DELETE')
        or has_table_privilege('authenticated', 'public.medicines', 'INSERT,UPDATE,DELETE')
        or has_table_privilege('authenticated', 'public.dose_schedules', 'INSERT,UPDATE,DELETE')
        or has_table_privilege('authenticated', 'public.dose_logs', 'INSERT,UPDATE,DELETE')
      ),
    -- Enforcement revokes legacy writes. It does not authorize client
    -- outbox consumption. A later explicit activation migration is required.
    'outbox_consumption_enabled', false
  );
$$;

revoke all on table public.sync_mutation_receipts from public, anon, authenticated;
revoke all on function public.apply_sync_mutation_v1(
  uuid, text, uuid, uuid, uuid, text, bigint, jsonb
) from public, anon;
grant execute on function public.apply_sync_mutation_v1(
  uuid, text, uuid, uuid, uuid, text, bigint, jsonb
) to authenticated;

revoke all on function public.sync_protocol_capabilities_v1() from public, anon;
grant execute on function public.sync_protocol_capabilities_v1() to authenticated;
