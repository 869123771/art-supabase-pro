-- Scope manual dispatch to the authorized tenant and backfill vehicle reminder subjects.

create or replace function app_private.process_notification_reminders_for_tenant(
  p_tenant_id uuid,
  p_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Shanghai')::date;
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 2000);
  v_created_events integer := 0;
  v_created_deliveries integer := 0;
  v_delivered_in_app integer := 0;
  v_delivery record;
begin
  if p_tenant_id is null or not exists (select 1 from public.sys_tenant where id = p_tenant_id) then
    raise exception 'Tenant not found';
  end if;

  insert into public.sys_notification_event (
    tenant_id, subject_id, rule_id, occurrence_date, scheduled_at,
    title, content, severity, status, create_by, update_by
  )
  select
    subject.tenant_id, subject.id, rule_row.id,
    case when rule_row.repeat_every_days is null
      then (subject.due_at at time zone 'Asia/Shanghai')::date - rule_row.lead_days
      else v_today end,
    (case when rule_row.repeat_every_days is null
      then (subject.due_at at time zone 'Asia/Shanghai')::date - rule_row.lead_days
      else v_today end + make_time(rule_row.send_hour, 0, 0)) at time zone 'Asia/Shanghai',
    subject.subject_title,
    case
      when (subject.due_at at time zone 'Asia/Shanghai')::date < v_today
        then subject.subject_title || '，已到期 ' || (v_today - (subject.due_at at time zone 'Asia/Shanghai')::date) || ' 天，请尽快处理。'
      when (subject.due_at at time zone 'Asia/Shanghai')::date = v_today
        then subject.subject_title || '，今天到期，请及时处理。'
      else subject.subject_title || '，还有 ' || ((subject.due_at at time zone 'Asia/Shanghai')::date - v_today) || ' 天到期，请提前处理。'
    end,
    case when (subject.due_at at time zone 'Asia/Shanghai')::date <= v_today then 'danger' else 'warning' end,
    'pending', 'system-reminder', 'system-reminder'
  from public.sys_notification_subject subject
  join public.sys_notification_rule rule_row
    on rule_row.tenant_id = subject.tenant_id
   and rule_row.scenario_id = subject.scenario_id
   and rule_row.enabled is true
  join public.sys_tenant tenant_row on tenant_row.id = subject.tenant_id and tenant_row.status = '1'
  where subject.tenant_id = p_tenant_id
    and subject.status = 'active'
    and v_today >= (subject.due_at at time zone 'Asia/Shanghai')::date - rule_row.lead_days
    and v_today <= (subject.due_at at time zone 'Asia/Shanghai')::date
    and (
      rule_row.repeat_every_days is null
      or mod(
        v_today - ((subject.due_at at time zone 'Asia/Shanghai')::date - rule_row.lead_days),
        rule_row.repeat_every_days
      ) = 0
    )
  on conflict (subject_id, rule_id, occurrence_date) do nothing;
  get diagnostics v_created_events = row_count;

  insert into public.sys_notification_delivery (
    tenant_id, event_id, recipient_user_id, channel_code, title, content,
    route_path, route_query, status, create_by, update_by
  )
  select distinct
    event_row.tenant_id, event_row.id, recipient.id, channel.channel_code,
    event_row.title, event_row.content, subject.route_path, subject.route_query,
    'pending', 'system-reminder', 'system-reminder'
  from public.sys_notification_event event_row
  join public.sys_notification_subject subject
    on subject.id = event_row.subject_id and subject.tenant_id = event_row.tenant_id
  join public.sys_notification_rule rule_row
    on rule_row.id = event_row.rule_id and rule_row.tenant_id = event_row.tenant_id
  join public.sys_notification_channel_config channel
    on channel.tenant_id = event_row.tenant_id
   and channel.channel_code = any(rule_row.channels)
   and channel.enabled is true
  join lateral (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = event_row.tenant_id
      and user_row.status = '1'
      and user_row.deleted_at is null
      and (
        (rule_row.recipient_strategy = 'owner_then_roles' and user_row.id = subject.owner_user_id)
        or exists (
          select 1 from public.sys_role role_row
          where role_row.tenant_id = user_row.tenant_id
            and role_row.enabled is true
            and role_row.role_code = any(coalesce(user_row.user_roles, array[]::text[]))
            and role_row.role_code = any(rule_row.recipient_role_codes)
        )
      )
  ) recipient on true
  where event_row.tenant_id = p_tenant_id
    and event_row.status in ('pending', 'failed')
    and event_row.scheduled_at <= now()
  on conflict (event_id, recipient_user_id, channel_code) do nothing;
  get diagnostics v_created_deliveries = row_count;

  for v_delivery in
    select delivery.*, subject.business_type, subject.business_id
    from public.sys_notification_delivery delivery
    left join public.sys_notification_event event_row on event_row.id = delivery.event_id
    left join public.sys_notification_subject subject on subject.id = event_row.subject_id
    where delivery.tenant_id = p_tenant_id
      and delivery.channel_code = 'in_app'
      and delivery.status in ('pending', 'failed')
      and (delivery.next_retry_at is null or delivery.next_retry_at <= now())
    order by delivery.create_time
    for update of delivery skip locked
    limit v_limit
  loop
    begin
      update public.sys_notification_delivery
      set status = 'processing', attempt_count = attempt_count + 1, update_by = 'system-reminder'
      where id = v_delivery.id;
      perform app_private.enqueue_user_notification(
        v_delivery.recipient_user_id, v_delivery.tenant_id, 'message',
        v_delivery.title, v_delivery.content, 'warning', 'notification_reminder_delivery',
        v_delivery.id, v_delivery.business_type, v_delivery.business_id, null,
        v_delivery.route_path, v_delivery.route_query
      );
      update public.sys_notification_delivery
      set status = 'delivered', delivered_at = now(), next_retry_at = null,
          error_message = null, update_by = 'system-reminder'
      where id = v_delivery.id;
      v_delivered_in_app := v_delivered_in_app + 1;
    exception when others then
      update public.sys_notification_delivery
      set status = 'failed', next_retry_at = now() + interval '15 minutes',
          error_message = left(sqlerrm, 1000), update_by = 'system-reminder'
      where id = v_delivery.id;
    end;
  end loop;

  update public.sys_notification_event event_row
  set status = case
        when exists (select 1 from public.sys_notification_delivery d where d.event_id = event_row.id and d.status in ('pending','processing','failed')) then 'queued'
        when exists (select 1 from public.sys_notification_delivery d where d.event_id = event_row.id and d.status = 'delivered') then 'delivered'
        else 'failed'
      end,
      update_by = 'system-reminder'
  where event_row.tenant_id = p_tenant_id
    and event_row.status in ('pending', 'queued', 'failed')
    and exists (select 1 from public.sys_notification_delivery d where d.event_id = event_row.id);

  return jsonb_build_object(
    'createdEventCount', v_created_events,
    'createdDeliveryCount', v_created_deliveries,
    'deliveredInAppCount', v_delivered_in_app
  );
