create or replace function app_private.hr_performance_level_for_score(p_score numeric)
returns text language sql immutable set search_path = '' as $function$
  select case
    when p_score >= 95 then 's'
    when p_score >= 85 then 'a'
    when p_score >= 70 then 'b'
    when p_score >= 60 then 'c'
    else 'd'
  end
$function$;

revoke all on function app_private.hr_performance_level_for_score(numeric)
  from public, anon, authenticated;

create or replace function public.hr_performance_overview_secure(p_tenant_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_featured public.hr_performance_cycle%rowtype;
begin
  if not app_private.can_execute_business_action('HrPerformance', 'Hr:Performance:View', null, false) then
    raise exception '当前账号没有查看绩效管理工作台的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  select c.* into v_featured
  from public.hr_performance_cycle c
  where (p_tenant_id is null or c.tenant_id = p_tenant_id)
    and c.status in ('active', 'reviewing')
  order by c.start_date desc, c.create_time desc
  limit 1;

  return jsonb_build_object(
    'active_cycle_count', (
      select count(*) from public.hr_performance_cycle c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and c.status in ('active', 'reviewing')
    ),
    'in_scope_employee_count', (
      select count(*) from public.hr_performance_review r
      where (p_tenant_id is null or r.tenant_id = p_tenant_id)
        and r.status <> 'cancelled'
        and (v_featured.id is null or r.cycle_id = v_featured.id)
    ),
    'completion_rate', (
      select coalesce(round(100 * count(*) filter (where r.status = 'completed')::numeric
        / nullif(count(*) filter (where r.status <> 'cancelled'), 0), 1), 0)
      from public.hr_performance_review r
      where (p_tenant_id is null or r.tenant_id = p_tenant_id)
        and (v_featured.id is null or r.cycle_id = v_featured.id)
    ),
    'at_risk_check_in_count', (
      with latest as (
        select distinct on (c.review_id) c.review_id, c.risk_status
        from public.hr_performance_check_in c
        join public.hr_performance_review r on r.id = c.review_id and r.tenant_id = c.tenant_id
        where (p_tenant_id is null or c.tenant_id = p_tenant_id)
          and (v_featured.id is null or r.cycle_id = v_featured.id)
        order by c.review_id, c.check_in_date desc, c.create_time desc
      )
      select count(*) from latest where risk_status in ('attention', 'off_track')
    ),
    'pending_calibration_count', (
      select count(*) from public.hr_performance_review r
      where (p_tenant_id is null or r.tenant_id = p_tenant_id)
        and r.status = 'confirmed'
        and (v_featured.id is null or r.cycle_id = v_featured.id)
    ),
    'featured_cycle', case when v_featured.id is null then null else jsonb_build_object(
      'id', v_featured.id,
      'cycle_code', v_featured.cycle_code,
      'cycle_name', v_featured.cycle_name,
      'status', v_featured.status,
      'start_date', v_featured.start_date,
      'end_date', v_featured.end_date,
      'goal_setting_count', (select count(*) from public.hr_performance_review r
        where r.tenant_id = v_featured.tenant_id and r.cycle_id = v_featured.id
          and r.status in ('draft', 'self_review')),
      'manager_review_count', (select count(*) from public.hr_performance_review r
        where r.tenant_id = v_featured.tenant_id and r.cycle_id = v_featured.id
          and r.status = 'manager_review'),
      'calibration_count', (select count(*) from public.hr_performance_review r
        where r.tenant_id = v_featured.tenant_id and r.cycle_id = v_featured.id
          and r.status = 'confirmed'),
      'completed_count', (select count(*) from public.hr_performance_review r
        where r.tenant_id = v_featured.tenant_id and r.cycle_id = v_featured.id
          and r.status = 'completed')
    ) end
  );
end
$function$;

create or replace function public.hr_list_performance_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_cycle_id uuid default null,
  p_session_id uuid default null,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_result jsonb;
begin
  if p_kind not in ('cycle', 'review', 'goal', 'check_in', 'calibration', 'calibration_item') then
    raise exception '不支持的绩效记录类型';
  end if;
  if not app_private.can_execute_business_action('HrPerformance', 'Hr:Performance:View', null, false) then
    raise exception '当前账号没有查看绩效管理工作台的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'cycle' then
    with filtered as materialized (
      select c.*, owner.employee_no owner_no, owner.employee_name owner_name,
        (select count(*) from public.hr_performance_review r where r.cycle_id=c.id and r.tenant_id=c.tenant_id and r.status<>'cancelled') review_count,
        (select count(*) from public.hr_performance_review r where r.cycle_id=c.id and r.tenant_id=c.tenant_id and r.status='completed') completed_count,
        (select count(*) from public.hr_performance_review r where r.cycle_id=c.id and r.tenant_id=c.tenant_id and r.status='confirmed') pending_calibration_count
      from public.hr_performance_cycle c
      left join public.hr_employee owner on owner.id=c.owner_employee_id and owner.tenant_id=c.tenant_id
      where (p_tenant_id is null or c.tenant_id=p_tenant_id)
        and (p_status is null or c.status=p_status)
        and (v_keyword is null or c.cycle_code ilike '%'||v_keyword||'%'
          or c.cycle_name ilike '%'||v_keyword||'%' or owner.employee_name ilike '%'||v_keyword||'%')
    ), paged as (
      select * from filtered order by start_date desc, cycle_code offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg((to_jsonb(paged)-'owner_no'-'owner_name') || jsonb_build_object(
        'owner', case when owner_employee_id is null then null else jsonb_build_object('id',owner_employee_id,'code',owner_no,'name',owner_name) end
      ) order by start_date desc, cycle_code), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  if p_kind = 'review' then
    with latest_check_in as (
      select distinct on (c.review_id) c.review_id, c.check_in_date, c.risk_status, c.progress_percent
      from public.hr_performance_check_in c
      order by c.review_id, c.check_in_date desc, c.create_time desc
    ), filtered as materialized (
      select r.*, c.cycle_code, c.cycle_name, e.employee_no, e.employee_name,
        e.organization_id, o.organization_name, reviewer.employee_no reviewer_no,
        reviewer.employee_name reviewer_name,
        coalesce(g.goal_count,0) goal_count, coalesce(g.goal_weight,0) goal_weight,
        ci.check_in_date last_check_in_date, ci.risk_status latest_risk_status,
        ci.progress_percent latest_progress_percent
      from public.hr_performance_review r
      join public.hr_performance_cycle c on c.id=r.cycle_id and c.tenant_id=r.tenant_id
      join public.hr_employee e on e.id=r.employee_id and e.tenant_id=r.tenant_id
      left join public.sys_organization o on o.id=e.organization_id and o.tenant_id=e.tenant_id
      left join public.hr_employee reviewer on reviewer.id=r.reviewer_employee_id and reviewer.tenant_id=r.tenant_id
      left join lateral (
        select count(*)::integer goal_count, coalesce(sum(weight),0)::numeric goal_weight
        from public.hr_performance_goal g where g.review_id=r.id and g.tenant_id=r.tenant_id
      ) g on true
      left join latest_check_in ci on ci.review_id=r.id
      where (p_tenant_id is null or r.tenant_id=p_tenant_id)
        and (p_cycle_id is null or r.cycle_id=p_cycle_id)
        and (p_status is null or r.status=p_status)
        and (v_keyword is null or e.employee_no ilike '%'||v_keyword||'%'
          or e.employee_name ilike '%'||v_keyword||'%' or c.cycle_name ilike '%'||v_keyword||'%'
          or o.organization_name ilike '%'||v_keyword||'%')
    ), paged as (
      select * from filtered order by cycle_name desc, employee_no offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg((to_jsonb(paged)-'cycle_code'-'cycle_name'-'employee_no'-'employee_name'
        -'organization_id'-'organization_name'-'reviewer_no'-'reviewer_name') || jsonb_build_object(
          'cycle',jsonb_build_object('id',cycle_id,'code',cycle_code,'name',cycle_name),
          'employee',jsonb_build_object('id',employee_id,'code',employee_no,'name',employee_name),
          'organization',case when organization_id is null then null else jsonb_build_object('id',organization_id,'name',organization_name) end,
          'reviewer',case when reviewer_employee_id is null then null else jsonb_build_object('id',reviewer_employee_id,'code',reviewer_no,'name',reviewer_name) end
        ) order by cycle_name desc, employee_no), '[]'::jsonb),
      'total',(select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  if p_kind = 'goal' then
    with filtered as materialized (
      select g.*, r.employee_id, r.cycle_id, r.status review_status,
        e.employee_no, e.employee_name, c.cycle_code, c.cycle_name
      from public.hr_performance_goal g
      join public.hr_performance_review r on r.id=g.review_id and r.tenant_id=g.tenant_id
      join public.hr_employee e on e.id=r.employee_id and e.tenant_id=r.tenant_id
      join public.hr_performance_cycle c on c.id=r.cycle_id and c.tenant_id=r.tenant_id
      where (p_tenant_id is null or g.tenant_id=p_tenant_id)
        and (p_cycle_id is null or r.cycle_id=p_cycle_id)
        and (p_status is null or g.status=p_status)
        and (v_keyword is null or g.goal_name ilike '%'||v_keyword||'%'
          or g.target_description ilike '%'||v_keyword||'%' or e.employee_name ilike '%'||v_keyword||'%')
    ), paged as (
      select * from filtered order by due_date nulls last, goal_name offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records',coalesce(jsonb_agg((to_jsonb(paged)-'employee_no'-'employee_name'-'cycle_code'-'cycle_name') || jsonb_build_object(
        'employee',jsonb_build_object('id',employee_id,'code',employee_no,'name',employee_name),
        'cycle',jsonb_build_object('id',cycle_id,'code',cycle_code,'name',cycle_name)
      ) order by due_date nulls last, goal_name),'[]'::jsonb),
      'total',(select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  if p_kind = 'check_in' then
    with filtered as materialized (
      select ci.*, r.employee_id, r.cycle_id, e.employee_no, e.employee_name,
        c.cycle_code, c.cycle_name, facilitator.employee_no facilitator_no,
        facilitator.employee_name facilitator_name
      from public.hr_performance_check_in ci
      join public.hr_performance_review r on r.id=ci.review_id and r.tenant_id=ci.tenant_id
      join public.hr_employee e on e.id=r.employee_id and e.tenant_id=r.tenant_id
      join public.hr_performance_cycle c on c.id=r.cycle_id and c.tenant_id=r.tenant_id
      left join public.hr_employee facilitator on facilitator.id=ci.facilitator_employee_id and facilitator.tenant_id=ci.tenant_id
      where (p_tenant_id is null or ci.tenant_id=p_tenant_id)
        and (p_cycle_id is null or r.cycle_id=p_cycle_id)
        and (p_status is null or ci.risk_status=p_status)
        and (v_keyword is null or e.employee_no ilike '%'||v_keyword||'%'
          or e.employee_name ilike '%'||v_keyword||'%' or ci.achievement ilike '%'||v_keyword||'%'
          or ci.next_action ilike '%'||v_keyword||'%')
    ), paged as (
      select * from filtered order by check_in_date desc, create_time desc offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records',coalesce(jsonb_agg((to_jsonb(paged)-'employee_no'-'employee_name'-'cycle_code'-'cycle_name'-'facilitator_no'-'facilitator_name') || jsonb_build_object(
        'employee',jsonb_build_object('id',employee_id,'code',employee_no,'name',employee_name),
        'cycle',jsonb_build_object('id',cycle_id,'code',cycle_code,'name',cycle_name),
        'facilitator',case when facilitator_employee_id is null then null else jsonb_build_object('id',facilitator_employee_id,'code',facilitator_no,'name',facilitator_name) end
      ) order by check_in_date desc, create_time desc),'[]'::jsonb),
      'total',(select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  if p_kind = 'calibration' then
    with filtered as materialized (
      select s.*, c.cycle_code, c.cycle_name, o.organization_code, o.organization_name,
        facilitator.employee_no facilitator_no, facilitator.employee_name facilitator_name,
        (select count(*) from public.hr_performance_calibration_item i where i.session_id=s.id and i.tenant_id=s.tenant_id) item_count,
        (select count(*) from public.hr_performance_calibration_item i where i.session_id=s.id and i.tenant_id=s.tenant_id
          and (i.calibrated_score<>i.original_score or i.calibrated_level<>i.original_level)) adjusted_count
      from public.hr_performance_calibration_session s
      join public.hr_performance_cycle c on c.id=s.cycle_id and c.tenant_id=s.tenant_id
      left join public.sys_organization o on o.id=s.organization_id and o.tenant_id=s.tenant_id
      left join public.hr_employee facilitator on facilitator.id=s.facilitator_employee_id and facilitator.tenant_id=s.tenant_id
      where (p_tenant_id is null or s.tenant_id=p_tenant_id)
        and (p_cycle_id is null or s.cycle_id=p_cycle_id)
        and (p_status is null or s.status=p_status)
        and (v_keyword is null or s.session_no ilike '%'||v_keyword||'%'
          or s.session_name ilike '%'||v_keyword||'%' or c.cycle_name ilike '%'||v_keyword||'%'
          or o.organization_name ilike '%'||v_keyword||'%')
    ), paged as (
      select * from filtered order by scheduled_at desc, session_no offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records',coalesce(jsonb_agg((to_jsonb(paged)-'cycle_code'-'cycle_name'-'organization_code'-'organization_name'-'facilitator_no'-'facilitator_name') || jsonb_build_object(
        'cycle',jsonb_build_object('id',cycle_id,'code',cycle_code,'name',cycle_name),
        'organization',case when organization_id is null then null else jsonb_build_object('id',organization_id,'code',organization_code,'name',organization_name) end,
        'facilitator',case when facilitator_employee_id is null then null else jsonb_build_object('id',facilitator_employee_id,'code',facilitator_no,'name',facilitator_name) end
      ) order by scheduled_at desc, session_no),'[]'::jsonb),
      'total',(select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  with filtered as materialized (
    select i.*, s.session_no, s.session_name, r.employee_id, r.cycle_id,
      e.employee_no, e.employee_name, c.cycle_code, c.cycle_name
    from public.hr_performance_calibration_item i
    join public.hr_performance_calibration_session s on s.id=i.session_id and s.tenant_id=i.tenant_id
    join public.hr_performance_review r on r.id=i.review_id and r.tenant_id=i.tenant_id
    join public.hr_employee e on e.id=r.employee_id and e.tenant_id=i.tenant_id
    join public.hr_performance_cycle c on c.id=r.cycle_id and c.tenant_id=i.tenant_id
    where (p_tenant_id is null or i.tenant_id=p_tenant_id)
      and (p_session_id is null or i.session_id=p_session_id)
      and (p_cycle_id is null or r.cycle_id=p_cycle_id)
      and (p_status is null or i.calibrated_level=p_status)
      and (v_keyword is null or e.employee_no ilike '%'||v_keyword||'%'
        or e.employee_name ilike '%'||v_keyword||'%' or s.session_name ilike '%'||v_keyword||'%')
  ), paged as (
    select * from filtered order by calibrated_score desc, employee_no offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records',coalesce(jsonb_agg((to_jsonb(paged)-'session_no'-'session_name'-'employee_no'-'employee_name'-'cycle_code'-'cycle_name') || jsonb_build_object(
      'session',jsonb_build_object('id',session_id,'code',session_no,'name',session_name),
      'employee',jsonb_build_object('id',employee_id,'code',employee_no,'name',employee_name),
      'cycle',jsonb_build_object('id',cycle_id,'code',cycle_code,'name',cycle_name)
    ) order by calibrated_score desc, employee_no),'[]'::jsonb),
    'total',(select count(*) from filtered)
  ) into v_result from paged;
  return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
