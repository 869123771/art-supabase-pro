create unique index if not exists smis_equipment_inspection_id_tenant_uq
  on public.smis_equipment_inspection(id, tenant_id);

create table public.smis_equipment_reminder_config (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  equipment_id uuid not null,
  responsible_employee_id uuid not null,
  reminder_days integer[] not null default array[30, 7, 1],
  channels text[] not null default array['mobile_push'],
  message_template text not null default '设备【{equipmentName}】（{equipmentCode}）的{inspectionCategory}将于{dueDate}到期，剩余{daysRemaining}天，请及时处理。',
  enabled boolean not null default true,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_equipment_reminder_config_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_equipment_reminder_config_equipment_fkey
    foreign key (equipment_id, tenant_id) references public.smis_equipment(id, tenant_id) on delete cascade,
  constraint smis_equipment_reminder_config_employee_fkey
    foreign key (responsible_employee_id, tenant_id) references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_equipment_reminder_config_equipment_uq unique (equipment_id, tenant_id),
  constraint smis_equipment_reminder_days_check check (
    cardinality(reminder_days) between 1 and 10 and reminder_days <@ array[0,1,2,3,5,7,10,15,20,30,45,60,90,120,180,365]
  ),
  constraint smis_equipment_reminder_channels_check check (
    cardinality(channels) between 1 and 4
    and channels <@ array['wecom','dingtalk','mobile_push','sms']
  ),
  constraint smis_equipment_reminder_template_check check (
    btrim(message_template) <> '' and char_length(message_template) <= 1000
  )
);

comment on table public.smis_equipment_reminder_config is
  '重大危险源与特种设备到期提醒配置；外部渠道适配器只消费发送队列，不保存密钥';
comment on column public.smis_equipment_reminder_config.message_template is
  '支持 {equipmentName}、{equipmentCode}、{inspectionCategory}、{dueDate}、{daysRemaining}、{responsibleName}';

create index smis_equipment_reminder_employee_idx
  on public.smis_equipment_reminder_config(responsible_employee_id, tenant_id);
create index smis_equipment_reminder_enabled_idx
  on public.smis_equipment_reminder_config(tenant_id, enabled) where enabled;

create table public.smis_equipment_reminder_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  config_id uuid not null,
  inspection_id uuid not null,
  equipment_id uuid not null,
  responsible_employee_id uuid not null,
  channel text not null,
  recipient_name text not null,
  recipient_phone text,
  subject text not null,
  message_content text not null,
  due_date date not null,
  lead_days integer not null,
  status text not null default 'pending',
  attempt_count integer not null default 0,
  last_error text,
  scheduled_time timestamptz not null default now(),
  sent_time timestamptz,
  create_time timestamptz not null default now(),
  update_time timestamptz not null default now(),
  constraint smis_equipment_reminder_outbox_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_equipment_reminder_outbox_config_fkey foreign key (config_id)
    references public.smis_equipment_reminder_config(id) on delete cascade,
  constraint smis_equipment_reminder_outbox_inspection_fkey
    foreign key (inspection_id, tenant_id) references public.smis_equipment_inspection(id, tenant_id) on delete cascade,
  constraint smis_equipment_reminder_outbox_equipment_fkey
    foreign key (equipment_id, tenant_id) references public.smis_equipment(id, tenant_id) on delete cascade,
  constraint smis_equipment_reminder_outbox_employee_fkey
    foreign key (responsible_employee_id, tenant_id) references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_equipment_reminder_outbox_channel_check check (channel in ('wecom','dingtalk','mobile_push','sms')),
  constraint smis_equipment_reminder_outbox_status_check check (status in ('pending','processing','sent','failed','cancelled')),
  constraint smis_equipment_reminder_outbox_attempt_check check (attempt_count between 0 and 20),
  constraint smis_equipment_reminder_outbox_dedupe_uq unique (tenant_id, inspection_id, channel, due_date, lead_days)
);