end;
$$;

create or replace function public.run_notification_reminders_now(p_tenant_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
begin
  if not app_private.has_permission('System:NotificationReminder:Dispatch') then
    raise exception '缺少立即执行提醒任务权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.notification_target_tenant(
    coalesce(p_tenant_id, app_private.current_user_tenant_id())
  );
  return app_private.process_notification_reminders_for_tenant(v_tenant_id, 500);
end;
$$;

create or replace function public.test_notification_channel(p_tenant_id uuid, p_channel_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.notification_target_tenant(p_tenant_id);
  v_user_id uuid := app_private.current_app_user_id();
  v_delivery_id uuid;
begin
  if not app_private.has_permission('System:NotificationReminder:TestChannel') then
    raise exception '缺少测试通知渠道权限' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.sys_notification_channel_config
    where tenant_id = v_tenant_id and channel_code = p_channel_code
      and (channel_code = 'in_app' or vault_secret_id is not null)
  ) then raise exception '请先完成该渠道的凭据配置'; end if;

  if not exists (
    select 1 from public.sys_user where id = v_user_id and tenant_id = v_tenant_id
  ) then
    select user_row.id into v_user_id
    from public.sys_user user_row
    where user_row.tenant_id = v_tenant_id
      and user_row.status = '1'
      and user_row.deleted_at is null
      and exists (
        select 1 from public.sys_role role_row
        where role_row.tenant_id = user_row.tenant_id
          and role_row.enabled is true
          and role_row.role_code = any(coalesce(user_row.user_roles, array[]::text[]))
          and role_row.role_code in ('R_ADMIN', 'YQ_ADMIN', 'R_SUPER')
      )
    order by user_row.create_time
    limit 1;
  end if;
  if v_user_id is null then raise exception '目标租户没有可用的管理员账号'; end if;

  insert into public.sys_notification_delivery (
    tenant_id, recipient_user_id, channel_code, title, content, route_path,
    status, create_by, update_by
  ) values (
    v_tenant_id, v_user_id, p_channel_code, '通知渠道测试',
    '这是一条渠道连通性测试消息，发送时间：' || to_char(now() at time zone 'Asia/Shanghai', 'YYYY-MM-DD HH24:MI:SS'),
    '/system/notification-reminder', 'pending',
    coalesce(app_private.current_user_email(), 'system-reminder'),
    coalesce(app_private.current_user_email(), 'system-reminder')
  ) returning id into v_delivery_id;

  update public.sys_notification_channel_config
  set last_test_at = now(), last_test_status = 'pending', last_error = null,
      update_by = coalesce(app_private.current_user_email(), 'system-reminder')
  where tenant_id = v_tenant_id and channel_code = p_channel_code;

  if p_channel_code = 'in_app' then
    perform app_private.enqueue_user_notification(
      v_user_id, v_tenant_id, 'message', '通知渠道测试', '站内通知渠道已连通。',
      'success', 'notification_channel_test', v_delivery_id,
      'notification_channel', v_delivery_id, null, '/system/notification-reminder', '{}'::jsonb
    );
    update public.sys_notification_delivery
    set status = 'delivered', delivered_at = now(), attempt_count = 1, update_by = 'system-reminder'
    where id = v_delivery_id;
    update public.sys_notification_channel_config
    set last_test_status = 'delivered', update_by = 'system-reminder'
    where tenant_id = v_tenant_id and channel_code = p_channel_code;
  end if;
  return v_delivery_id;
