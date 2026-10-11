-- Isolated Batch 2B-3B/3C protocol checks.
-- NEVER run against CheckMed_Project or any production database.
-- Intended for a disposable local Postgres / isolated Supabase instance only.

create extension if not exists dblink;
create schema if not exists sync_protocol_test;

create or replace function sync_protocol_test.fail(msg text)
returns void
language plpgsql
as $$
begin
  raise exception 'FAIL: %', msg;
end;
$$;

create or replace function sync_protocol_test.assert(cond boolean, msg text)
returns void
language plpgsql
as $$
begin
  if not coalesce(cond, false) then
    perform sync_protocol_test.fail(msg);
  end if;
end;
$$;

create or replace function sync_protocol_test.set_auth(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_uid::text || '@isolated.test')::text,
    true
  );
end;
$$;

create or replace function sync_protocol_test.clear_auth()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
end;
$$;

grant usage on schema sync_protocol_test to authenticated;
grant execute on all functions in schema sync_protocol_test to authenticated;

create or replace function sync_protocol_test.ensure_user(
  p_id uuid,
  p_email text,
  p_display text
)
returns uuid
language plpgsql
as $$
begin
  if not exists (select 1 from auth.users where id = p_id) then
    insert into auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      email_change,
      email_change_token_new,
      recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000',
      p_id,
      'authenticated',
      'authenticated',
      p_email,
      crypt('isolated-only', gen_salt('bf')),
      clock_timestamp(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('display_name', p_display),
      clock_timestamp(),
      clock_timestamp(),
      '',
      '',
      '',
      ''
    );
  end if;
  insert into public.profiles (owner_id, display_name, companion_name)
  values (p_id, p_display, 'Phil')
  on conflict (owner_id) do nothing;
  return p_id;
end;
$$;

create or replace function sync_protocol_test.medicine_payload(p_treatment_id uuid)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'treatment_id', p_treatment_id,
    'name', 'Atorvastatin',
    'dose_label', '20 mg',
    'frequency', 'once daily',
    'duration', '30 days',
    'reason', 'cholesterol',
    'form', 'tablet',
    'package_amount', 30,
    'package_unit', 'tablet',
    'stock_percent', 100,
    'quantity_per_dose', 1,
    'dose_unit', 'tablet',
    'doctor_name', 'Dr Isolated',
    'doctor_id', 'iso-1',
    'hospital_name', 'Isolated Hospital',
    'doctor_notes', '',
    'refill_remind_enabled', true
  );
$$;

select sync_protocol_test.ensure_user(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'owner-a@isolated.test',
  'Owner A'
);
select sync_protocol_test.ensure_user(
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'owner-b@isolated.test',
  'Owner B'
);
update public.profiles
set extra_family_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff',
    extra_family_name = 'Isolated family'
where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  and extra_family_id is distinct from 'ffffffff-ffff-ffff-ffff-ffffffffffff';

delete from public.treatments
where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
insert into public.treatments (
  id, owner_id, profile_id, subject_profile_id, title, status, start_date
)
select
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  p.id,
  p.id,
  'Concurrent',
  'active',
  current_date
from public.profiles as p
where p.owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