end
$function$;

create or replace function public.hr_list_performance_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if p_kind not in ('cycle','review','employee','organization','calibration') then
    raise exception '不支持的绩效选项类型';
  end if;
  if not app_private.can_execute_business_action('HrPerformance','Hr:Performance:View',null,false) then
    raise exception '当前账号没有查看绩效选项的权限' using errcode='42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id:=v_tenant_id; end if;

  if p_kind='cycle' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'tenant_id',c.tenant_id,'code',c.cycle_code,'name',c.cycle_name,'status',c.status) order by c.start_date desc),'[]'::jsonb)
      from public.hr_performance_cycle c where (p_tenant_id is null or c.tenant_id=p_tenant_id) and c.status<>'cancelled');
  end if;
  if p_kind='review' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'tenant_id',r.tenant_id,'name',e.employee_name,'code',e.employee_no,'status',r.status,'cycle_id',r.cycle_id) order by e.employee_name),'[]'::jsonb)
      from public.hr_performance_review r join public.hr_employee e on e.id=r.employee_id and e.tenant_id=r.tenant_id
      where (p_tenant_id is null or r.tenant_id=p_tenant_id) and r.status<>'cancelled');
  end if;
  if p_kind='employee' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'tenant_id',e.tenant_id,'code',e.employee_no,'name',e.employee_name,'organization_id',e.organization_id) order by e.employee_name),'[]'::jsonb)
      from public.hr_employee e where (p_tenant_id is null or e.tenant_id=p_tenant_id)
        and e.employment_status not in ('left','terminated'));
  end if;
  if p_kind='organization' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'tenant_id',o.tenant_id,'code',o.organization_code,'name',o.organization_name) order by o.sort,o.organization_name),'[]'::jsonb)
      from public.sys_organization o where (p_tenant_id is null or o.tenant_id=p_tenant_id) and o.status='1');
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'tenant_id',s.tenant_id,'code',s.session_no,'name',s.session_name,'status',s.status,'cycle_id',s.cycle_id) order by s.scheduled_at desc),'[]'::jsonb)
    from public.hr_performance_calibration_session s where (p_tenant_id is null or s.tenant_id=p_tenant_id) and s.status='in_progress');
