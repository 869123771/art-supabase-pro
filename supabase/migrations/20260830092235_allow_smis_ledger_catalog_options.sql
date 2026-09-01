begin;

create or replace function public.smis_list_qualification_catalog_secure(
  p_catalog_type text,
  p_from integer default 0,
  p_to integer default 99,
  p_keyword text default null,
  p_status text default null,
  p_ancestor_id uuid default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 99), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
  v_permission text := app_private.smis_catalog_permission(p_catalog_type, 'View');
  v_can_view boolean;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看安全资质基础数据' using errcode='42501';
  end if;
  if p_purpose not in ('list','export','option') then
    raise exception '查询用途无效' using errcode='22023';
  end if;

  v_can_view := (select app_private.is_platform_super())
    or app_private.has_permission(v_permission)
    or (
      p_purpose = 'option'
      and app_private.has_permission('SmisPersonnelCertificateLedger:View')
    );
  if v_permission is null or not v_can_view then
    raise exception '当前账号没有查看该基础数据的权限' using errcode='42501';
  end if;
  if p_purpose = 'export'
     and not app_private.has_permission(app_private.smis_catalog_permission(p_catalog_type, 'Export')) then
    raise exception '当前账号没有导出该基础数据的权限' using errcode='42501';
  end if;

  return (
    with recursive source as (
      select c.*,
        (select count(*) from public.smis_qualification_catalog child
         where child.tenant_id=c.tenant_id and child.parent_id=c.id)::integer child_count,
        (select p.item_name from public.smis_qualification_catalog p where p.id=c.parent_id) parent_name
      from public.smis_qualification_catalog c
      where c.tenant_id=app_private.current_read_tenant_id() and c.catalog_type=p_catalog_type
    ), subtree as (
      select id from source where id=p_ancestor_id
      union all select c.id from source c join subtree p on c.parent_id=p.id
    ), filtered as (
      select * from source
      where (p_ancestor_id is null or id in (select id from subtree))
        and (p_status is null or status=p_status)
        and (v_keyword is null or lower(item_code) like '%'||v_keyword||'%'
          or lower(item_name) like '%'||v_keyword||'%'
          or lower(coalesce(remark,'')) like '%'||v_keyword||'%')
    )
    select jsonb_build_object(
      'records', coalesce((select jsonb_agg(to_jsonb(r) order by r.sort,r."itemName") from (
        select id,tenant_id "tenantId",parent_id "parentId",parent_name "parentName",
          catalog_type "catalogType",item_code "itemCode",item_name "itemName",sort,status,remark,
          child_count "childCount",create_by "createBy",create_time "createTime",update_by "updateBy",update_time "updateTime"
        from filtered offset v_from limit v_to-v_from+1
      ) r),'[]'::jsonb),
      'total',(select count(*) from filtered),
      'tree',coalesce((select jsonb_agg(jsonb_build_object(
        'id',id,'parentId',parent_id,'catalogType',catalog_type,'itemCode',item_code,
        'itemName',item_name,'sort',sort,'status',status,'childCount',child_count
      ) order by sort,item_name) from source),'[]'::jsonb),
      'overview',(select jsonb_build_object(
        'total',count(*),'enabled',count(*) filter(where status='enabled'),
        'disabled',count(*) filter(where status='disabled'),
        'rootCount',count(*) filter(where parent_id is null)
      ) from source)
    )
  );
end;
$function$;

commit;

;