comment on table public.smis_equipment_reminder_outbox is
  '设备到期提醒发送队列与审计快照；由企微、钉钉、移动端或短信适配器幂等消费';
create index smis_equipment_reminder_outbox_pending_idx
  on public.smis_equipment_reminder_outbox(status, scheduled_time) where status = 'pending';
create index smis_equipment_reminder_outbox_equipment_idx
  on public.smis_equipment_reminder_outbox(tenant_id, equipment_id, create_time desc);

create trigger smis_equipment_reminder_config_create_audit before insert on public.smis_equipment_reminder_config
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_equipment_reminder_config_update_audit before update on public.smis_equipment_reminder_config
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_equipment_reminder_outbox_update_audit before update on public.smis_equipment_reminder_outbox
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_equipment_reminder_config enable row level security;
alter table public.smis_equipment_reminder_outbox enable row level security;
create policy smis_equipment_reminder_config_select on public.smis_equipment_reminder_config
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisEquipmentReminder:View')))
  or (select app_private.is_platform_super())
);
create policy smis_equipment_reminder_config_write on public.smis_equipment_reminder_config
for all to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisEquipmentReminder:Manage'))
) with check (
  tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisEquipmentReminder:Manage'))
);
create policy smis_equipment_reminder_outbox_select on public.smis_equipment_reminder_outbox
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id()) and (select app_private.has_permission('SmisEquipmentReminder:View')))
  or (select app_private.is_platform_super())
);

revoke all on table public.smis_equipment_reminder_config from public, anon, authenticated;
revoke all on table public.smis_equipment_reminder_outbox from public, anon, authenticated;
grant select, insert, update, delete on public.smis_equipment_reminder_config to service_role;
grant select, insert, update, delete on public.smis_equipment_reminder_outbox to service_role;