end
$function$;

create or replace function public.hr_save_performance_record_secure(
  p_kind text,
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_permission text := case when p_id is null then 'Hr:Performance:Add' else 'Hr:Performance:Edit' end;
  v_cycle public.hr_performance_cycle%rowtype;
  v_review public.hr_performance_review%rowtype;
  v_goal public.hr_performance_goal%rowtype;
  v_check_in public.hr_performance_check_in%rowtype;
  v_session public.hr_performance_calibration_session%rowtype;
  v_item public.hr_performance_calibration_item%rowtype;
begin
  if p_kind not in ('cycle','review','goal','check_in','calibration','calibration_item') then
    raise exception '不支持的绩效记录类型';
  end if;
  if p_kind='calibration_item' then v_permission:='Hr:Performance:Calibrate'; end if;
  if not app_private.can_execute_business_action('HrPerformance',v_permission,null,false) then
    raise exception '当前账号没有执行该绩效操作的权限' using errcode='42501';
  end if;
  if app_private.is_platform_super() and nullif(p_payload->>'tenant_id','') is not null then
    v_tenant_id := (p_payload->>'tenant_id')::uuid;
  end if;

  if p_kind='cycle' then
    if p_id is not null then
      select * into v_cycle from public.hr_performance_cycle where id=p_id and tenant_id=v_tenant_id for update;
      if not found then raise exception '绩效周期不存在'; end if;
      if v_cycle.status<>'draft' then raise exception '只有草稿周期可以修改'; end if;
      update public.hr_performance_cycle set
        cycle_code=btrim(p_payload->>'cycle_code'), cycle_name=btrim(p_payload->>'cycle_name'),
        start_date=(p_payload->>'start_date')::date, end_date=(p_payload->>'end_date')::date,
        owner_employee_id=nullif(p_payload->>'owner_employee_id','')::uuid,
        check_in_frequency_days=coalesce((p_payload->>'check_in_frequency_days')::integer,30),
        self_review_due_date=nullif(p_payload->>'self_review_due_date','')::date,
        manager_review_due_date=nullif(p_payload->>'manager_review_due_date','')::date,
        calibration_due_date=nullif(p_payload->>'calibration_due_date','')::date,
        description=nullif(btrim(p_payload->>'description'),'')
      where id=p_id returning * into v_cycle;
    else
      insert into public.hr_performance_cycle(
        tenant_id,cycle_code,cycle_name,start_date,end_date,owner_employee_id,
        check_in_frequency_days,self_review_due_date,manager_review_due_date,calibration_due_date,status,description
      ) values (
        v_tenant_id,btrim(p_payload->>'cycle_code'),btrim(p_payload->>'cycle_name'),
        (p_payload->>'start_date')::date,(p_payload->>'end_date')::date,
        nullif(p_payload->>'owner_employee_id','')::uuid,
        coalesce((p_payload->>'check_in_frequency_days')::integer,30),
        nullif(p_payload->>'self_review_due_date','')::date,
        nullif(p_payload->>'manager_review_due_date','')::date,
        nullif(p_payload->>'calibration_due_date','')::date,'draft',nullif(btrim(p_payload->>'description'),'')
      ) returning * into v_cycle;
    end if;
    return v_cycle.id;
  end if;

  if p_kind='review' then
    select * into v_cycle from public.hr_performance_cycle
      where id=(p_payload->>'cycle_id')::uuid and tenant_id=v_tenant_id;
    if not found or v_cycle.status not in ('draft','active') then raise exception '只能在草稿或执行中的周期安排员工考核'; end if;
    if p_id is not null then
      select * into v_review from public.hr_performance_review where id=p_id and tenant_id=v_tenant_id for update;
      if not found then raise exception '员工考核不存在'; end if;
      if v_review.status<>'draft' then raise exception '只有目标设定阶段可以修改考核对象'; end if;
      update public.hr_performance_review set
        cycle_id=(p_payload->>'cycle_id')::uuid, employee_id=(p_payload->>'employee_id')::uuid,
        reviewer_employee_id=nullif(p_payload->>'reviewer_employee_id','')::uuid
      where id=p_id returning * into v_review;
    else
      insert into public.hr_performance_review(tenant_id,cycle_id,employee_id,reviewer_employee_id,status)
      values(v_tenant_id,(p_payload->>'cycle_id')::uuid,(p_payload->>'employee_id')::uuid,
        nullif(p_payload->>'reviewer_employee_id','')::uuid,'draft') returning * into v_review;
    end if;
    return v_review.id;
  end if;

  if p_kind='goal' then
    select r.* into v_review from public.hr_performance_review r
      where r.id=(p_payload->>'review_id')::uuid and r.tenant_id=v_tenant_id for update;
    if not found then raise exception '员工考核不存在'; end if;
    if v_review.status not in ('draft','self_review','manager_review') then raise exception '当前阶段不能修改绩效目标'; end if;
    if p_id is not null then
      select * into v_goal from public.hr_performance_goal where id=p_id and tenant_id=v_tenant_id for update;
      if not found or v_goal.review_id<>v_review.id then raise exception '绩效目标不存在'; end if;
      update public.hr_performance_goal set
        goal_name=case when v_review.status='draft' then btrim(p_payload->>'goal_name') else goal_name end,
        target_description=case when v_review.status='draft' then btrim(p_payload->>'target_description') else target_description end,
        goal_type=case when v_review.status='draft' then coalesce(nullif(p_payload->>'goal_type',''),'business') else goal_type end,
        weight=case when v_review.status='draft' then coalesce((p_payload->>'weight')::numeric,0) else weight end,
        due_date=case when v_review.status='draft' then nullif(p_payload->>'due_date','')::date else due_date end,
        progress_percent=coalesce((p_payload->>'progress_percent')::numeric,progress_percent),
        status=coalesce(nullif(p_payload->>'status',''),status),
        actual_result=nullif(btrim(p_payload->>'actual_result'),''),
        evidence_source=nullif(btrim(p_payload->>'evidence_source'),''),
        employee_score=case when v_review.status='self_review' then nullif(p_payload->>'employee_score','')::numeric else employee_score end,
        manager_score=case when v_review.status='manager_review' then nullif(p_payload->>'manager_score','')::numeric else manager_score end
      where id=p_id returning * into v_goal;
    else
      if v_review.status<>'draft' then raise exception '只能在目标设定阶段新增目标'; end if;
      insert into public.hr_performance_goal(
        tenant_id,review_id,goal_name,target_description,goal_type,weight,due_date,
        progress_percent,status,actual_result,evidence_source
      ) values (
        v_tenant_id,v_review.id,btrim(p_payload->>'goal_name'),btrim(p_payload->>'target_description'),
        coalesce(nullif(p_payload->>'goal_type',''),'business'),coalesce((p_payload->>'weight')::numeric,0),
        nullif(p_payload->>'due_date','')::date,coalesce((p_payload->>'progress_percent')::numeric,0),
        coalesce(nullif(p_payload->>'status',''),'draft'),nullif(btrim(p_payload->>'actual_result'),''),
        nullif(btrim(p_payload->>'evidence_source'),'')
      ) returning * into v_goal;
    end if;
    return v_goal.id;
  end if;

  if p_kind='check_in' then
    select * into v_review from public.hr_performance_review
      where id=(p_payload->>'review_id')::uuid and tenant_id=v_tenant_id for update;
    if not found or v_review.status not in ('self_review','manager_review') then
      raise exception '只有执行中的考核可以登记绩效沟通';
    end if;
    if p_id is null then
      insert into public.hr_performance_check_in(
        tenant_id,review_id,check_in_date,progress_percent,risk_status,achievement,blocker,
        next_action,manager_feedback,facilitator_employee_id
      ) values (
        v_tenant_id,v_review.id,coalesce(nullif(p_payload->>'check_in_date','')::date,current_date),
        coalesce((p_payload->>'progress_percent')::numeric,0),coalesce(nullif(p_payload->>'risk_status',''),'on_track'),
        nullif(btrim(p_payload->>'achievement'),''),nullif(btrim(p_payload->>'blocker'),''),
        btrim(p_payload->>'next_action'),nullif(btrim(p_payload->>'manager_feedback'),''),
        nullif(p_payload->>'facilitator_employee_id','')::uuid
      ) returning * into v_check_in;
    else
      update public.hr_performance_check_in set
        check_in_date=coalesce(nullif(p_payload->>'check_in_date','')::date,check_in_date),
        progress_percent=coalesce((p_payload->>'progress_percent')::numeric,progress_percent),
        risk_status=coalesce(nullif(p_payload->>'risk_status',''),risk_status),
        achievement=nullif(btrim(p_payload->>'achievement'),''), blocker=nullif(btrim(p_payload->>'blocker'),''),
        next_action=btrim(p_payload->>'next_action'),manager_feedback=nullif(btrim(p_payload->>'manager_feedback'),''),
        facilitator_employee_id=nullif(p_payload->>'facilitator_employee_id','')::uuid
      where id=p_id and tenant_id=v_tenant_id returning * into v_check_in;
      if not found or v_check_in.review_id<>v_review.id then raise exception '绩效沟通记录不存在'; end if;
    end if;
    update public.hr_performance_goal set progress_percent=v_check_in.progress_percent,
      status=case when v_check_in.progress_percent>=100 then 'completed'
        when v_check_in.risk_status='off_track' then 'at_risk' else 'in_progress' end
    where tenant_id=v_tenant_id and review_id=v_review.id and status<>'completed';
    return v_check_in.id;
  end if;

  if p_kind='calibration' then
    select * into v_cycle from public.hr_performance_cycle
      where id=(p_payload->>'cycle_id')::uuid and tenant_id=v_tenant_id;
    if not found or v_cycle.status not in ('active','reviewing') then raise exception '只能为执行或评议中的周期创建校准会议'; end if;
    if p_id is not null then
      select * into v_session from public.hr_performance_calibration_session where id=p_id and tenant_id=v_tenant_id for update;
      if not found then raise exception '绩效校准会议不存在'; end if;
      if v_session.status<>'setup' then raise exception '只有筹备中的校准会议可以修改'; end if;
      update public.hr_performance_calibration_session set
        session_no=btrim(p_payload->>'session_no'),session_name=btrim(p_payload->>'session_name'),
        cycle_id=v_cycle.id,organization_id=nullif(p_payload->>'organization_id','')::uuid,
        facilitator_employee_id=nullif(p_payload->>'facilitator_employee_id','')::uuid,
        scheduled_at=(p_payload->>'scheduled_at')::timestamptz,
        distribution_note=nullif(btrim(p_payload->>'distribution_note'),'')
      where id=p_id returning * into v_session;
    else
      insert into public.hr_performance_calibration_session(
        tenant_id,session_no,session_name,cycle_id,organization_id,facilitator_employee_id,
        scheduled_at,status,distribution_note
      ) values (
        v_tenant_id,btrim(p_payload->>'session_no'),btrim(p_payload->>'session_name'),v_cycle.id,
        nullif(p_payload->>'organization_id','')::uuid,nullif(p_payload->>'facilitator_employee_id','')::uuid,
        (p_payload->>'scheduled_at')::timestamptz,'setup',nullif(btrim(p_payload->>'distribution_note'),'')
      ) returning * into v_session;
    end if;
    return v_session.id;
  end if;

  if p_id is null then raise exception '校准评分只能修改现有记录'; end if;
  select i.* into v_item from public.hr_performance_calibration_item i
    join public.hr_performance_calibration_session s on s.id=i.session_id and s.tenant_id=i.tenant_id
    where i.id=p_id and i.tenant_id=v_tenant_id and s.status='in_progress' for update of i;
  if not found then raise exception '校准评分不存在或会议已结束'; end if;
  update public.hr_performance_calibration_item set
    calibrated_score=(p_payload->>'calibrated_score')::numeric,
    calibrated_level=coalesce(nullif(p_payload->>'calibrated_level',''),
      app_private.hr_performance_level_for_score((p_payload->>'calibrated_score')::numeric)),
    adjustment_reason=nullif(btrim(p_payload->>'adjustment_reason'),'')
  where id=p_id returning * into v_item;
  return v_item.id;
end
$function$;

create or replace function public.hr_transition_performance_cycle_secure(
  p_id uuid,
  p_action text,
  p_comment text default null
)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cycle public.hr_performance_cycle%rowtype;
  v_permission text := case when p_action in ('activate','begin_review') then 'Hr:Performance:Activate' else 'Hr:Performance:Complete' end;
  v_review_count integer;
begin
  if p_action not in ('activate','begin_review','complete','cancel') then raise exception '不支持的绩效周期动作'; end if;
  if not app_private.can_execute_business_action('HrPerformance',v_permission,null,false) then
    raise exception '当前账号没有推进绩效周期的权限' using errcode='42501';
  end if;
  select * into v_cycle from public.hr_performance_cycle
    where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id) for update;
  if not found then raise exception '绩效周期不存在'; end if;

  if p_action='activate' then
    if v_cycle.status<>'draft' then raise exception '只有草稿周期可以启动'; end if;
    select count(*) into v_review_count from public.hr_performance_review r
      where r.cycle_id=v_cycle.id and r.tenant_id=v_cycle.tenant_id and r.status='draft';
    if v_review_count=0 then raise exception '启动周期前至少安排一名员工考核'; end if;
    if exists (
      select 1 from public.hr_performance_review r
      left join public.hr_performance_goal g on g.review_id=r.id and g.tenant_id=r.tenant_id
      where r.cycle_id=v_cycle.id and r.tenant_id=v_cycle.tenant_id and r.status='draft'
      group by r.id having count(g.id)=0 or coalesce(sum(g.weight),0)<>100
    ) then raise exception '每位员工至少维护一项目标，且目标权重合计必须为 100%%'; end if;
    update public.hr_performance_cycle set status='active',activated_at=now(),description=coalesce(description,p_comment) where id=v_cycle.id;
    update public.hr_performance_review set status='self_review',submitted_at=now()
      where cycle_id=v_cycle.id and tenant_id=v_cycle.tenant_id and status='draft';
    update public.hr_performance_goal set status='in_progress'
      where tenant_id=v_cycle.tenant_id and review_id in (select id from public.hr_performance_review where cycle_id=v_cycle.id and tenant_id=v_cycle.tenant_id);
    return true;
  end if;
  if p_action='begin_review' then
    if v_cycle.status<>'active' then raise exception '只有执行中的周期可以进入评议'; end if;
    if exists (select 1 from public.hr_performance_review where cycle_id=v_cycle.id and tenant_id=v_cycle.tenant_id and status in ('draft','self_review')) then
      raise exception '仍有员工未完成自评，不能进入周期评议';
    end if;
    update public.hr_performance_cycle set status='reviewing' where id=v_cycle.id;
    return true;
  end if;
  if p_action='complete' then
    if v_cycle.status not in ('active','reviewing') then raise exception '当前周期不能完成'; end if;
    if exists (select 1 from public.hr_performance_review where cycle_id=v_cycle.id and tenant_id=v_cycle.tenant_id and status not in ('completed','cancelled')) then
      raise exception '仍有员工绩效结果未完成';
    end if;
    update public.hr_performance_cycle set status='completed',completed_at=now() where id=v_cycle.id;
    return true;
  end if;
  if v_cycle.status not in ('draft','active') then raise exception '当前周期不能取消'; end if;
  if nullif(btrim(p_comment),'') is null then raise exception '取消周期必须填写原因'; end if;
  update public.hr_performance_cycle set status='cancelled',description=concat_ws(E'\n',description,'取消原因：'||btrim(p_comment)) where id=v_cycle.id;
  update public.hr_performance_review set status='cancelled' where cycle_id=v_cycle.id and tenant_id=v_cycle.tenant_id and status<>'completed';
  return true;