end;
$$;

do $vehicle_backfill$
declare
  v_row record;
begin
  for v_row in select * from public.vehicle_insurance loop
    perform app_private.upsert_notification_subject(
      v_row.tenant_id, 'vms_commercial_insurance_expiry', 'vehicle_insurance', v_row.id, 'commercial',
      coalesce(v_row.plate_no, '车辆') || ' 商业险到期',
      case when v_row.commercial_expire_date is null then null else (v_row.commercial_expire_date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/vms/reminder-manage/insurance-expiry', jsonb_build_object('vehicleId', v_row.vehicle_id),
      jsonb_build_object('plateNo', v_row.plate_no), 'active'
    );
    perform app_private.upsert_notification_subject(
      v_row.tenant_id, 'vms_compulsory_insurance_expiry', 'vehicle_insurance', v_row.id, 'compulsory',
      coalesce(v_row.plate_no, '车辆') || ' 交强险到期',
      case when v_row.compulsory_expire_date is null then null else (v_row.compulsory_expire_date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/vms/reminder-manage/insurance-expiry', jsonb_build_object('vehicleId', v_row.vehicle_id),
      jsonb_build_object('plateNo', v_row.plate_no), 'active'
    );
  end loop;
  for v_row in select * from public.vehicle_inspection loop
    perform app_private.upsert_notification_subject(
      v_row.tenant_id, 'vms_vehicle_inspection_expiry', 'vehicle_inspection', v_row.id, 'expire_date',
      coalesce(v_row.plate_no, '车辆') || ' 年检到期',
      case when v_row.expire_date is null then null else (v_row.expire_date + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/vms/reminder-manage/inspection-expiry', jsonb_build_object('vehicleId', v_row.vehicle_id),
      jsonb_build_object('plateNo', v_row.plate_no), 'active'
    );
  end loop;
  for v_row in select * from public.vehicle_archive loop
    perform app_private.upsert_notification_subject(
      v_row.tenant_id, 'vms_vehicle_service_expiry', 'vehicle_archive', v_row.id, 'service_end',
      coalesce(v_row.plate_no, '车辆') || ' 服务期到期',
      case when v_row.service_end_time is null then null else (v_row.service_end_time + time '09:00') at time zone 'Asia/Shanghai' end,
      null, '/vms/reminder-manage/vehicle-service-life', jsonb_build_object('vehicleId', v_row.id),
      jsonb_build_object('plateNo', v_row.plate_no),
      case when coalesce(v_row.operation_status, '') in ('scrapped', 'retired', 'inactive') then 'resolved' else 'active' end
    );
  end loop;
end
$vehicle_backfill$;

grant execute on function public.run_notification_reminders_now(uuid) to authenticated;
grant execute on function public.test_notification_channel(uuid, text) to authenticated;

;
