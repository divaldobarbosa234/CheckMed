-- Batch 2B-3B expansion only. This migration is not the write-enforcement cutover.
-- It is additive and keeps legacy table grants unchanged until the separate
-- enforcement migration is explicitly approved and applied.

alter table public.treatments
  add column if not exists subject_profile_id uuid,
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_mutation_id uuid;

alter table public.medicines
  add column if not exists subject_profile_id uuid,
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_mutation_id uuid,
  add column if not exists reason text not null default '',
  add column if not exists form text not null default 'other',
  add column if not exists package_amount double precision not null default 0,
  add column if not exists package_unit text not null default 'tablet',
  add column if not exists stock_percent double precision not null default 100,
  add column if not exists quantity_per_dose double precision not null default 1,
  add column if not exists dose_unit text not null default 'tablet',
  add column if not exists doctor_name text not null default '',
  add column if not exists doctor_id text not null default '',
  add column if not exists hospital_name text not null default '',
  add column if not exists doctor_notes text not null default '',
  add column if not exists last_refill_at timestamptz,
  add column if not exists refill_remind_enabled boolean not null default true;

alter table public.dose_schedules
  add column if not exists subject_profile_id uuid,
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_mutation_id uuid;

alter table public.dose_logs
  add column if not exists subject_profile_id uuid,
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_mutation_id uuid,
  add column if not exists logical_medicine_id uuid,
  add column if not exists slot_minute timestamptz;

update public.treatments
set subject_profile_id = profile_id
where subject_profile_id is null;

update public.medicines
set subject_profile_id = profile_id
where subject_profile_id is null;

update public.dose_schedules
set subject_profile_id = profile_id
where subject_profile_id is null;

update public.dose_logs
set subject_profile_id = profile_id
where subject_profile_id is null;

update public.dose_logs as log
set
  logical_medicine_id = schedule.medicine_id,
  slot_minute = date_trunc('minute', log.scheduled_at)
from public.dose_schedules as schedule
where schedule.id = log.schedule_id
  and (
    log.logical_medicine_id is distinct from schedule.medicine_id
    or log.slot_minute is distinct from date_trunc('minute', log.scheduled_at)
  );

alter table public.treatments
  drop constraint if exists treatments_sync_version_positive;
alter table public.treatments
  add constraint treatments_sync_version_positive check (sync_version > 0) not valid;

alter table public.medicines
  drop constraint if exists medicines_sync_version_positive;
alter table public.medicines
  add constraint medicines_sync_version_positive check (sync_version > 0) not valid;

alter table public.dose_schedules
  drop constraint if exists dose_schedules_sync_version_positive;
alter table public.dose_schedules
  add constraint dose_schedules_sync_version_positive check (sync_version > 0) not valid;

alter table public.dose_logs
  drop constraint if exists dose_logs_sync_version_positive;
alter table public.dose_logs
  add constraint dose_logs_sync_version_positive check (sync_version > 0) not valid;

create index if not exists treatments_owner_subject_version_idx
  on public.treatments (owner_id, subject_profile_id, sync_version);
create index if not exists medicines_owner_subject_version_idx
  on public.medicines (owner_id, subject_profile_id, sync_version);
create index if not exists medicines_treatment_id_idx
  on public.medicines (treatment_id);
create index if not exists dose_schedules_owner_subject_version_idx
  on public.dose_schedules (owner_id, subject_profile_id, sync_version);
create index if not exists dose_schedules_medicine_id_idx
  on public.dose_schedules (medicine_id);
create index if not exists dose_logs_owner_subject_scheduled_id_idx
  on public.dose_logs (owner_id, subject_profile_id, scheduled_at, id);
create index if not exists dose_logs_schedule_id_idx
  on public.dose_logs (schedule_id);
create index if not exists dose_logs_logical_slot_audit_idx
  on public.dose_logs (owner_id, subject_profile_id, logical_medicine_id, slot_minute)
  where deleted_at is null;

create table if not exists public.sync_mutation_receipts (
  owner_id uuid not null references auth.users (id) on delete cascade,
  mutation_id uuid not null,
  entity_type text not null,
  requested_entity_id uuid not null,
  request_body jsonb not null,
  outcome text not null,
  committed_version bigint,
  canonical_entity_id uuid,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (owner_id, mutation_id),
  constraint sync_mutation_receipts_entity_type
    check (entity_type in ('treatment', 'medicine', 'schedule', 'doseLog'))
);