end
$function$;

create or replace function public.hr_transition_performance_review_secure(
  p_id uuid,
  p_action text,
  p_comment text default null
)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_review public.hr_performance_review%rowtype;
  v_permission text := case when p_action in ('submit_self','submit_manager') then 'Hr:Performance:Review' else 'Hr:Performance:Complete' end;
  v_score numeric;
begin
  if p_action not in ('submit_self','submit_manager','complete') then raise exception '不支持的员工考核动作'; end if;
  if not app_private.can_execute_business_action('HrPerformance',v_permission,null,false) then
    raise exception '当前账号没有推进员工考核的权限' using errcode='42501';
  end if;
  select * into v_review from public.hr_performance_review
    where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id) for update;
  if not found then raise exception '员工考核不存在'; end if;

  if p_action='submit_self' then
    if v_review.status<>'self_review' then raise exception '当前考核不在员工自评阶段'; end if;
    if nullif(btrim(p_comment),'') is null then raise exception '提交自评前请填写员工总结'; end if;
    if exists (select 1 from public.hr_performance_goal where review_id=v_review.id and tenant_id=v_review.tenant_id and employee_score is null) then
      raise exception '请完成全部目标的员工自评分';
    end if;
    select round(sum(weight*employee_score)/nullif(sum(weight),0),2) into v_score
      from public.hr_performance_goal where review_id=v_review.id and tenant_id=v_review.tenant_id;
    update public.hr_performance_review set status='manager_review',employee_summary=btrim(p_comment),self_score=v_score
      where id=v_review.id;
    return true;
  end if;
  if p_action='submit_manager' then
    if v_review.status<>'manager_review' then raise exception '当前考核不在主管评价阶段'; end if;
    if nullif(btrim(p_comment),'') is null then raise exception '提交主管评价前请填写评价意见'; end if;
    if exists (select 1 from public.hr_performance_goal where review_id=v_review.id and tenant_id=v_review.tenant_id and manager_score is null) then
      raise exception '请完成全部目标的主管评分';
    end if;
    select round(sum(weight*manager_score)/nullif(sum(weight),0),2) into v_score
      from public.hr_performance_goal where review_id=v_review.id and tenant_id=v_review.tenant_id;
    update public.hr_performance_review set status='confirmed',reviewer_comment=btrim(p_comment),
      manager_score=v_score,total_score=v_score,performance_level=app_private.hr_performance_level_for_score(v_score),
      manager_reviewed_at=now(),confirmed_at=now() where id=v_review.id;
    return true;
  end if;
  if v_review.status<>'confirmed' then raise exception '只有待校准结果可以直接完成'; end if;
  update public.hr_performance_review set status='completed',completed_at=now() where id=v_review.id;
  return true;