create or replace function public.smis_get_equipment_reminder_secure(p_equipment_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid; v_result jsonb;
begin
  if not app_private.has_permission('SmisEquipmentReminder:View') then raise exception '当前账号无权查看设备提醒配置'; end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if not exists (select 1 from public.smis_equipment where id = p_equipment_id and tenant_id = v_tenant_id) then raise exception '设备不存在或无权访问'; end if;
  select jsonb_build_object(
    'config', case when config.id is null then null else jsonb_build_object(
      'id', config.id, 'equipmentId', config.equipment_id,
      'responsibleEmployeeId', config.responsible_employee_id,
      'reminderDays', config.reminder_days, 'channels', config.channels,
      'messageTemplate', config.message_template, 'enabled', config.enabled,
      'responsible', jsonb_build_object('id', employee.id, 'employeeNo', employee.employee_no,
        'employeeName', employee.employee_name, 'phone', employee.phone,
        'organizationId', employee.organization_id, 'organizationName', organization.organization_name)
    ) end,
    'recentDeliveries', coalesce((select jsonb_agg(jsonb_build_object(
      'id', outbox.id, 'channel', outbox.channel, 'status', outbox.status,
      'dueDate', outbox.due_date, 'leadDays', outbox.lead_days,
      'messageContent', outbox.message_content, 'scheduledTime', outbox.scheduled_time,
      'sentTime', outbox.sent_time, 'lastError', outbox.last_error
    ) order by outbox.create_time desc) from (
      select * from public.smis_equipment_reminder_outbox
      where tenant_id = v_tenant_id and equipment_id = p_equipment_id
      order by create_time desc limit 20
    ) outbox), '[]'::jsonb)
  ) into v_result
  from public.smis_equipment equipment
  left join public.smis_equipment_reminder_config config on config.equipment_id = equipment.id and config.tenant_id = equipment.tenant_id
  left join public.hr_employee employee on employee.id = config.responsible_employee_id and employee.tenant_id = config.tenant_id
  left join public.sys_organization organization on organization.id = employee.organization_id and organization.tenant_id = employee.tenant_id
  where equipment.id = p_equipment_id and equipment.tenant_id = v_tenant_id;
  return coalesce(v_result, jsonb_build_object('config', null, 'recentDeliveries', '[]'::jsonb));
end;
$$;

create or replace function public.smis_save_equipment_reminder_secure(p_equipment_id uuid, p_payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid;
  v_employee_id uuid := nullif(p_payload ->> 'responsible_employee_id', '')::uuid;
  v_days integer[];
  v_channels text[];
  v_template text := btrim(coalesce(p_payload ->> 'message_template', ''));
  v_result uuid;
begin
  if not app_private.has_permission('SmisEquipmentReminder:Manage') then raise exception '当前账号无权维护设备提醒配置'; end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if not exists (select 1 from public.smis_equipment where id = p_equipment_id and tenant_id = v_tenant_id and (is_major_hazard_source or is_special_equipment)) then raise exception '仅重大危险源或特种设备可配置到期提醒'; end if;
  if v_employee_id is null or not exists (select 1 from public.hr_employee where id = v_employee_id and tenant_id = v_tenant_id) then raise exception '请选择当前租户员工花名册中的责任人'; end if;
  select array_agg(distinct value::integer order by value::integer) into v_days from jsonb_array_elements_text(coalesce(p_payload -> 'reminder_days', '[]'::jsonb)) value;
  select array_agg(distinct value order by value) into v_channels from jsonb_array_elements_text(coalesce(p_payload -> 'channels', '[]'::jsonb)) value;
  if coalesce(cardinality(v_days), 0) = 0 then raise exception '请至少选择一个提前提醒天数'; end if;
  if coalesce(cardinality(v_channels), 0) = 0 then raise exception '请至少选择一个推送渠道'; end if;
  if v_template = '' then raise exception '请输入提醒消息模板'; end if;
  insert into public.smis_equipment_reminder_config(
    tenant_id, equipment_id, responsible_employee_id, reminder_days, channels, message_template, enabled
  ) values (
    v_tenant_id, p_equipment_id, v_employee_id, v_days, v_channels, v_template,
    coalesce((p_payload ->> 'enabled')::boolean, true)
  ) on conflict (equipment_id, tenant_id) do update set
    responsible_employee_id = excluded.responsible_employee_id,
    reminder_days = excluded.reminder_days, channels = excluded.channels,
    message_template = excluded.message_template, enabled = excluded.enabled
  returning id into v_result;
  return v_result;
end;
$$;

create or replace function app_private.enqueue_due_equipment_reminders(p_run_date date default current_date)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  insert into public.smis_equipment_reminder_outbox(
    tenant_id, config_id, inspection_id, equipment_id, responsible_employee_id,
    channel, recipient_name, recipient_phone, subject, message_content,
    due_date, lead_days, status, scheduled_time
  )
  select config.tenant_id, config.id, inspection.id, equipment.id, employee.id,
    channel.value, employee.employee_name, employee.phone,
    '设备检验到期提醒｜' || equipment.equipment_name,
    replace(replace(replace(replace(replace(replace(config.message_template,
      '{equipmentName}', equipment.equipment_name), '{equipmentCode}', equipment.equipment_code),
      '{inspectionCategory}', category.category_name), '{dueDate}', inspection.next_due_date::text),
      '{daysRemaining}', lead.value::text), '{responsibleName}', employee.employee_name),
    inspection.next_due_date, lead.value, 'pending', now()
  from public.smis_equipment_reminder_config config
  join public.smis_equipment equipment on equipment.id = config.equipment_id and equipment.tenant_id = config.tenant_id
  join public.hr_employee employee on employee.id = config.responsible_employee_id and employee.tenant_id = config.tenant_id
  join public.smis_equipment_inspection inspection on inspection.equipment_id = equipment.id and inspection.tenant_id = equipment.tenant_id
  join public.smis_inspection_category category on category.id = inspection.inspection_category_id and category.tenant_id = inspection.tenant_id
  cross join unnest(config.reminder_days) lead(value)
  cross join unnest(config.channels) channel(value)
  where config.enabled and equipment.status = 'enabled'
    and inspection.status in ('planned','completed')
    and inspection.next_due_date = p_run_date + lead.value
  on conflict (tenant_id, inspection_id, channel, due_date, lead_days) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.smis_get_equipment_reminder_secure(uuid) from public, anon;
revoke all on function public.smis_save_equipment_reminder_secure(uuid, jsonb) from public, anon;
revoke all on function app_private.enqueue_due_equipment_reminders(date) from public, anon, authenticated;
grant execute on function public.smis_get_equipment_reminder_secure(uuid) to authenticated, service_role;
grant execute on function public.smis_save_equipment_reminder_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function app_private.enqueue_due_equipment_reminders(date) to service_role;

with platform_tenant as (select id from public.sys_tenant where tenant_code = 'platform' limit 1)
insert into public.sys_dict_type(id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort)
select gen_random_uuid(), '设备提醒渠道', 'smisEquipmentReminderChannel', '1',
  '624944977@qq.com', '624944977@qq.com', '企微、钉钉、移动端和短信渠道', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'smisEquipmentLedger' limit 1), 'dictionary', 21
from platform_tenant on conflict (code) do update set name = excluded.name, status = excluded.status,
  remark = excluded.remark, parent_id = excluded.parent_id, sort = excluded.sort, update_time = now();

with platform_tenant as (select id from public.sys_tenant where tenant_code = 'platform' limit 1),
items(value,label,sort,tag_type,remark) as (values
  ('wecom','企业微信',1,'primary','由企业微信渠道适配器消费发送队列'),
  ('dingtalk','钉钉',2,'warning','由钉钉渠道适配器消费发送队列'),
  ('mobile_push','移动端推送',3,'success','由移动端消息服务消费发送队列'),
  ('sms','短信',4,'danger','使用员工花名册手机号，由短信服务消费发送队列')
)
insert into public.sys_dictionary(id,type_id,code,status,create_by,update_by,remark,value,label,tenant_id,tag_type,sort)
select gen_random_uuid(), type.id, 'smisEquipmentReminderChannel_' || items.value, '1',
  '624944977@qq.com','624944977@qq.com',items.remark,items.value,items.label,platform_tenant.id,items.tag_type,items.sort
from items join public.sys_dict_type type on type.code='smisEquipmentReminderChannel'
cross join platform_tenant where not exists (select 1 from public.sys_dictionary existing where existing.type_id=type.id and existing.value=items.value);

insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,app_code,create_by,update_by)
select seed.id,'a1530000-0000-4000-8000-000000000019'::uuid,seed.name,'','',
  jsonb_build_object('title',seed.title,'icon','','is_hide',true,'is_enable',true,'roles',jsonb_build_array()),
  seed.sort,'button','smis','624944977@qq.com','624944977@qq.com'
from (values
  ('a1530000-0000-4000-8190-000000000001'::uuid,'SmisEquipmentReminder:View','查看设备提醒',1),
  ('a1530000-0000-4000-8190-000000000002'::uuid,'SmisEquipmentReminder:Manage','维护设备提醒',2)
) seed(id,name,title,sort)
on conflict (id) do update set parent_id=excluded.parent_id,name=excluded.name,meta=excluded.meta,sort=excluded.sort,type=excluded.type,app_code=excluded.app_code,update_time=now();

insert into public.sys_role_menu(role_id,menu_id,tenant_id,permission,create_by,update_by)
select grant_row.role_id,button.id,role.tenant_id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com'
from public.sys_role_menu grant_row join public.sys_role role on role.id=grant_row.role_id
cross join (values
  ('a1530000-0000-4000-8190-000000000001'::uuid),
  ('a1530000-0000-4000-8190-000000000002'::uuid)
) button(id)
where grant_row.menu_id='a1530000-0000-4000-8000-000000000019'::uuid
on conflict (role_id,menu_id) do nothing;

;
