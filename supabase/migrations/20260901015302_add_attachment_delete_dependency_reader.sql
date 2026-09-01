create or replace function public.get_attachment_delete_dependency_details(
  p_resource_ids uuid[]
)
returns table(
  resource_id uuid,
  dependency_code text,
  record_id uuid,
  target_id uuid,
  record_no text,
  record_summary text,
  record_status text,
  record_amount numeric,
  created_at timestamptz,
  cleanup_allowed boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if to_regclass('public.tms_waybill_proof') is null then
    return;
  end if;

  return query execute $query$
    with requested as (
      select attachment.id as resource_id
      from public.sys_attachment attachment
      where attachment.id = any(coalesce($1, '{}'::uuid[]))
        and (
          app_private.is_platform_super()
          or attachment.tenant_id = app_private.current_user_tenant_id()
        )
    )
    select
      proof.attachment_id,
      'attachment_waybill_proof'::text,
      proof.id,
      proof.waybill_id,
      coalesce(nullif(proof.file_name, ''), proof.id::text),
      proof.proof_type,
      null::text,
      null::numeric,
      proof.create_time,
      false
    from public.tms_waybill_proof proof
    join requested on requested.resource_id = proof.attachment_id
    where app_private.is_platform_super()
      or proof.tenant_id = app_private.current_user_tenant_id()
    order by proof.attachment_id, proof.create_time desc, proof.id
  $query$ using p_resource_ids;
end;
$function$;

revoke all on function public.get_attachment_delete_dependency_details(uuid[]) from public;
grant execute on function public.get_attachment_delete_dependency_details(uuid[])
  to authenticated, service_role;

comment on function public.get_attachment_delete_dependency_details(uuid[]) is
  'Returns tenant-scoped attachment references for governed deletion without exposing the source table.';;