do $$
declare
  owner_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  owner_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  family_id uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  profile_a uuid;
  profile_b uuid;
  treatment_id uuid := gen_random_uuid();
  medicine_id uuid := gen_random_uuid();
  schedule_id uuid := gen_random_uuid();
  log_id uuid := gen_random_uuid();
  log_alias uuid := gen_random_uuid();
  stale_treatment uuid := gen_random_uuid();
  retry_id uuid := gen_random_uuid();
  tombstone_id uuid := gen_random_uuid();
  parent_id uuid := gen_random_uuid();
  child_id uuid := gen_random_uuid();
  partial_treatment uuid := gen_random_uuid();
  partial_medicine uuid := gen_random_uuid();
  concurrent_id uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  mutation_1 uuid := gen_random_uuid();
  mutation_retry uuid := gen_random_uuid();
  mutation_stale uuid := gen_random_uuid();
  mutation_dup uuid := gen_random_uuid();
  mutation_tomb uuid := gen_random_uuid();
  mutation_parent uuid := gen_random_uuid();
  mutation_child uuid := gen_random_uuid();
  mutation_log uuid := gen_random_uuid();
  mutation_alias uuid := gen_random_uuid();
  mutation_partial_t uuid := gen_random_uuid();
  mutation_partial_m uuid := gen_random_uuid();
  mutation_conc_a uuid := gen_random_uuid();
  mutation_conc_b uuid := gen_random_uuid();
  result jsonb;
  retry jsonb;
  stale jsonb;
  dup jsonb;
  reused jsonb;
  tomb jsonb;
  parent_deleted jsonb;
  slot jsonb;
  unauthorized_text text;
  leaked int;
  persisted_version bigint;
  persisted_title text;
  capabilities jsonb;
  writes_enforced boolean;
  consumption boolean;
  conn text := 'dbname=' || current_database();
  applied_count int;
  conflict_count int;
