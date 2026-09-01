-- Keep one enterprise rule across all permission-managed tenant tables:
-- platform super administrators override the tenant predicate, while ordinary
-- users must still satisfy the original tenant, ownership, and button checks.
-- Policies without a managed business permission (personal AI history,
-- notifications, service-only access, and explicit direct-access denial) are
-- intentionally excluded.

do $$
declare
  policy_row record;
  alter_statement text;
begin
  for policy_row in
    select
      policy.schemaname,
      policy.tablename,
      policy.policyname,
      policy.qual,
      policy.with_check
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.cmd in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
      and exists (
        select 1
        from information_schema.columns column_row
        where column_row.table_schema = policy.schemaname
          and column_row.table_name = policy.tablename
          and column_row.column_name = 'tenant_id'
      )
      and (
        coalesce(policy.qual, '') ilike '%has_permission%'
        or coalesce(policy.with_check, '') ilike '%has_permission%'
      )
      and (
        coalesce(policy.qual, '') || ' ' || coalesce(policy.with_check, '')
      ) not ilike '%is_platform_super%'
    order by policy.tablename, policy.policyname
  loop
    alter_statement := format(
      'alter policy %I on %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );

    if policy_row.qual is not null then
      alter_statement := alter_statement || format(
        ' using ((select app_private.is_platform_super()) or (%s))',
        policy_row.qual
      );
    end if;

    if policy_row.with_check is not null then
      alter_statement := alter_statement || format(
        ' with check ((select app_private.is_platform_super()) or (%s))',
        policy_row.with_check
      );
    end if;

    execute alter_statement;
  end loop;
end;
$$;

;