end
$function$;

create or replace function public.hr_transition_performance_calibration_secure(
  p_id uuid,
  p_action text,
  p_comment text default null
)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_session public.hr_performance_calibration_session%rowtype;
  v_item_count integer;
begin
  if p_action not in ('start','approve','deactivate') then raise exception '不支持的绩效校准动作'; end if;
  if not app_private.can_execute_business_action('HrPerformance','Hr:Performance:Calibrate',null,false) then
    raise exception '当前账号没有执行绩效校准的权限' using errcode='42501';
  end if;
  select * into v_session from public.hr_performance_calibration_session
    where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id) for update;
  if not found then raise exception '绩效校准会议不存在'; end if;

  if p_action='start' then
    if v_session.status<>'setup' then raise exception '只有筹备中的会议可以开始校准'; end if;
    insert into public.hr_performance_calibration_item(
      tenant_id,session_id,review_id,original_score,original_level,calibrated_score,calibrated_level
    )
    select r.tenant_id,v_session.id,r.id,r.manager_score,r.performance_level,r.manager_score,r.performance_level
    from public.hr_performance_review r
    join public.hr_employee e on e.id=r.employee_id and e.tenant_id=r.tenant_id
    where r.tenant_id=v_session.tenant_id and r.cycle_id=v_session.cycle_id and r.status='confirmed'
      and (v_session.organization_id is null or e.organization_id=v_session.organization_id)
    on conflict (tenant_id,session_id,review_id) do nothing;
    get diagnostics v_item_count = row_count;
    if v_item_count=0 and not exists (select 1 from public.hr_performance_calibration_item where session_id=v_session.id and tenant_id=v_session.tenant_id) then
      raise exception '当前范围没有待校准的员工绩效结果';
    end if;
    update public.hr_performance_calibration_session set status='in_progress' where id=v_session.id;
    update public.hr_performance_cycle set status='reviewing'
      where id=v_session.cycle_id and tenant_id=v_session.tenant_id and status='active';
    return true;
  end if;
  if p_action='approve' then
    if v_session.status<>'in_progress' then raise exception '只有校准中的会议可以定案'; end if;
    if nullif(btrim(p_comment),'') is null then raise exception '校准定案必须填写会议结论'; end if;
    if exists (
      select 1 from public.hr_performance_calibration_item i
      where i.session_id=v_session.id and i.tenant_id=v_session.tenant_id
        and (i.calibrated_score<>i.original_score or i.calibrated_level<>i.original_level)
        and nullif(btrim(i.adjustment_reason),'') is null
    ) then raise exception '发生评分调整时必须逐项填写调整依据'; end if;
    update public.hr_performance_review r set
      calibrated_score=i.calibrated_score,calibrated_level=i.calibrated_level,
      calibration_comment=i.adjustment_reason,total_score=i.calibrated_score,
      performance_level=i.calibrated_level,status='completed',completed_at=now()
    from public.hr_performance_calibration_item i
    where i.session_id=v_session.id and i.tenant_id=v_session.tenant_id
      and r.id=i.review_id and r.tenant_id=i.tenant_id;
    update public.hr_performance_calibration_session set status='approved',approved_at=now(),decision_note=btrim(p_comment)
      where id=v_session.id;
    return true;
  end if;
  if v_session.status<>'setup' then raise exception '只有筹备中的会议可以停用'; end if;
  if nullif(btrim(p_comment),'') is null then raise exception '停用会议必须填写原因'; end if;
  update public.hr_performance_calibration_session set status='deactivated',decision_note=btrim(p_comment) where id=v_session.id;
  return true;