create index if not exists sync_mutation_receipts_owner_created_idx
  on public.sync_mutation_receipts (owner_id, created_at);

alter table public.sync_mutation_receipts enable row level security;
revoke all on table public.sync_mutation_receipts from public, anon, authenticated;

create or replace function public.checkmed_sync_touch_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  business_changed boolean;
begin
  if tg_op = 'INSERT' then
    new.sync_version := 1;
    new.updated_at := clock_timestamp();
    return new;
  end if;

  if new.last_mutation_id is null then
    new.last_mutation_id := old.last_mutation_id;
  end if;

  business_changed :=
    (to_jsonb(new) - array['sync_version', 'updated_at', 'last_mutation_id'])
      is distinct from
    (to_jsonb(old) - array['sync_version', 'updated_at', 'last_mutation_id'])
    or new.last_mutation_id is distinct from old.last_mutation_id;

  if business_changed then
    new.sync_version := old.sync_version + 1;
    new.updated_at := clock_timestamp();
  else
    new.sync_version := old.sync_version;
    new.updated_at := old.updated_at;
  end if;
  return new;
end;
$$;

drop trigger if exists treatments_sync_touch_v1 on public.treatments;
create trigger treatments_sync_touch_v1
before insert or update on public.treatments
for each row execute function public.checkmed_sync_touch_v1();

drop trigger if exists medicines_sync_touch_v1 on public.medicines;
create trigger medicines_sync_touch_v1
before insert or update on public.medicines
for each row execute function public.checkmed_sync_touch_v1();

drop trigger if exists dose_schedules_sync_touch_v1 on public.dose_schedules;
create trigger dose_schedules_sync_touch_v1
before insert or update on public.dose_schedules
for each row execute function public.checkmed_sync_touch_v1();

drop trigger if exists dose_logs_sync_touch_v1 on public.dose_logs;
create trigger dose_logs_sync_touch_v1
before insert or update on public.dose_logs
for each row execute function public.checkmed_sync_touch_v1();

revoke all on function public.checkmed_sync_touch_v1() from public, anon, authenticated;

create or replace function public.checkmed_sync_subject_allowed_v1(
  p_owner_id uuid,
  p_subject_profile_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where owner_id = p_owner_id
      and (
        id = p_subject_profile_id
        or extra_family_id = p_subject_profile_id
      )
  );
$$;

revoke all on function public.checkmed_sync_subject_allowed_v1(uuid, uuid)
  from public, anon, authenticated;

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
    -- Expansion never activates the client consumer. The explicit enforcement
    -- migration replaces this capability only after validation and cutover.
    'outbox_consumption_enabled', false
  );
$$;

revoke all on function public.sync_protocol_capabilities_v1() from public, anon;
grant execute on function public.sync_protocol_capabilities_v1() to authenticated;

