-- Adds read-only decision workspaces for VMS, Workflow, and SMIS.

create or replace function public.vms_get_fleet_health_workspace(
  p_keyword text default null,
  p_risk_level text default null,
  p_from integer default 0,
  p_to integer default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(200, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not app_private.has_permission('VehicleFleetHealth:View') then
    raise exception 'Missing fleet health view permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;
  if nullif(btrim(p_risk_level), '') is not null
     and p_risk_level not in ('critical', 'high', 'medium', 'low') then
    raise exception 'Invalid fleet health risk level';
  end if;

  with insurance as materialized (
    select
      vehicle_id,
      max(commercial_expire_date) as commercial_expire_date,
      max(compulsory_expire_date) as compulsory_expire_date
    from public.vehicle_insurance
    where app_private.is_platform_super() or tenant_id = v_tenant_id
    group by vehicle_id
  ), inspection as materialized (
    select vehicle_id, max(expire_date) as expire_date
    from public.vehicle_inspection
    where app_private.is_platform_super() or tenant_id = v_tenant_id
    group by vehicle_id
  ), maintenance as materialized (
    select vehicle_id, max(start_time)::date as last_maintenance_date
    from public.vehicle_maintenance_record
    where (app_private.is_platform_super() or tenant_id = v_tenant_id)
      and maintenance_type = 'maintenance'
    group by vehicle_id
  ), accident as materialized (
    select vehicle_id, count(*) filter (where not coalesce(processed, false))::integer as unresolved_count
    from public.vehicle_accident_record
    where app_private.is_platform_super() or tenant_id = v_tenant_id
    group by vehicle_id
  ), routine as materialized (
    select
      vehicle_id,
      count(*) filter (
        where check_result = 'unqualified'
          and inspection_time >= pg_catalog.now() - interval '90 days'
      )::integer as failed_count
    from public.vehicle_routine_inspection_record
    where app_private.is_platform_super() or tenant_id = v_tenant_id
    group by vehicle_id
  ), work_order as materialized (
    select
      vehicle_id,
      count(*) filter (where status in ('pending', 'in_progress'))::integer as open_count
    from public.vehicle_reminder_work_order
    where app_private.is_platform_super() or tenant_id = v_tenant_id
    group by vehicle_id
  ), source_rows as materialized (
    select
      vehicle_row.id as vehicle_id,
      vehicle_row.plate_no,
      vehicle_row.company_name,
      vehicle_row.vehicle_type,
      vehicle_row.operation_status,
      vehicle_row.update_time,
      case
        when insurance.commercial_expire_date is null then insurance.compulsory_expire_date
        when insurance.compulsory_expire_date is null then insurance.commercial_expire_date
        else least(insurance.commercial_expire_date, insurance.compulsory_expire_date)
      end as insurance_expire_date,
      inspection.expire_date as inspection_expire_date,
      maintenance.last_maintenance_date,
      coalesce(accident.unresolved_count, 0) as unresolved_accident_count,
      coalesce(routine.failed_count, 0) as failed_inspection_count,
      coalesce(work_order.open_count, 0) as open_work_order_count
    from public.vehicle_archive vehicle_row
    left join insurance on insurance.vehicle_id = vehicle_row.id
    left join inspection on inspection.vehicle_id = vehicle_row.id
    left join maintenance on maintenance.vehicle_id = vehicle_row.id
    left join accident on accident.vehicle_id = vehicle_row.id
    left join routine on routine.vehicle_id = vehicle_row.id
    left join work_order on work_order.vehicle_id = vehicle_row.id
    where (app_private.is_platform_super() or vehicle_row.tenant_id = v_tenant_id)
      and vehicle_row.audit_status = 'approved'
      and (
        nullif(btrim(p_keyword), '') is null
        or vehicle_row.plate_no ilike '%' || btrim(p_keyword) || '%'
        or vehicle_row.company_name ilike '%' || btrim(p_keyword) || '%'
      )
  ), scored as materialized (
    select
      source_rows.*,
      case when insurance_expire_date is null then null else insurance_expire_date - current_date end
        as insurance_days_remaining,
      case when inspection_expire_date is null then null else inspection_expire_date - current_date end
        as inspection_days_remaining,
      case when last_maintenance_date is null then null else current_date - last_maintenance_date end
        as days_since_maintenance,
      (
        case
          when insurance_expire_date is null then 18
          when insurance_expire_date < current_date then 40
          when insurance_expire_date <= current_date + 30 then 20
          else 0
        end
        + case
            when inspection_expire_date is null then 18
            when inspection_expire_date < current_date then 40
            when inspection_expire_date <= current_date + 30 then 20
            else 0
          end
        + case
            when last_maintenance_date is null then 18
            when last_maintenance_date < current_date - 180 then 18
            else 0
          end
        + least(unresolved_accident_count * 12, 36)
        + least(failed_inspection_count * 10, 20)
        + least(open_work_order_count * 4, 12)
      )::integer as risk_score
    from source_rows
  ), classified as materialized (
    select
      scored.*,
      case
        when risk_score >= 50 then 'critical'
        when risk_score >= 30 then 'high'
        when risk_score >= 15 then 'medium'
        else 'low'
      end as risk_level,
      greatest(0, 100 - risk_score)::integer as health_score,
      array_remove(array[
        case when insurance_expire_date is null then '保险资料缺失'
             when insurance_expire_date < current_date then '保险已过期'
             when insurance_expire_date <= current_date + 30 then '保险 30 天内到期' end,
        case when inspection_expire_date is null then '年检资料缺失'
             when inspection_expire_date < current_date then '年检已过期'
             when inspection_expire_date <= current_date + 30 then '年检 30 天内到期' end,
        case when last_maintenance_date is null then '缺少保养记录'
             when last_maintenance_date < current_date - 180 then '超过 180 天未保养' end,
        case when unresolved_accident_count > 0 then unresolved_accident_count || ' 起事故待处理' end,
        case when failed_inspection_count > 0 then failed_inspection_count || ' 次例检不合格' end,
        case when open_work_order_count > 0 then open_work_order_count || ' 个提醒工单待处理' end
      ], null) as issues
    from scored
  ), filtered as materialized (
    select *
    from classified
    where nullif(btrim(p_risk_level), '') is null or risk_level = p_risk_level
  ), paged as (
    select *
    from filtered
    order by risk_score desc, update_time desc, vehicle_id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select pg_catalog.jsonb_build_object(
    'records', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'vehicleId', paged.vehicle_id,
          'plateNo', paged.plate_no,
          'companyName', paged.company_name,
          'vehicleType', paged.vehicle_type,
          'operationStatus', paged.operation_status,
          'riskLevel', paged.risk_level,
          'riskScore', paged.risk_score,
          'healthScore', paged.health_score,
          'insuranceDaysRemaining', paged.insurance_days_remaining,
          'inspectionDaysRemaining', paged.inspection_days_remaining,
          'daysSinceMaintenance', paged.days_since_maintenance,
          'unresolvedAccidentCount', paged.unresolved_accident_count,
          'failedInspectionCount', paged.failed_inspection_count,
          'openWorkOrderCount', paged.open_work_order_count,
          'issueCount', pg_catalog.cardinality(paged.issues),
          'issues', pg_catalog.to_jsonb(paged.issues),
          'updateTime', paged.update_time
        ) order by paged.risk_score desc, paged.update_time desc, paged.vehicle_id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'overview', pg_catalog.jsonb_build_object(
      'total', (select count(*) from classified),
      'critical', (select count(*) from classified where risk_level = 'critical'),
      'high', (select count(*) from classified where risk_level = 'high'),
      'medium', (select count(*) from classified where risk_level = 'medium'),
      'low', (select count(*) from classified where risk_level = 'low'),
      'openWorkOrders', (select coalesce(sum(open_work_order_count), 0) from classified)
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.vms_get_fleet_health_workspace(text, text, integer, integer)
  from public, anon;
grant execute on function public.vms_get_fleet_health_workspace(text, text, integer, integer)
  to authenticated, service_role;

comment on function public.vms_get_fleet_health_workspace(text, text, integer, integer) is
  'Returns a tenant-safe, bounded fleet health decision workspace without exposing sensitive vehicle fields.';

insert into public.sys_dict_type (
  id, name, code, status, remark, tenant_id, create_by, create_time, update_by, update_time
)
values (
  'd1000000-0000-4000-8200-000000000001'::uuid,
  '车队健康风险', 'vmsFleetHealthRisk', '1', '车队健康中心风险分级',
  app_private.platform_tenant_id(), '624944977@qq.com', now(), '624944977@qq.com', now()
)
on conflict (code) do update set
  name = excluded.name,
  status = excluded.status,
  remark = excluded.remark,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_dictionary (
  id, type_id, code, value, label, status, sort, tag_type, tenant_id,
  create_by, create_time, update_by, update_time, i18n_scope
)
select
  item.id,
  type_row.id,
  item.code,
  item.value,
  item.label,
  '1',
  item.sort,
  item.tag_type,
  type_row.tenant_id,
  '624944977@qq.com', now(), '624944977@qq.com', now(), '1'
from public.sys_dict_type type_row
cross join (values
  ('d1000000-0000-4000-8210-000000000001'::uuid, 'vmsFleetHealthRisk_critical', 'critical', '严重', 1, 'danger'),
  ('d1000000-0000-4000-8210-000000000002'::uuid, 'vmsFleetHealthRisk_high', 'high', '高风险', 2, 'warning'),
  ('d1000000-0000-4000-8210-000000000003'::uuid, 'vmsFleetHealthRisk_medium', 'medium', '需关注', 3, 'primary'),
  ('d1000000-0000-4000-8210-000000000004'::uuid, 'vmsFleetHealthRisk_low', 'low', '健康', 4, 'success')
) as item(id, code, value, label, sort, tag_type)
where type_row.code = 'vmsFleetHealthRisk'
on conflict (id) do update set
  type_id = excluded.type_id,
  code = excluded.code,
  value = excluded.value,
  label = excluded.label,
  status = excluded.status,
  sort = excluded.sort,
  tag_type = excluded.tag_type,
  tenant_id = excluded.tenant_id,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_menu (
  id, parent_id, name, path, component, type, app_code, sort, meta,
  create_by, create_time, update_by, update_time
)
values
  (
    'd1000000-0000-4000-8000-000000000001'::uuid,
    '200d5e4c-b49d-49b5-962f-cd1c6744b637'::uuid,
    'VehicleFleetHealth', 'fleet-health', '/vms/fleet-health', 'menu', 'vms', 3,
    '{"icon":"ri:heart-pulse-line","title":"车队健康中心","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'd1000000-0000-4000-8100-000000000001'::uuid,
    'd1000000-0000-4000-8000-000000000001'::uuid,
    'VehicleFleetHealth:View', '', '', 'button', 'vms', 1,
    '{"icon":"","title":"查看车队健康","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'd2000000-0000-4000-8000-000000000001'::uuid,
    'adcddc55-d5a2-4e11-872e-86156d2b7d36'::uuid,
    'WorkflowAnalytics', 'analytics', '/workflow/analytics', 'menu', 'platform', 4,
    '{"icon":"ri:bar-chart-grouped-line","title":"审批效能","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'd2000000-0000-4000-8100-000000000001'::uuid,
    'd2000000-0000-4000-8000-000000000001'::uuid,
    'WorkflowAnalytics:View', '', '', 'button', 'platform', 1,
    '{"icon":"","title":"查看审批效能","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  )
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  path = excluded.path,
  component = excluded.component,
  type = excluded.type,
  app_code = excluded.app_code,
  sort = excluded.sort,
  meta = excluded.meta,
  update_by = excluded.update_by,
  update_time = now();

-- The training report keeps its route and grants but now renders a specialized workspace.
update public.sys_menu
set component = '/smis/training-analytics',
    meta = jsonb_set(meta, '{icon}', '"ri:graduation-cap-line"'::jsonb, true),
    update_by = 'migration',
    update_time = now()
where name = 'SmisDocTrainingAnalysis'
  and type = 'menu';

with grants(source_menu_id, target_menu_id) as (
  values
    ('e28af17e-c201-4604-84bb-b4db4eca4db6'::uuid, 'd1000000-0000-4000-8000-000000000001'::uuid),
    ('1ce2adc1-e434-4100-bea3-537d708bb0bd'::uuid, 'd1000000-0000-4000-8100-000000000001'::uuid),
    ('2c9439d4-fb40-4676-935f-cbd225f6003b'::uuid, 'd2000000-0000-4000-8000-000000000001'::uuid),
    ('2c9439d4-fb40-4676-935f-cbd225f6003b'::uuid, 'd2000000-0000-4000-8100-000000000001'::uuid)
)
insert into public.sys_role_menu (
  permission, create_by, create_time, role_id, menu_id, update_by, update_time, tenant_id
)
select
  source.permission,
  'migration', now(), source.role_id, grants.target_menu_id, 'migration', now(), source.tenant_id
from grants
join public.sys_role_menu source on source.menu_id = grants.source_menu_id
on conflict (role_id, menu_id) do update set
  permission = excluded.permission,
  update_by = excluded.update_by,
  update_time = now(),
  tenant_id = excluded.tenant_id;

;