end
$function$;

create or replace function public.hr_delete_performance_record_secure(p_kind text,p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if p_kind not in ('cycle','review','goal','check_in','calibration') then raise exception '不支持删除该绩效记录'; end if;
  if not app_private.can_execute_business_action('HrPerformance','Hr:Performance:Delete',null,false) then
    raise exception '当前账号没有删除绩效记录的权限' using errcode='42501';
  end if;
  if p_kind='cycle' then
    delete from public.hr_performance_cycle where id=p_id
      and (app_private.is_platform_super() or tenant_id=v_tenant_id) and status='draft';
  elsif p_kind='review' then
    delete from public.hr_performance_review where id=p_id
      and (app_private.is_platform_super() or tenant_id=v_tenant_id) and status='draft';
  elsif p_kind='goal' then
    delete from public.hr_performance_goal g using public.hr_performance_review r
      where g.id=p_id and g.review_id=r.id and g.tenant_id=r.tenant_id
        and (app_private.is_platform_super() or g.tenant_id=v_tenant_id) and r.status='draft';
  elsif p_kind='check_in' then
    delete from public.hr_performance_check_in ci using public.hr_performance_review r
      where ci.id=p_id and ci.review_id=r.id and ci.tenant_id=r.tenant_id
        and (app_private.is_platform_super() or ci.tenant_id=v_tenant_id)
        and r.status in ('self_review','manager_review');
  else
    delete from public.hr_performance_calibration_session where id=p_id
      and (app_private.is_platform_super() or tenant_id=v_tenant_id) and status='setup';
  end if;
  if not found then raise exception '记录不存在或当前阶段不允许删除'; end if;
  return true;
end
$function$;

revoke all on function public.hr_performance_overview_secure(uuid) from public, anon, authenticated;
revoke all on function public.hr_list_performance_records_secure(text,integer,integer,text,text,uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.hr_list_performance_options_secure(text,uuid) from public, anon, authenticated;
revoke all on function public.hr_save_performance_record_secure(text,uuid,jsonb) from public, anon, authenticated;
revoke all on function public.hr_transition_performance_cycle_secure(uuid,text,text) from public, anon, authenticated;
revoke all on function public.hr_transition_performance_review_secure(uuid,text,text) from public, anon, authenticated;
revoke all on function public.hr_transition_performance_calibration_secure(uuid,text,text) from public, anon, authenticated;
revoke all on function public.hr_delete_performance_record_secure(text,uuid) from public, anon, authenticated;

grant execute on function public.hr_performance_overview_secure(uuid) to authenticated, service_role;
grant execute on function public.hr_list_performance_records_secure(text,integer,integer,text,text,uuid,uuid,uuid) to authenticated, service_role;
grant execute on function public.hr_list_performance_options_secure(text,uuid) to authenticated, service_role;
grant execute on function public.hr_save_performance_record_secure(text,uuid,jsonb) to authenticated, service_role;
grant execute on function public.hr_transition_performance_cycle_secure(uuid,text,text) to authenticated, service_role;
grant execute on function public.hr_transition_performance_review_secure(uuid,text,text) to authenticated, service_role;
grant execute on function public.hr_transition_performance_calibration_secure(uuid,text,text) to authenticated, service_role;
grant execute on function public.hr_delete_performance_record_secure(text,uuid) to authenticated, service_role;
