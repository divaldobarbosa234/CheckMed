-- Batch 2B-3C explicit activation only. Do not apply until:
-- 1. isolated server protocol tests PASS,
-- 2. two-device and lost-acknowledgement runtime tests PASS,
-- 3. the minimum-supported-version boundary is approved, and
-- 4. a separate production cutover plan is authorized.
--
-- This file is not part of expansion or enforcement. Applying it is the
-- only server-side way to advertise outbox consumption after writes are
-- already revoked. Client builds still require their own authorization
-- flag before they will consume.

do $$
begin
  if has_table_privilege('authenticated', 'public.treatments', 'INSERT')
      or has_table_privilege('authenticated', 'public.medicines', 'INSERT')
      or has_table_privilege('authenticated', 'public.dose_schedules', 'INSERT')
      or has_table_privilege('authenticated', 'public.dose_logs', 'INSERT') then
    raise exception 'sync activation blocked: direct medication writes are still granted';
  end if;
end;
$$;

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
    'outbox_consumption_enabled',
      not (
        has_table_privilege('authenticated', 'public.treatments', 'INSERT,UPDATE,DELETE')
        or has_table_privilege('authenticated', 'public.medicines', 'INSERT,UPDATE,DELETE')
        or has_table_privilege('authenticated', 'public.dose_schedules', 'INSERT,UPDATE,DELETE')
        or has_table_privilege('authenticated', 'public.dose_logs', 'INSERT,UPDATE,DELETE')
      )
  );
$$;

revoke all on function public.sync_protocol_capabilities_v1() from public, anon;
grant execute on function public.sync_protocol_capabilities_v1() to authenticated;