begin
  perform sync_protocol_test.clear_auth();
  perform sync_protocol_test.ensure_user(owner_a, 'owner-a@isolated.test', 'Owner A');
  perform sync_protocol_test.ensure_user(owner_b, 'owner-b@isolated.test', 'Owner B');

  select id into profile_a from public.profiles where owner_id = owner_a;
  select id into profile_b from public.profiles where owner_id = owner_b;
  perform sync_protocol_test.assert(profile_a is not null, 'owner A profile missing');
  perform sync_protocol_test.assert(profile_b is not null, 'owner B profile missing');

  update public.profiles
  set extra_family_id = family_id, extra_family_name = 'Isolated family'
  where owner_id = owner_a
    and extra_family_id is distinct from family_id;

  perform sync_protocol_test.set_auth(owner_a);

  -- 1. Correct expected version is applied and increments sync_version.
  result := public.apply_sync_mutation_v1(
    mutation_1, 'treatment', treatment_id, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('title', 'Cardio', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform sync_protocol_test.assert(result->>'outcome' = 'applied', '1 applied: ' || result::text);
  perform sync_protocol_test.assert((result->>'committed_version')::bigint = 1, '1 version 1');
  result := public.apply_sync_mutation_v1(
    gen_random_uuid(), 'treatment', treatment_id, owner_a, profile_a, 'upsert', 1,
    jsonb_build_object('title', 'Cardio v2', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform sync_protocol_test.assert(result->>'outcome' = 'applied', '1 update applied');
  perform sync_protocol_test.assert((result->>'committed_version')::bigint = 2, '1 incremented');
  select t.sync_version, t.title into persisted_version, persisted_title
  from public.treatments as t where t.id = treatment_id;
  perform sync_protocol_test.assert(persisted_version = 2 and persisted_title = 'Cardio v2', '1 persisted increment');

  -- 2. Stale expected version returns conflict and does not write.
  result := public.apply_sync_mutation_v1(
    gen_random_uuid(), 'treatment', stale_treatment, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('title', 'Stale base', 'status', 'active', 'start_date', '2026-10-11')
  );
  stale := public.apply_sync_mutation_v1(
    mutation_stale, 'treatment', stale_treatment, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('title', 'Should not write', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform sync_protocol_test.assert(stale->>'outcome' = 'conflict', '2 conflict');
  perform sync_protocol_test.assert(stale->>'reason' = 'stale_version', '2 stale_version');
  select t.title into persisted_title from public.treatments as t where t.id = stale_treatment;
  perform sync_protocol_test.assert(persisted_title = 'Stale base', '2 did not write');

  -- 3. Duplicate mutation UUID + identical fingerprint returns the stored receipt.
  result := public.apply_sync_mutation_v1(
    mutation_retry, 'treatment', retry_id, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('title', 'Retry', 'status', 'active', 'start_date', '2026-10-11')
  );
  retry := public.apply_sync_mutation_v1(
    mutation_retry, 'treatment', retry_id, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('title', 'Retry', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform sync_protocol_test.assert(retry = result, '3 identical receipt replay');
  perform sync_protocol_test.assert(
    (select count(*) from public.treatments where id = retry_id) = 1,
    '3 no duplicate row'
  );

  -- 4. Duplicate mutation UUID + different payload returns invalid.
  reused := public.apply_sync_mutation_v1(
    mutation_retry, 'treatment', retry_id, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('title', 'Different', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform sync_protocol_test.assert(reused->>'outcome' = 'invalid', '4 invalid reuse');
  perform sync_protocol_test.assert(reused->>'reason' = 'mutation_id_reused', '4 mutation_id_reused');
  select t.title into persisted_title from public.treatments as t where t.id = retry_id;
  perform sync_protocol_test.assert(persisted_title = 'Retry', '4 original row unchanged');

  -- 5. Lost acknowledgement retry uses the original mutation UUID.
  perform sync_protocol_test.assert(retry->>'mutation_id' = mutation_retry::text, '5 same mutation id');
  perform sync_protocol_test.assert((retry->>'committed_version')::bigint = 1, '5 original version');

  -- 6. Live upsert against a tombstone is rejected.
  perform public.apply_sync_mutation_v1(
    mutation_tomb, 'treatment', tombstone_id, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('title', 'Tombstone', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform public.apply_sync_mutation_v1(
    gen_random_uuid(), 'treatment', tombstone_id, owner_a, profile_a, 'delete', 1,
    '{}'::jsonb
  );
  tomb := public.apply_sync_mutation_v1(
    gen_random_uuid(), 'treatment', tombstone_id, owner_a, profile_a, 'upsert', 2,
    jsonb_build_object('title', 'Revive', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform sync_protocol_test.assert(tomb->>'outcome' = 'conflict', '6 tombstone conflict');
  perform sync_protocol_test.assert(tomb->>'reason' = 'record_deleted', '6 record_deleted');
  perform sync_protocol_test.assert(
    (select deleted_at is not null from public.treatments where id = tombstone_id),
    '6 remains deleted'
  );

  -- 7. Descendant upsert under a deleted parent returns parent_deleted.
  perform public.apply_sync_mutation_v1(
    mutation_parent, 'treatment', parent_id, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('title', 'Parent', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform public.apply_sync_mutation_v1(
    gen_random_uuid(), 'treatment', parent_id, owner_a, profile_a, 'delete', 1,
    '{}'::jsonb
  );
  parent_deleted := public.apply_sync_mutation_v1(
    mutation_child, 'medicine', child_id, owner_a, profile_a, 'upsert', 0,
    sync_protocol_test.medicine_payload(parent_id)
  );
  perform sync_protocol_test.assert(parent_deleted->>'outcome' = 'parent_deleted', '7 parent_deleted');
  perform sync_protocol_test.assert(
    not exists (select 1 from public.medicines where id = child_id),
    '7 child not inserted'
  );

  -- 8. Cross-owner and invalid-subject calls raise unauthorized and leak no row.
  begin
    perform public.apply_sync_mutation_v1(
      gen_random_uuid(), 'treatment', gen_random_uuid(), owner_b, profile_b, 'upsert', 0,
      jsonb_build_object('title', 'Leak', 'status', 'active', 'start_date', '2026-10-11')
    );
    perform sync_protocol_test.fail('8 cross-owner did not raise');
  exception
    when insufficient_privilege then
      unauthorized_text := sqlerrm;
  end;
  perform sync_protocol_test.assert(unauthorized_text = 'sync mutation unauthorized', '8 unauthorized text');
  select count(*) into leaked
  from public.treatments
  where title = 'Leak';
  perform sync_protocol_test.assert(leaked = 0, '8 no leaked row');

  begin
    unauthorized_text := null;
    perform public.apply_sync_mutation_v1(
      gen_random_uuid(), 'treatment', gen_random_uuid(), owner_a,
      '99999999-9999-9999-9999-999999999999', 'upsert', 0,
      jsonb_build_object('title', 'Bad subject', 'status', 'active', 'start_date', '2026-10-11')
    );
    perform sync_protocol_test.fail('8 invalid subject did not raise');
  exception
    when insufficient_privilege then
      unauthorized_text := sqlerrm;
  end;
  perform sync_protocol_test.assert(unauthorized_text = 'sync mutation unauthorized', '8 invalid subject');

  result := public.apply_sync_mutation_v1(
    gen_random_uuid(), 'treatment', gen_random_uuid(), owner_a, family_id, 'upsert', 0,
    jsonb_build_object('title', 'Family seat', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform sync_protocol_test.assert(result->>'outcome' = 'applied', '8 extra-family subject allowed');

  -- 11 first: later descendant failure does not retract ancestors.
  perform public.apply_sync_mutation_v1(
    mutation_partial_t, 'treatment', partial_treatment, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('title', 'Partial', 'status', 'active', 'start_date', '2026-10-11')
  );
  perform public.apply_sync_mutation_v1(
    mutation_partial_m, 'medicine', partial_medicine, owner_a, profile_a, 'upsert', 0,
    sync_protocol_test.medicine_payload(partial_treatment)
  );
  result := public.apply_sync_mutation_v1(
    gen_random_uuid(), 'schedule', gen_random_uuid(), owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('medicine_id', partial_medicine, 'time_of_day', '08:00')
  );
  perform sync_protocol_test.assert(result->>'outcome' = 'invalid', '11 descendant invalid');
  perform sync_protocol_test.assert(
    exists (select 1 from public.treatments where id = partial_treatment and deleted_at is null)
      and exists (select 1 from public.medicines where id = partial_medicine and deleted_at is null),
    '11 ancestors remain'
  );

  -- Hierarchy for DoseLog slot.
  result := public.apply_sync_mutation_v1(
    gen_random_uuid(), 'medicine', medicine_id, owner_a, profile_a, 'upsert', 0,
    sync_protocol_test.medicine_payload(treatment_id)
  );
  perform sync_protocol_test.assert(result->>'outcome' = 'applied', 'medicine applied: ' || result::text);
  result := public.apply_sync_mutation_v1(
    gen_random_uuid(), 'schedule', schedule_id, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object('medicine_id', medicine_id, 'time_of_day', '08:00', 'period', 'Morning')
  );
  perform sync_protocol_test.assert(result->>'outcome' = 'applied', 'schedule applied: ' || result::text);

  -- 10. Same-slot DoseLog create returns the canonical UUID.
  result := public.apply_sync_mutation_v1(
    mutation_log, 'doseLog', log_id, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object(
      'schedule_id', schedule_id,
      'scheduled_at', '2026-10-11T08:00:00+00:00',
      'status', 'pending'
    )
  );
  perform sync_protocol_test.assert(result->>'outcome' = 'applied', '10 first log: ' || result::text);
  slot := public.apply_sync_mutation_v1(
    mutation_alias, 'doseLog', log_alias, owner_a, profile_a, 'upsert', 0,
    jsonb_build_object(
      'schedule_id', schedule_id,
      'scheduled_at', '2026-10-11T08:00:30+00:00',
      'status', 'pending'
    )
  );
  perform sync_protocol_test.assert(slot->>'outcome' = 'already_applied', '10 already_applied');
  perform sync_protocol_test.assert(slot->>'canonical_entity_id' = log_id::text, '10 canonical UUID');
  perform sync_protocol_test.assert(
    not exists (select 1 from public.dose_logs where id = log_alias),
    '10 alias not inserted'
  );

  -- 9. Concurrent same-row updates serialize; one applies, one conflicts.
  -- The row is committed in the harness setup so dblink sessions can see it.
  perform dblink_connect('sync_a', conn);
  perform dblink_connect('sync_b', conn);
  perform dblink_send_query('sync_a', format(
    $q$select public.apply_sync_mutation_v1(
         %L::uuid, 'treatment', %L::uuid, %L::uuid, %L::uuid, 'upsert', 1,
         '{"title":"Concurrent A","status":"active","start_date":"2026-10-11"}'::jsonb
       )
       from (
         select set_config('request.jwt.claim.sub', %L, true) as sub,
                set_config('request.jwt.claims', %L, true) as claims
       ) as auth_setup;$q$,
    mutation_conc_a, concurrent_id, owner_a, profile_a,
    owner_a::text,
    json_build_object('sub', owner_a, 'role', 'authenticated')::text
  ));
  perform dblink_send_query('sync_b', format(
    $q$select public.apply_sync_mutation_v1(
         %L::uuid, 'treatment', %L::uuid, %L::uuid, %L::uuid, 'upsert', 1,
         '{"title":"Concurrent B","status":"active","start_date":"2026-10-11"}'::jsonb
       )
       from (
         select set_config('request.jwt.claim.sub', %L, true) as sub,
                set_config('request.jwt.claims', %L, true) as claims
       ) as auth_setup;$q$,
    mutation_conc_b, concurrent_id, owner_a, profile_a,
    owner_a::text,
    json_build_object('sub', owner_a, 'role', 'authenticated')::text
  ));
  perform (select t.result from dblink_get_result('sync_a') as t(result jsonb));
  perform (select t.result from dblink_get_result('sync_b') as t(result jsonb));
  perform dblink_disconnect('sync_a');
  perform dblink_disconnect('sync_b');

  select count(*) into applied_count
  from public.sync_mutation_receipts
  where mutation_id in (mutation_conc_a, mutation_conc_b)
    and outcome = 'applied';
  select count(*) into conflict_count
  from public.sync_mutation_receipts
  where mutation_id in (mutation_conc_a, mutation_conc_b)
    and outcome = 'conflict';
  perform sync_protocol_test.assert(applied_count = 1, '9 one applied, got ' || applied_count);
  perform sync_protocol_test.assert(conflict_count = 1, '9 one conflict, got ' || conflict_count);
  perform sync_protocol_test.assert(
    (select sync_version from public.treatments where id = concurrent_id) = 2,
    '9 final version 2'
  );

  capabilities := public.sync_protocol_capabilities_v1();
  writes_enforced := coalesce((capabilities->>'direct_writes_enforced')::boolean, false);
  consumption := coalesce((capabilities->>'outbox_consumption_enabled')::boolean, true);
  perform sync_protocol_test.assert(
    (capabilities->>'protocol_version')::int = 1
      and (capabilities->>'mutation_rpc_available')::boolean,
    'capabilities protocol ready'
  );
  perform sync_protocol_test.assert(consumption = false, 'consumption stays false until activation');

  if not writes_enforced then
    -- 12. Direct table writes remain possible after expansion.
    perform set_config('role', 'authenticated', true);
    insert into public.treatments (
      id, owner_id, profile_id, subject_profile_id, title, status, start_date
    ) values (
      gen_random_uuid(), owner_a, profile_a, profile_a, 'Legacy write', 'active', current_date
    );
    perform set_config('role', 'postgres', true);
    perform sync_protocol_test.assert(
      exists (select 1 from public.treatments where title = 'Legacy write'),
      '12 legacy write after expansion'
    );
    raise notice 'PASS expansion cases 1-12; consumption=false enforced=false';
  else
    -- 13. After enforcement, direct writes are denied and consumption remains false.
    begin
      perform set_config('role', 'authenticated', true);
      insert into public.treatments (
        id, owner_id, profile_id, subject_profile_id, title, status, start_date
      ) values (
        gen_random_uuid(), owner_a, profile_a, profile_a, 'Should deny', 'active', current_date
      );
      perform set_config('role', 'postgres', true);
      perform sync_protocol_test.fail('13 legacy write succeeded after enforcement');
    exception
      when insufficient_privilege then
        perform set_config('role', 'postgres', true);
    end;
    perform sync_protocol_test.assert(
      not exists (select 1 from public.treatments where title = 'Should deny'),
      '13 no legacy row'
    );
    perform sync_protocol_test.assert(writes_enforced, '13 direct_writes_enforced');
    perform sync_protocol_test.assert(consumption = false, '13 consumption still false');
    raise notice 'PASS enforcement cases 13; consumption=false enforced=true';
  end if;

  perform sync_protocol_test.clear_auth();
end;
$$;

select 'sync_protocol_v1_isolated: executable isolated fixture' as fixture;