create or replace function public.apply_sync_mutation_v1(
  p_mutation_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_owner_id uuid,
  p_subject_profile_id uuid,
  p_operation text,
  p_expected_version bigint,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_id uuid := auth.uid();
  v_profile_id uuid;
  v_existing_owner uuid;
  v_existing_subject uuid;
  v_existing_version bigint;
  v_existing_deleted_at timestamptz;
  v_parent_deleted_at timestamptz;
  v_parent_owner uuid;
  v_parent_subject uuid;
  v_canonical jsonb;
  v_canonical_id uuid := p_entity_id;
  v_version bigint;
  v_outcome text;
  v_reason text;
  v_response jsonb;
  v_request jsonb;
  v_receipt_request jsonb;
  v_receipt_response jsonb;
  v_affected jsonb := '[]'::jsonb;
  v_allowed text[];
  v_logical_medicine_id uuid;
  v_slot_minute timestamptz;
  v_collision_id uuid;
  v_collision_status text;
  v_incoming_status text;
begin
  if v_auth_id is null or p_owner_id is distinct from v_auth_id then
    raise exception 'sync mutation unauthorized' using errcode = '42501';
  end if;
  if p_mutation_id is null
      or p_entity_id is null
      or p_subject_profile_id is null
      or p_entity_type not in ('treatment', 'medicine', 'schedule', 'doseLog')
      or p_operation not in ('upsert', 'delete')
      or p_expected_version < 0
      or p_payload is null
      or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid sync mutation' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_owner_id::text || ':' || p_mutation_id::text, 0)
  );

  v_request := jsonb_build_object(
    'mutation_id', p_mutation_id,
    'entity_type', p_entity_type,
    'entity_id', p_entity_id,
    'owner_id', p_owner_id,
    'subject_profile_id', p_subject_profile_id,
    'operation', p_operation,
    'expected_version', p_expected_version,
    'payload', p_payload
  );

  select request_body, response
  into v_receipt_request, v_receipt_response
  from public.sync_mutation_receipts
  where owner_id = p_owner_id and mutation_id = p_mutation_id;

  if found then
    if v_receipt_request = v_request then
      return v_receipt_response;
    end if;
    return jsonb_build_object(
      'protocol_version', 1,
      'mutation_id', p_mutation_id,
      'outcome', 'invalid',
      'entity_type', p_entity_type,
      'requested_entity_id', p_entity_id,
      'canonical_entity_id', null,
      'owner_id', p_owner_id,
      'subject_profile_id', p_subject_profile_id,
      'committed_version', null,
      'server_updated_at', null,
      'canonical_row', null,
      'affected_descendants', '[]'::jsonb,
      'reason', 'mutation_id_reused'
    );
  end if;

  select id into v_profile_id
  from public.profiles
  where owner_id = p_owner_id
  limit 1;
  if v_profile_id is null then
    raise exception 'sync mutation unauthorized' using errcode = '42501';
  end if;

  case p_entity_type
    when 'treatment' then
      v_allowed := array['title', 'status', 'start_date', 'end_date'];
    when 'medicine' then
      v_allowed := array[
        'treatment_id', 'name', 'dose_label', 'frequency', 'duration',
        'reason', 'form', 'package_amount', 'package_unit', 'stock_percent',
        'quantity_per_dose', 'dose_unit', 'doctor_name', 'doctor_id',
        'hospital_name', 'doctor_notes', 'last_refill_at',
        'refill_remind_enabled'
      ];
    when 'schedule' then
      v_allowed := array['medicine_id', 'time_of_day', 'period'];
    when 'doseLog' then
      v_allowed := array['schedule_id', 'scheduled_at', 'status', 'logged_at'];
  end case;

  if exists (
    select 1
    from jsonb_object_keys(p_payload) as key_name
    where key_name <> all(v_allowed)
  ) then
    v_outcome := 'invalid';
    v_reason := 'payload_field_not_allowed';
  else
    <<apply_entity>>
    begin
      if p_entity_type = 'treatment' then
        select owner_id, subject_profile_id, sync_version, deleted_at, to_jsonb(row_value)
        into v_existing_owner, v_existing_subject, v_existing_version,
             v_existing_deleted_at, v_canonical
        from public.treatments as row_value
        where id = p_entity_id
        for update;

        if found and (
          v_existing_owner is distinct from p_owner_id
          or v_existing_subject is distinct from p_subject_profile_id
        ) then
          raise exception 'sync mutation unauthorized' using errcode = '42501';
        end if;

        if not found then
          if p_operation = 'delete' then
            v_outcome := 'already_deleted';
            v_canonical := null;
            v_version := null;
            exit apply_entity;
          end if;
          if p_expected_version <> 0 then
            v_outcome := 'conflict';
            v_reason := 'record_missing';
            exit apply_entity;
          end if;
          if not public.checkmed_sync_subject_allowed_v1(
            p_owner_id, p_subject_profile_id
          ) then
            raise exception 'sync mutation unauthorized' using errcode = '42501';
          end if;
          if not (p_payload ? 'title' and p_payload ? 'status' and p_payload ? 'start_date') then
            v_outcome := 'invalid';
            v_reason := 'required_field_missing';
            exit apply_entity;
          end if;
          insert into public.treatments (
            id, owner_id, profile_id, subject_profile_id, title, status,
            start_date, end_date, last_mutation_id
          ) values (
            p_entity_id, p_owner_id, v_profile_id, p_subject_profile_id,
            p_payload->>'title', p_payload->>'status',
            (p_payload->>'start_date')::date,
            nullif(p_payload->>'end_date', '')::date,
            p_mutation_id
          )
          returning to_jsonb(treatments.*), sync_version
          into v_canonical, v_version;
          v_outcome := 'applied';
          exit apply_entity;
        end if;

        v_version := v_existing_version;
        if v_existing_deleted_at is not null then
          v_outcome := case when p_operation = 'delete' then 'already_deleted' else 'conflict' end;
          v_reason := case when p_operation = 'delete' then null else 'record_deleted' end;
          exit apply_entity;
        end if;
        if p_expected_version <> v_existing_version then
          v_outcome := 'conflict';
          v_reason := 'stale_version';
          exit apply_entity;
        end if;

        if p_operation = 'delete' then
          with changed as (
            update public.dose_logs as log
            set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
            where log.deleted_at is null
              and exists (
                select 1
                from public.dose_schedules as schedule
                join public.medicines as medicine on medicine.id = schedule.medicine_id
                where schedule.id = log.schedule_id
                  and medicine.treatment_id = p_entity_id
                  and medicine.owner_id = p_owner_id
              )
            returning id, sync_version
          )
          select v_affected || coalesce(
            jsonb_agg(jsonb_build_object(
              'entity_type', 'doseLog',
              'entity_id', id,
              'committed_version', sync_version
            )), '[]'::jsonb
          ) into v_affected from changed;

          with changed as (
            update public.dose_schedules as schedule
            set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
            where schedule.deleted_at is null
              and exists (
                select 1 from public.medicines as medicine
                where medicine.id = schedule.medicine_id
                  and medicine.treatment_id = p_entity_id
                  and medicine.owner_id = p_owner_id
              )
            returning id, sync_version
          )
          select v_affected || coalesce(
            jsonb_agg(jsonb_build_object(
              'entity_type', 'schedule',
              'entity_id', id,
              'committed_version', sync_version
            )), '[]'::jsonb
          ) into v_affected from changed;

          with changed as (
            update public.medicines
            set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
            where treatment_id = p_entity_id
              and owner_id = p_owner_id
              and deleted_at is null
            returning id, sync_version
          )
          select v_affected || coalesce(
            jsonb_agg(jsonb_build_object(
              'entity_type', 'medicine',
              'entity_id', id,
              'committed_version', sync_version
            )), '[]'::jsonb
          ) into v_affected from changed;

          update public.treatments
          set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
          where id = p_entity_id
          returning to_jsonb(treatments.*), sync_version
          into v_canonical, v_version;
        else
          if not (p_payload ? 'title' and p_payload ? 'status' and p_payload ? 'start_date') then
            v_outcome := 'invalid';
            v_reason := 'required_field_missing';
            exit apply_entity;
          end if;
          update public.treatments
          set
            title = p_payload->>'title',
            status = p_payload->>'status',
            start_date = (p_payload->>'start_date')::date,
            end_date = nullif(p_payload->>'end_date', '')::date,
            last_mutation_id = p_mutation_id
          where id = p_entity_id
          returning to_jsonb(treatments.*), sync_version
          into v_canonical, v_version;
        end if;
        v_outcome := 'applied';

      elsif p_entity_type = 'medicine' then
        select owner_id, subject_profile_id, sync_version, deleted_at, to_jsonb(row_value)
        into v_existing_owner, v_existing_subject, v_existing_version,
             v_existing_deleted_at, v_canonical
        from public.medicines as row_value
        where id = p_entity_id
        for update;

        if found and (
          v_existing_owner is distinct from p_owner_id
          or v_existing_subject is distinct from p_subject_profile_id
        ) then
          raise exception 'sync mutation unauthorized' using errcode = '42501';
        end if;
        if not found and p_operation = 'delete' then
          v_outcome := 'already_deleted';
          v_canonical := null;
          v_version := null;
          exit apply_entity;
        end if;
        if not found and p_expected_version <> 0 then
          v_outcome := 'conflict';
          v_reason := 'record_missing';
          exit apply_entity;
        end if;
        if found and v_existing_deleted_at is not null then
          v_version := v_existing_version;
          v_outcome := case when p_operation = 'delete' then 'already_deleted' else 'conflict' end;
          v_reason := case when p_operation = 'delete' then null else 'record_deleted' end;
          exit apply_entity;
        end if;
        if found and p_expected_version <> v_existing_version then
          v_version := v_existing_version;
          v_outcome := 'conflict';
          v_reason := 'stale_version';
          exit apply_entity;
        end if;

        if p_operation = 'delete' then
          with changed as (
            update public.dose_logs as log
            set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
            where log.deleted_at is null
              and exists (
                select 1 from public.dose_schedules as schedule
                where schedule.id = log.schedule_id
                  and schedule.medicine_id = p_entity_id
                  and schedule.owner_id = p_owner_id
              )
            returning id, sync_version
          )
          select v_affected || coalesce(
            jsonb_agg(jsonb_build_object(
              'entity_type', 'doseLog',
              'entity_id', id,
              'committed_version', sync_version
            )), '[]'::jsonb
          ) into v_affected from changed;

          with changed as (
            update public.dose_schedules
            set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
            where medicine_id = p_entity_id
              and owner_id = p_owner_id
              and deleted_at is null
            returning id, sync_version
          )
          select v_affected || coalesce(
            jsonb_agg(jsonb_build_object(
              'entity_type', 'schedule',
              'entity_id', id,
              'committed_version', sync_version
            )), '[]'::jsonb
          ) into v_affected from changed;

          update public.medicines
          set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
          where id = p_entity_id
          returning to_jsonb(medicines.*), sync_version
          into v_canonical, v_version;
          v_outcome := 'applied';
          exit apply_entity;
        end if;

        if v_existing_version is null
            and not public.checkmed_sync_subject_allowed_v1(
              p_owner_id, p_subject_profile_id
            ) then
          raise exception 'sync mutation unauthorized' using errcode = '42501';
        end if;
        if not (
          p_payload ? 'treatment_id' and p_payload ? 'name'
          and p_payload ? 'dose_label' and p_payload ? 'frequency'
          and p_payload ? 'duration' and p_payload ? 'reason'
          and p_payload ? 'form' and p_payload ? 'package_amount'
          and p_payload ? 'package_unit' and p_payload ? 'stock_percent'
          and p_payload ? 'quantity_per_dose' and p_payload ? 'dose_unit'
          and p_payload ? 'doctor_name' and p_payload ? 'doctor_id'
          and p_payload ? 'hospital_name' and p_payload ? 'doctor_notes'
          and p_payload ? 'refill_remind_enabled'
        ) then
          v_outcome := 'invalid';
          v_reason := 'required_field_missing';
          exit apply_entity;
        end if;

        select owner_id, subject_profile_id, deleted_at
        into v_parent_owner, v_parent_subject, v_parent_deleted_at
        from public.treatments
        where id = (p_payload->>'treatment_id')::uuid
        for update;
        if not found
            or v_parent_owner is distinct from p_owner_id
            or v_parent_subject is distinct from p_subject_profile_id then
          raise exception 'sync mutation unauthorized' using errcode = '42501';
        end if;
        if v_parent_deleted_at is not null then
          v_outcome := 'parent_deleted';
          v_reason := 'treatment_deleted';
          exit apply_entity;
        end if;

        if v_existing_version is null then
          insert into public.medicines (
            id, owner_id, profile_id, subject_profile_id, treatment_id,
            name, dose_label, frequency, duration, reason, form,
            package_amount, package_unit, stock_percent, quantity_per_dose,
            dose_unit, doctor_name, doctor_id, hospital_name, doctor_notes,
            last_refill_at, refill_remind_enabled, last_mutation_id
          ) values (
            p_entity_id, p_owner_id, v_profile_id, p_subject_profile_id,
            (p_payload->>'treatment_id')::uuid, p_payload->>'name',
            p_payload->>'dose_label', p_payload->>'frequency',
            p_payload->>'duration', p_payload->>'reason', p_payload->>'form',
            (p_payload->>'package_amount')::double precision,
            p_payload->>'package_unit',
            (p_payload->>'stock_percent')::double precision,
            (p_payload->>'quantity_per_dose')::double precision,
            p_payload->>'dose_unit', p_payload->>'doctor_name',
            p_payload->>'doctor_id', p_payload->>'hospital_name',
            p_payload->>'doctor_notes',
            nullif(p_payload->>'last_refill_at', '')::timestamptz,
            (p_payload->>'refill_remind_enabled')::boolean,
            p_mutation_id
          )
          returning to_jsonb(medicines.*), sync_version
          into v_canonical, v_version;
        else
          update public.medicines
          set
            treatment_id = (p_payload->>'treatment_id')::uuid,
            name = p_payload->>'name',
            dose_label = p_payload->>'dose_label',
            frequency = p_payload->>'frequency',
            duration = p_payload->>'duration',
            reason = p_payload->>'reason',
            form = p_payload->>'form',
            package_amount = (p_payload->>'package_amount')::double precision,
            package_unit = p_payload->>'package_unit',
            stock_percent = (p_payload->>'stock_percent')::double precision,
            quantity_per_dose = (p_payload->>'quantity_per_dose')::double precision,
            dose_unit = p_payload->>'dose_unit',
            doctor_name = p_payload->>'doctor_name',
            doctor_id = p_payload->>'doctor_id',
            hospital_name = p_payload->>'hospital_name',
            doctor_notes = p_payload->>'doctor_notes',
            last_refill_at = nullif(p_payload->>'last_refill_at', '')::timestamptz,
            refill_remind_enabled = (p_payload->>'refill_remind_enabled')::boolean,
            last_mutation_id = p_mutation_id
          where id = p_entity_id
          returning to_jsonb(medicines.*), sync_version
          into v_canonical, v_version;
        end if;
        v_outcome := 'applied';

      elsif p_entity_type = 'schedule' then
        select owner_id, subject_profile_id, sync_version, deleted_at, to_jsonb(row_value)
        into v_existing_owner, v_existing_subject, v_existing_version,
             v_existing_deleted_at, v_canonical
        from public.dose_schedules as row_value
        where id = p_entity_id
        for update;

        if found and (
          v_existing_owner is distinct from p_owner_id
          or v_existing_subject is distinct from p_subject_profile_id
        ) then
          raise exception 'sync mutation unauthorized' using errcode = '42501';
        end if;
        if not found and p_operation = 'delete' then
          v_outcome := 'already_deleted';
          v_canonical := null;
          v_version := null;
          exit apply_entity;
        end if;
        if not found and p_expected_version <> 0 then
          v_outcome := 'conflict';
          v_reason := 'record_missing';
          exit apply_entity;
        end if;
        if found and v_existing_deleted_at is not null then
          v_version := v_existing_version;
          v_outcome := case when p_operation = 'delete' then 'already_deleted' else 'conflict' end;
          v_reason := case when p_operation = 'delete' then null else 'record_deleted' end;
          exit apply_entity;
        end if;
        if found and p_expected_version <> v_existing_version then
          v_version := v_existing_version;
          v_outcome := 'conflict';
          v_reason := 'stale_version';
          exit apply_entity;
        end if;

        if p_operation = 'delete' then
          with changed as (
            update public.dose_logs
            set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
            where schedule_id = p_entity_id
              and owner_id = p_owner_id
              and deleted_at is null
            returning id, sync_version
          )
          select v_affected || coalesce(
            jsonb_agg(jsonb_build_object(
              'entity_type', 'doseLog',
              'entity_id', id,
              'committed_version', sync_version
            )), '[]'::jsonb
          ) into v_affected from changed;

          update public.dose_schedules
          set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
          where id = p_entity_id
          returning to_jsonb(dose_schedules.*), sync_version
          into v_canonical, v_version;
          v_outcome := 'applied';
          exit apply_entity;
        end if;

        if not (p_payload ? 'medicine_id' and p_payload ? 'time_of_day' and p_payload ? 'period') then
          v_outcome := 'invalid';
          v_reason := 'required_field_missing';
          exit apply_entity;
        end if;
        select owner_id, subject_profile_id, deleted_at
        into v_parent_owner, v_parent_subject, v_parent_deleted_at
        from public.medicines
        where id = (p_payload->>'medicine_id')::uuid
        for update;
        if not found
            or v_parent_owner is distinct from p_owner_id
            or v_parent_subject is distinct from p_subject_profile_id then
          raise exception 'sync mutation unauthorized' using errcode = '42501';
        end if;
        if v_parent_deleted_at is not null then
          v_outcome := 'parent_deleted';
          v_reason := 'medicine_deleted';
          exit apply_entity;
        end if;

        if v_existing_version is null then
          insert into public.dose_schedules (
            id, owner_id, profile_id, subject_profile_id, medicine_id,
            time_of_day, period, last_mutation_id
          ) values (
            p_entity_id, p_owner_id, v_profile_id, p_subject_profile_id,
            (p_payload->>'medicine_id')::uuid, p_payload->>'time_of_day',
            p_payload->>'period', p_mutation_id
          )
          returning to_jsonb(dose_schedules.*), sync_version
          into v_canonical, v_version;
        else
          update public.dose_schedules
          set
            medicine_id = (p_payload->>'medicine_id')::uuid,
            time_of_day = p_payload->>'time_of_day',
            period = p_payload->>'period',
            last_mutation_id = p_mutation_id
          where id = p_entity_id
          returning to_jsonb(dose_schedules.*), sync_version
          into v_canonical, v_version;
        end if;
        v_outcome := 'applied';

      else
        select owner_id, subject_profile_id, sync_version, deleted_at, to_jsonb(row_value)
        into v_existing_owner, v_existing_subject, v_existing_version,
             v_existing_deleted_at, v_canonical
        from public.dose_logs as row_value
        where id = p_entity_id
        for update;

        if found and (
          v_existing_owner is distinct from p_owner_id
          or v_existing_subject is distinct from p_subject_profile_id
        ) then
          raise exception 'sync mutation unauthorized' using errcode = '42501';
        end if;
        if not found and p_operation = 'delete' then
          v_outcome := 'already_deleted';
          v_canonical := null;
          v_version := null;
          exit apply_entity;
        end if;
        if not found and p_expected_version <> 0 then
          v_outcome := 'conflict';
          v_reason := 'record_missing';
          exit apply_entity;
        end if;
        if found and v_existing_deleted_at is not null then
          v_version := v_existing_version;
          v_outcome := case when p_operation = 'delete' then 'already_deleted' else 'conflict' end;
          v_reason := case when p_operation = 'delete' then null else 'record_deleted' end;
          exit apply_entity;
        end if;
        if found and p_expected_version <> v_existing_version then
          v_version := v_existing_version;
          v_outcome := 'conflict';
          v_reason := 'stale_version';
          exit apply_entity;
        end if;

        if p_operation = 'delete' then
          update public.dose_logs
          set deleted_at = clock_timestamp(), last_mutation_id = p_mutation_id
          where id = p_entity_id
          returning to_jsonb(dose_logs.*), sync_version
          into v_canonical, v_version;
          v_outcome := 'applied';
          exit apply_entity;
        end if;

        if not (
          p_payload ? 'schedule_id' and p_payload ? 'scheduled_at'
          and p_payload ? 'status'
        ) then
          v_outcome := 'invalid';
          v_reason := 'required_field_missing';
          exit apply_entity;
        end if;
        select owner_id, subject_profile_id, deleted_at, medicine_id
        into v_parent_owner, v_parent_subject, v_parent_deleted_at,
             v_logical_medicine_id
        from public.dose_schedules
        where id = (p_payload->>'schedule_id')::uuid
        for update;
        if not found
            or v_parent_owner is distinct from p_owner_id
            or v_parent_subject is distinct from p_subject_profile_id then
          raise exception 'sync mutation unauthorized' using errcode = '42501';
        end if;
        if v_parent_deleted_at is not null then
          v_outcome := 'parent_deleted';
          v_reason := 'schedule_deleted';
          exit apply_entity;
        end if;

        v_slot_minute := date_trunc(
          'minute',
          (p_payload->>'scheduled_at')::timestamptz
        );
        v_incoming_status := p_payload->>'status';

        if v_existing_version is not null then
          select id, status, sync_version, to_jsonb(row_value)
          into v_collision_id, v_collision_status, v_version, v_canonical
          from public.dose_logs as row_value
          where owner_id = p_owner_id
            and subject_profile_id = p_subject_profile_id
            and logical_medicine_id = v_logical_medicine_id
            and slot_minute = v_slot_minute
            and deleted_at is null
            and id <> p_entity_id
          order by id
          limit 1
          for update;
          if found then
            v_canonical_id := v_collision_id;
            v_outcome := 'conflict';
            v_reason := 'logical_slot_conflict';
            exit apply_entity;
          end if;
        end if;

        if v_existing_version is null then
          select id, status, sync_version, to_jsonb(row_value)
          into v_collision_id, v_collision_status, v_version, v_canonical
          from public.dose_logs as row_value
          where owner_id = p_owner_id
            and subject_profile_id = p_subject_profile_id
            and logical_medicine_id = v_logical_medicine_id
            and slot_minute = v_slot_minute
            and deleted_at is null
          order by id
          limit 1
          for update;

          if found then
            v_canonical_id := v_collision_id;
            if v_collision_status = v_incoming_status
                or (
                  v_collision_status in ('taken', 'takenLate')
                  and v_incoming_status not in ('taken', 'takenLate')
                ) then
              v_outcome := 'already_applied';
            else
              v_outcome := 'conflict';
              v_reason := 'logical_slot_conflict';
            end if;
            exit apply_entity;
          end if;

          insert into public.dose_logs (
            id, owner_id, profile_id, subject_profile_id, schedule_id,
            scheduled_at, status, logged_at, logical_medicine_id,
            slot_minute, last_mutation_id
          ) values (
            p_entity_id, p_owner_id, v_profile_id, p_subject_profile_id,
            (p_payload->>'schedule_id')::uuid,
            (p_payload->>'scheduled_at')::timestamptz,
            v_incoming_status,
            nullif(p_payload->>'logged_at', '')::timestamptz,
            v_logical_medicine_id, v_slot_minute, p_mutation_id
          )
          returning to_jsonb(dose_logs.*), sync_version
          into v_canonical, v_version;
        else
          update public.dose_logs
          set
            schedule_id = (p_payload->>'schedule_id')::uuid,
            scheduled_at = (p_payload->>'scheduled_at')::timestamptz,
            status = v_incoming_status,
            logged_at = nullif(p_payload->>'logged_at', '')::timestamptz,
            logical_medicine_id = v_logical_medicine_id,
            slot_minute = v_slot_minute,
            last_mutation_id = p_mutation_id
          where id = p_entity_id
          returning to_jsonb(dose_logs.*), sync_version
          into v_canonical, v_version;
        end if;
        v_outcome := 'applied';
      end if;
    exception
      when invalid_text_representation or not_null_violation
          or check_violation or numeric_value_out_of_range then
        v_outcome := 'invalid';
        v_reason := 'payload_value_invalid';
        v_canonical := null;
        v_version := null;
    end apply_entity;
  end if;

  v_response := jsonb_build_object(
    'protocol_version', 1,
    'mutation_id', p_mutation_id,
    'outcome', v_outcome,
    'entity_type', p_entity_type,
    'requested_entity_id', p_entity_id,
    'canonical_entity_id', v_canonical_id,
    'owner_id', p_owner_id,
    'subject_profile_id', p_subject_profile_id,
    'committed_version', v_version,
    'server_updated_at', v_canonical->>'updated_at',
    'canonical_row', v_canonical,
    'affected_descendants', v_affected,
    'reason', v_reason
  );

  insert into public.sync_mutation_receipts (
    owner_id, mutation_id, entity_type, requested_entity_id,
    request_body, outcome, committed_version, canonical_entity_id, response
  ) values (
    p_owner_id, p_mutation_id, p_entity_type, p_entity_id,
    v_request, v_outcome, v_version, v_canonical_id, v_response
  );

  return v_response;
end;
$$;

revoke all on function public.apply_sync_mutation_v1(
  uuid, text, uuid, uuid, uuid, text, bigint, jsonb
) from public, anon;
grant execute on function public.apply_sync_mutation_v1(
  uuid, text, uuid, uuid, uuid, text, bigint, jsonb
) to authenticated;
