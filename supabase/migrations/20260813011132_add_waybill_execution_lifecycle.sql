-- Auditable end-to-end waybill execution lifecycle shared by Web and driver clients.

create table public.tms_waybill_execution_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  waybill_id uuid not null references public.tms_waybill(id) on delete cascade,
  departure_time timestamptz,
  departure_odometer_km numeric(12, 1),
  departure_photo_urls jsonb not null default '[]'::jsonb,
  departure_remark text,
  departure_operator_name text,
  departure_recorded_at timestamptz,
  signed_at timestamptz,
  signer_name text,
  receipt_urls jsonb not null default '[]'::jsonb,
  signature_urls jsonb not null default '[]'::jsonb,
  signature_remark text,
  signature_operator_name text,
  signature_recorded_at timestamptz,
  return_time timestamptz,
  return_odometer_km numeric(12, 1),
  return_photo_urls jsonb not null default '[]'::jsonb,
  completion_remark text,
  completion_operator_name text,
  completion_recorded_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_waybill_execution_record_waybill_uidx unique (waybill_id),
  constraint tms_waybill_execution_departure_odometer_check
    check (departure_odometer_km is null or departure_odometer_km >= 0),
  constraint tms_waybill_execution_return_odometer_check
    check (return_odometer_km is null or return_odometer_km >= 0),
  constraint tms_waybill_execution_odometer_sequence_check
    check (
      departure_odometer_km is null
      or return_odometer_km is null
      or return_odometer_km >= departure_odometer_km
    ),
  constraint tms_waybill_execution_photo_arrays_check
    check (
      jsonb_typeof(departure_photo_urls) = 'array'
      and jsonb_typeof(receipt_urls) = 'array'
      and jsonb_typeof(signature_urls) = 'array'
      and jsonb_typeof(return_photo_urls) = 'array'
    ),
  constraint tms_waybill_execution_departure_completion_check
    check (
      departure_time is null
      or (
        departure_odometer_km is not null
        and jsonb_array_length(departure_photo_urls) > 0
        and departure_recorded_at is not null
      )
    ),
  constraint tms_waybill_execution_signature_completion_check
    check (
      signed_at is null
      or (
        nullif(btrim(signer_name), '') is not null
        and jsonb_array_length(receipt_urls) > 0
        and jsonb_array_length(signature_urls) > 0
        and signature_recorded_at is not null
      )
    ),
  constraint tms_waybill_execution_return_completion_check
    check (
      return_time is null
      or (
        return_odometer_km is not null
        and jsonb_array_length(return_photo_urls) > 0
        and completion_recorded_at is not null
      )
    )
);

comment on table public.tms_waybill_execution_record is
  'One authoritative departure, signature, and return record per waybill, shared by Web and driver clients.';
comment on column public.tms_waybill_execution_record.departure_odometer_km is
  'Vehicle odometer at departure, in kilometres.';
comment on column public.tms_waybill_execution_record.return_odometer_km is
  'Vehicle odometer when the waybill is closed, in kilometres.';

create index tms_waybill_execution_record_tenant_time_idx
  on public.tms_waybill_execution_record (tenant_id, update_time desc);

create trigger tms_waybill_execution_record_create_audit
before insert on public.tms_waybill_execution_record
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger tms_waybill_execution_record_update_audit
before update on public.tms_waybill_execution_record
for each row execute function public.trg_set_update_time_and_by();

alter table public.vehicle_mileage_record
  add column waybill_id uuid references public.tms_waybill(id) on delete set null;

create unique index vehicle_mileage_record_waybill_uidx
  on public.vehicle_mileage_record (waybill_id)
  where waybill_id is not null;

create or replace function app_private.tms_valid_url_array(p_value jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_typeof(p_value) = 'array'
    and jsonb_array_length(p_value) between 1 and 9
    and not exists (
      select 1
      from jsonb_array_elements(p_value) item
      where jsonb_typeof(item) <> 'string'
        or nullif(btrim(item #>> '{}'), '') is null
    );
$$;

revoke all on function app_private.tms_valid_url_array(jsonb) from public;

create or replace function app_private.tms_current_operator_name()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select coalesce(nullif(u.nick_name, ''), nullif(u.user_name, ''), u.user_email)
      from public.sys_user u
      where u.auth_user_id = (select auth.uid())
        and u.status = '1'
      limit 1
    ),
    (
      select d.driver_name
      from public.tms_driver d
      where d.id = (select app_private.current_user_driver_id())
      limit 1
    ),
    '系统用户'
  );
$$;

revoke all on function app_private.tms_current_operator_name() from public, anon, authenticated;

create or replace function app_private.can_manage_waybill_execution_action(p_action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select app_private.is_platform_super())
    or (select app_private.has_permission(
      case p_action
        when 'accept' then 'TmsWaybill:Accept'
        when 'departure' then 'TmsWaybill:Depart'
        when 'arrival' then 'TmsWaybill:Arrive'
        when 'signature' then 'TmsWaybill:Sign'
        when 'completion' then 'TmsWaybill:Complete'
        when 'cancel' then 'TmsWaybill:Cancel'
        else ''
      end
    ));
$$;

revoke all on function app_private.can_manage_waybill_execution_action(text)
  from public, anon, authenticated;

create or replace function app_private.can_manage_waybill_cargo_operation(
  p_operation_type text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select app_private.is_platform_super())
    or case p_operation_type
      when 'loading' then (select app_private.has_permission('TmsWaybill:Loading'))
      when 'unloading' then
        (select app_private.has_permission('TmsWaybill:Arrive'))
        or (select app_private.has_permission('TmsWaybill:Unloading'))
      else false
    end;
$$;

revoke all on function app_private.can_manage_waybill_cargo_operation(text)
  from public, anon, authenticated;

alter table public.tms_waybill_execution_record enable row level security;

create policy tms_waybill_execution_record_select
on public.tms_waybill_execution_record
for select to authenticated
using ((select app_private.can_access_waybill_cargo_operation(waybill_id)));

grant select on public.tms_waybill_execution_record to authenticated;
grant all on public.tms_waybill_execution_record to service_role;

create or replace function public.tms_get_waybill_execution_context(p_waybill_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  execution_record public.tms_waybill_execution_record%rowtype;
  loading_record public.tms_waybill_cargo_operation%rowtype;
  unloading_record public.tms_waybill_cargo_operation%rowtype;
  is_driver boolean;
  tenant_matches boolean;
begin
  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id;

  if not found or not app_private.can_access_waybill_cargo_operation(p_waybill_id) then
    raise exception '无权查看该运单执行信息' using errcode = '42501';
  end if;

  select * into execution_record
  from public.tms_waybill_execution_record
  where waybill_id = p_waybill_id;

  select * into loading_record
  from public.tms_waybill_cargo_operation
  where waybill_id = p_waybill_id and operation_type = 'loading';

  select * into unloading_record
  from public.tms_waybill_cargo_operation
  where waybill_id = p_waybill_id and operation_type = 'unloading';

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  tenant_matches := app_private.is_platform_super()
    or waybill_record.tenant_id = app_private.current_user_tenant_id();

  return jsonb_build_object(
    'waybillId', waybill_record.id,
    'waybillStatus', waybill_record.status,
    'loadingStatus', loading_record.operation_status,
    'unloadingStatus', unloading_record.operation_status,
    'arrivalTime', unloading_record.checkin_time,
    'arrivalAddress', unloading_record.location_text,
    'arrivalLongitude', unloading_record.longitude,
    'arrivalLatitude', unloading_record.latitude,
    'canAccept', waybill_record.status = 'pending' and (
      is_driver or (tenant_matches and app_private.can_manage_waybill_execution_action('accept'))
    ),
    'canDepart', waybill_record.status = 'loading'
      and loading_record.operation_status = 'completed'
      and (is_driver or (tenant_matches and app_private.can_manage_waybill_execution_action('departure'))),
    'canArrive', waybill_record.status = 'transporting' and (
      is_driver or (tenant_matches and app_private.can_manage_waybill_execution_action('arrival'))
    ),
    'canUnload', waybill_record.status = 'unloading' and (
      is_driver or (tenant_matches and (
        app_private.is_platform_super()
        or app_private.has_permission('TmsWaybill:Unloading')
      ))
    ),
    'canSign', (
      waybill_record.status = 'unloading'
      or (waybill_record.status = 'signed' and execution_record.signed_at is null)
    )
      and unloading_record.operation_status = 'completed'
      and (is_driver or (tenant_matches and app_private.can_manage_waybill_execution_action('signature'))),
    'canComplete', waybill_record.status = 'signed' and (
      is_driver or (tenant_matches and app_private.can_manage_waybill_execution_action('completion'))
    ),
    'canCancel', waybill_record.status not in ('signed', 'completed', 'cancelled') and (
      (is_driver and waybill_record.status in ('pending', 'accepted'))
      or (tenant_matches and app_private.can_manage_waybill_execution_action('cancel'))
    ),
    'record', case when execution_record.id is null then null else jsonb_build_object(
      'id', execution_record.id,
      'tenantId', execution_record.tenant_id,
      'waybillId', execution_record.waybill_id,
      'departureTime', execution_record.departure_time,
      'departureOdometerKm', execution_record.departure_odometer_km,
      'departurePhotoUrls', execution_record.departure_photo_urls,
      'departureRemark', execution_record.departure_remark,
      'departureOperatorName', execution_record.departure_operator_name,
      'departureRecordedAt', execution_record.departure_recorded_at,
      'signedAt', execution_record.signed_at,
      'signerName', execution_record.signer_name,
      'receiptUrls', execution_record.receipt_urls,
      'signatureUrls', execution_record.signature_urls,
      'signatureRemark', execution_record.signature_remark,
      'signatureOperatorName', execution_record.signature_operator_name,
      'signatureRecordedAt', execution_record.signature_recorded_at,
      'returnTime', execution_record.return_time,
      'returnOdometerKm', execution_record.return_odometer_km,
      'returnPhotoUrls', execution_record.return_photo_urls,
      'completionRemark', execution_record.completion_remark,
      'completionOperatorName', execution_record.completion_operator_name,
      'completionRecordedAt', execution_record.completion_recorded_at,
      'createTime', execution_record.create_time,
      'updateTime', execution_record.update_time
    ) end
  );
end;
$$;

insert into public.sys_menu (
  parent_id, name, path, component, meta, sort, type, create_by, update_by
)
select
  parent.id,
  action.name,
  '',
  '',
  jsonb_build_object(
    'title', action.title,
    'authMark', action.auth_mark,
    'is_enable', true,
    'is_auth_button', true
  ),
  action.sort,
  'button',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_menu parent
cross join (
  values
    ('TmsWaybill:Accept', '确认接单', 'accept', 3),
    ('TmsWaybill:Depart', '确认发车', 'depart', 4),
    ('TmsWaybill:Arrive', '确认到达', 'arrive', 5),
    ('TmsWaybill:Sign', '签收', 'sign', 6),
    ('TmsWaybill:Complete', '确认完成', 'complete', 7),
    ('TmsWaybill:Cancel', '取消运单', 'cancel', 8)
) as action(name, title, auth_mark, sort)
where parent.name = 'TmsLoadedWaybillList'
  and not exists (
    select 1 from public.sys_menu existing where existing.name = action.name
  );

insert into public.sys_role_menu (
  role_id, menu_id, permission, create_by, update_by, tenant_id
)
select
  role.id,
  menu.id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com',
  role.tenant_id
from public.sys_role role
join public.sys_menu menu on menu.name in (
  'TmsWaybill:Accept',
  'TmsWaybill:Depart',
  'TmsWaybill:Arrive',
  'TmsWaybill:Sign',
  'TmsWaybill:Complete',
  'TmsWaybill:Cancel'
)
where role.builtin_type = 'platform_super'
on conflict (role_id, menu_id) do nothing;

revoke all on function public.tms_get_waybill_execution_context(uuid) from public, anon;
grant execute on function public.tms_get_waybill_execution_context(uuid) to authenticated;

create or replace function public.tms_record_waybill_departure(
  p_waybill_id uuid,
  p_departure_time timestamptz,
  p_odometer_km numeric,
  p_photo_urls jsonb,
  p_remark text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  loading_record public.tms_waybill_cargo_operation%rowtype;
  operator_value text;
  occurred_at timestamptz;
  is_driver boolean;
  is_manager boolean;
begin
  if p_odometer_km is null or p_odometer_km < 0 then
    raise exception '出车里程必须大于或等于 0 公里' using errcode = '23514';
  end if;
  if not app_private.tms_valid_url_array(p_photo_urls) then
    raise exception '请上传 1 至 9 张发车凭证照片' using errcode = '23514';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;
  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_execution_action('departure')
    and (app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id());
  if not is_driver and not is_manager then
    raise exception '无权确认该运单发车' using errcode = '42501';
  end if;
  if waybill_record.status = 'transporting' then
    return public.tms_get_waybill_execution_context(p_waybill_id);
  end if;
  if waybill_record.status <> 'loading' then
    raise exception '仅装货完成的运单可以确认发车' using errcode = '23514';
  end if;

  select * into loading_record
  from public.tms_waybill_cargo_operation
  where waybill_id = p_waybill_id and operation_type = 'loading';
  if loading_record.operation_status is distinct from 'completed' then
    raise exception '请先提交完整装货信息' using errcode = '23514';
  end if;

  occurred_at := coalesce(p_departure_time, now());
  if occurred_at < coalesce(loading_record.completed_at, waybill_record.loaded_at, waybill_record.accepted_at)
     or occurred_at > now() + interval '10 minutes' then
    raise exception '发车时间必须晚于装货完成时间且不能超过当前时间 10 分钟' using errcode = '23514';
  end if;
  operator_value := app_private.tms_current_operator_name();

  insert into public.tms_waybill_execution_record (
    tenant_id, waybill_id, departure_time, departure_odometer_km,
    departure_photo_urls, departure_remark, departure_operator_name,
    departure_recorded_at
  ) values (
    waybill_record.tenant_id, waybill_record.id, occurred_at, p_odometer_km,
    p_photo_urls, nullif(btrim(p_remark), ''), operator_value, now()
  )
  on conflict (waybill_id) do update set
    departure_time = excluded.departure_time,
    departure_odometer_km = excluded.departure_odometer_km,
    departure_photo_urls = excluded.departure_photo_urls,
    departure_remark = excluded.departure_remark,
    departure_operator_name = excluded.departure_operator_name,
    departure_recorded_at = excluded.departure_recorded_at;

  update public.tms_waybill
  set status = 'transporting', departed_at = occurred_at
  where id = waybill_record.id;

  insert into public.tms_waybill_event (
    tenant_id, waybill_id, event_type, event_time, operator_name,
    location_text, payload, remark
  ) values (
    waybill_record.tenant_id, waybill_record.id, 'departed', occurred_at,
    operator_value,
    concat_ws(' - ', waybill_record.origin_city, waybill_record.destination_city),
    jsonb_build_object(
      'action', 'confirm_departure',
      'source', case when is_driver then 'driver' else 'web' end,
      'odometerKm', p_odometer_km,
      'photoCount', jsonb_array_length(p_photo_urls)
    ),
    nullif(btrim(p_remark), '')
  );

  return public.tms_get_waybill_execution_context(p_waybill_id);
end;
$$;

revoke all on function public.tms_record_waybill_departure(
  uuid, timestamptz, numeric, jsonb, text
) from public, anon;
grant execute on function public.tms_record_waybill_departure(
  uuid, timestamptz, numeric, jsonb, text
) to authenticated;

create or replace function public.tms_sign_waybill(
  p_waybill_id uuid,
  p_signed_at timestamptz,
  p_signer_name text,
  p_receipt_urls jsonb,
  p_signature_urls jsonb,
  p_remark text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  unloading_record public.tms_waybill_cargo_operation%rowtype;
  operator_value text;
  occurred_at timestamptz;
  is_driver boolean;
  is_manager boolean;
  has_signature boolean;
  linked_order_id uuid;
begin
  if nullif(btrim(p_signer_name), '') is null then
    raise exception '请填写签收人' using errcode = '23514';
  end if;
  if not app_private.tms_valid_url_array(p_receipt_urls) then
    raise exception '请上传 1 至 9 张签收回单' using errcode = '23514';
  end if;
  if not app_private.tms_valid_url_array(p_signature_urls) then
    raise exception '请上传 1 至 9 张签字确认照片' using errcode = '23514';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;
  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_execution_action('signature')
    and (app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id());
  if not is_driver and not is_manager then
    raise exception '无权签收该运单' using errcode = '42501';
  end if;
  select coalesce(bool_or(execution.signed_at is not null), false)
    into has_signature
  from public.tms_waybill_execution_record execution
  where execution.waybill_id = p_waybill_id;
  if waybill_record.status = 'signed' and has_signature then
    return public.tms_get_waybill_execution_context(p_waybill_id);
  end if;
  if waybill_record.status not in ('unloading', 'signed') then
    raise exception '仅卸货完成的运单可以签收' using errcode = '23514';
  end if;

  select * into unloading_record
  from public.tms_waybill_cargo_operation
  where waybill_id = p_waybill_id and operation_type = 'unloading';
  if unloading_record.operation_status is distinct from 'completed' then
    raise exception '请先提交完整卸货信息' using errcode = '23514';
  end if;

  occurred_at := coalesce(p_signed_at, now());
  if occurred_at < coalesce(unloading_record.completed_at, waybill_record.unloaded_at)
     or occurred_at > now() + interval '10 minutes' then
    raise exception '签收时间必须晚于卸货完成时间且不能超过当前时间 10 分钟' using errcode = '23514';
  end if;
  operator_value := app_private.tms_current_operator_name();

  insert into public.tms_waybill_execution_record (
    tenant_id, waybill_id, signed_at, signer_name, receipt_urls,
    signature_urls, signature_remark, signature_operator_name,
    signature_recorded_at
  ) values (
    waybill_record.tenant_id, waybill_record.id, occurred_at,
    btrim(p_signer_name), p_receipt_urls, p_signature_urls,
    nullif(btrim(p_remark), ''), operator_value, now()
  )
  on conflict (waybill_id) do update set
    signed_at = excluded.signed_at,
    signer_name = excluded.signer_name,
    receipt_urls = excluded.receipt_urls,
    signature_urls = excluded.signature_urls,
    signature_remark = excluded.signature_remark,
    signature_operator_name = excluded.signature_operator_name,
    signature_recorded_at = excluded.signature_recorded_at;

  update public.tms_waybill
  set status = 'signed',
      receipt_attachments = p_receipt_urls || p_signature_urls
  where id = waybill_record.id;

  select orders.id into linked_order_id
  from public.tms_order orders
  where orders.id = waybill_record.order_id
     or (
       waybill_record.order_id is null
       and orders.tenant_id = waybill_record.tenant_id
       and orders.order_no = waybill_record.waybill_no
     )
  limit 1;

  update public.tms_order
  set receipt_image_urls = p_receipt_urls || p_signature_urls,
      signed_at = occurred_at
  where id = linked_order_id;

  insert into public.tms_waybill_event (
    tenant_id, waybill_id, event_type, event_time, operator_name,
    location_text, payload, remark
  ) values (
    waybill_record.tenant_id, waybill_record.id, 'signed', occurred_at,
    operator_value, unloading_record.location_text,
    jsonb_build_object(
      'action', 'sign',
      'source', case when is_driver then 'driver' else 'web' end,
      'signerName', btrim(p_signer_name),
      'receiptCount', jsonb_array_length(p_receipt_urls),
      'signatureCount', jsonb_array_length(p_signature_urls)
    ),
    nullif(btrim(p_remark), '')
  );

  return public.tms_get_waybill_execution_context(p_waybill_id);
end;
$$;

revoke all on function public.tms_sign_waybill(
  uuid, timestamptz, text, jsonb, jsonb, text
) from public, anon;
grant execute on function public.tms_sign_waybill(
  uuid, timestamptz, text, jsonb, jsonb, text
) to authenticated;

create or replace function public.tms_complete_waybill_execution(
  p_waybill_id uuid,
  p_return_time timestamptz,
  p_return_odometer_km numeric,
  p_photo_urls jsonb,
  p_remark text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  execution_record public.tms_waybill_execution_record%rowtype;
  vehicle_record public.vehicle_archive%rowtype;
  operator_value text;
  occurred_at timestamptz;
  is_driver boolean;
  is_manager boolean;
begin
  if p_return_odometer_km is null or p_return_odometer_km < 0 then
    raise exception '收车里程必须大于或等于 0 公里' using errcode = '23514';
  end if;
  if not app_private.tms_valid_url_array(p_photo_urls) then
    raise exception '请上传 1 至 9 张收车凭证照片' using errcode = '23514';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;
  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_execution_action('completion')
    and (app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id());
  if not is_driver and not is_manager then
    raise exception '无权完成该运单' using errcode = '42501';
  end if;
  if waybill_record.status = 'completed' then
    return public.tms_get_waybill_execution_context(p_waybill_id);
  end if;
  if waybill_record.status <> 'signed' then
    raise exception '仅已签收运单可以确认完成' using errcode = '23514';
  end if;

  select * into execution_record
  from public.tms_waybill_execution_record
  where waybill_id = p_waybill_id
  for update;
  if execution_record.signed_at is null then
    raise exception '签收记录不完整，无法完成运单' using errcode = '23514';
  end if;
  if execution_record.departure_odometer_km is null
     or p_return_odometer_km < execution_record.departure_odometer_km then
    raise exception '收车里程不能小于出车里程 % 公里', execution_record.departure_odometer_km
      using errcode = '23514';
  end if;

  occurred_at := coalesce(p_return_time, now());
  if occurred_at < execution_record.signed_at
     or occurred_at > now() + interval '10 minutes' then
    raise exception '收车时间必须晚于签收时间且不能超过当前时间 10 分钟' using errcode = '23514';
  end if;
  operator_value := app_private.tms_current_operator_name();

  update public.tms_waybill_execution_record
  set return_time = occurred_at,
      return_odometer_km = p_return_odometer_km,
      return_photo_urls = p_photo_urls,
      completion_remark = nullif(btrim(p_remark), ''),
      completion_operator_name = operator_value,
      completion_recorded_at = now()
  where id = execution_record.id;

  update public.tms_waybill
  set status = 'completed', completed_at = occurred_at
  where id = waybill_record.id;

  select * into vehicle_record
  from public.vehicle_archive
  where id = waybill_record.vehicle_id;

  if vehicle_record.id is not null then
    insert into public.vehicle_mileage_record (
      tenant_id, vehicle_id, waybill_id, plate_no, company_name,
      start_time, end_time, start_mileage, end_mileage, running_mileage
    ) values (
      waybill_record.tenant_id, vehicle_record.id, waybill_record.id,
      vehicle_record.plate_no, vehicle_record.company_name,
      execution_record.departure_time, occurred_at,
      execution_record.departure_odometer_km, p_return_odometer_km,
      p_return_odometer_km - execution_record.departure_odometer_km
    )
    on conflict (waybill_id) where waybill_id is not null do update set
      end_time = excluded.end_time,
      end_mileage = excluded.end_mileage,
      running_mileage = excluded.running_mileage;
  end if;

  insert into public.tms_waybill_event (
    tenant_id, waybill_id, event_type, event_time, operator_name,
    location_text, payload, remark
  ) values (
    waybill_record.tenant_id, waybill_record.id, 'completed', occurred_at,
    operator_value,
    concat_ws(' - ', waybill_record.origin_city, waybill_record.destination_city),
    jsonb_build_object(
      'action', 'complete',
      'source', case when is_driver then 'driver' else 'web' end,
      'returnOdometerKm', p_return_odometer_km,
      'runningMileageKm', p_return_odometer_km - execution_record.departure_odometer_km,
      'photoCount', jsonb_array_length(p_photo_urls)
    ),
    nullif(btrim(p_remark), '')
  );

  return public.tms_get_waybill_execution_context(p_waybill_id);
end;
$$;

revoke all on function public.tms_complete_waybill_execution(
  uuid, timestamptz, numeric, jsonb, text
) from public, anon;
grant execute on function public.tms_complete_waybill_execution(
  uuid, timestamptz, numeric, jsonb, text
) to authenticated;

create or replace function public.tms_cancel_assigned_waybill(
  p_waybill_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  operator_value text;
  is_driver boolean;
  is_manager boolean;
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 4 then
    raise exception '取消原因至少填写 4 个字' using errcode = '23514';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;
  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_execution_action('cancel')
    and (app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id());
  if not is_driver and not is_manager then
    raise exception '无权取消该运单' using errcode = '42501';
  end if;
  if is_driver and not is_manager and waybill_record.status not in ('pending', 'accepted') then
    raise exception '司机仅可取消待接单或待装货运单' using errcode = '23514';
  end if;
  if waybill_record.status in ('signed', 'completed') then
    raise exception '已签收或已完成运单不能取消' using errcode = '23514';
  end if;
  if waybill_record.status = 'cancelled' then
    return public.tms_get_waybill_execution_context(p_waybill_id);
  end if;

  operator_value := app_private.tms_current_operator_name();
  update public.tms_waybill
  set status = 'cancelled', cancelled_at = coalesce(cancelled_at, now())
  where id = waybill_record.id;

  insert into public.tms_waybill_event (
    tenant_id, waybill_id, event_type, event_time, operator_name,
    location_text, payload, remark
  ) values (
    waybill_record.tenant_id, waybill_record.id, 'cancelled', now(),
    operator_value,
    concat_ws(' - ', waybill_record.origin_city, waybill_record.destination_city),
    jsonb_build_object(
      'action', 'cancel',
      'source', case when is_driver and not is_manager then 'driver' else 'web' end
    ),
    btrim(p_reason)
  );

  return public.tms_get_waybill_execution_context(p_waybill_id);
end;
$$;

revoke all on function public.tms_cancel_assigned_waybill(uuid, text) from public, anon;
grant execute on function public.tms_cancel_assigned_waybill(uuid, text) to authenticated;

-- Destination check-in is the explicit arrival node. It records the address and
-- coordinates, then moves the waybill into unloading before evidence is entered.
create or replace function public.tms_check_in_waybill_cargo_operation(
  p_waybill_id uuid,
  p_operation_type text,
  p_longitude numeric,
  p_latitude numeric,
  p_accuracy_m numeric default null,
  p_location_text text default null,
  p_outside_reason text default null,
  p_automatic boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  operation_record public.tms_waybill_cargo_operation%rowtype;
  policy_value jsonb;
  center_longitude numeric;
  center_latitude numeric;
  radius_value integer;
  distance_value numeric;
  inside_value boolean;
  allow_outside boolean;
  auto_checkin boolean;
  is_driver boolean;
  is_manager boolean;
  mode_value text;
  operator_value text;
begin
  if p_operation_type not in ('loading', 'unloading') then
    raise exception '不支持的装卸货操作类型' using errcode = '22023';
  end if;
  if p_longitude is null or p_longitude not between -180 and 180
    or p_latitude is null or p_latitude not between -90 and 90 then
    raise exception '定位坐标无效，请重新定位' using errcode = '22023';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;
  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_cargo_operation(p_operation_type)
    and (app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id());
  if not is_driver and not is_manager then
    raise exception '无权操作该运单' using errcode = '42501';
  end if;

  if p_operation_type = 'loading'
     and waybill_record.status not in ('accepted', 'loading') then
    raise exception '当前运单状态不支持装货打卡' using errcode = '23514';
  end if;
  if p_operation_type = 'unloading'
     and waybill_record.status not in ('transporting', 'unloading') then
    raise exception '当前运单状态不支持到达打卡' using errcode = '23514';
  end if;

  policy_value := app_private.tms_cargo_operation_policy();
  if p_operation_type = 'loading' then
    center_longitude := waybill_record.shipper_longitude;
    center_latitude := waybill_record.shipper_latitude;
    radius_value := (policy_value ->> 'loadingRadiusM')::integer;
    allow_outside := (policy_value ->> 'loadingAllowOutsideCheckIn')::boolean;
    auto_checkin := (policy_value ->> 'autoConfirmLoading')::boolean;
  else
    center_longitude := waybill_record.receiver_longitude;
    center_latitude := waybill_record.receiver_latitude;
    radius_value := (policy_value ->> 'unloadingRadiusM')::integer;
    allow_outside := (policy_value ->> 'unloadingAllowOutsideCheckIn')::boolean;
    auto_checkin := (policy_value ->> 'autoConfirmUnloading')::boolean;
  end if;

  if center_longitude is null or center_latitude is null then
    raise exception '该运单未配置%坐标，请联系调度维护地址',
      case p_operation_type when 'loading' then '装货地' else '卸货地' end
      using errcode = '23514';
  end if;

  distance_value := app_private.tms_distance_m(
    p_longitude, p_latitude, center_longitude, center_latitude
  );
  inside_value := coalesce((policy_value ->> 'enabled')::boolean, true) is false
    or distance_value <= radius_value;

  if p_automatic and (not auto_checkin or not inside_value) then
    raise exception '当前定位不满足自动打卡条件' using errcode = '23514';
  end if;
  if not p_automatic and not inside_value and not allow_outside then
    raise exception '当前不在%围栏内，请到达现场后重新打卡',
      case p_operation_type when 'loading' then '装货地' else '卸货地' end
      using errcode = '23514';
  end if;
  if not inside_value and nullif(btrim(p_outside_reason), '') is null then
    raise exception '围栏外打卡必须填写原因' using errcode = '23514';
  end if;

  mode_value := case
    when p_automatic then 'automatic'
    when is_driver then 'manual'
    else 'admin'
  end;
  operator_value := app_private.tms_current_operator_name();

  insert into public.tms_waybill_cargo_operation (
    tenant_id, waybill_id, operation_type, operation_status,
    checkin_time, checkin_mode, operator_name, longitude, latitude,
    location_accuracy_m, location_text, geofence_center_longitude,
    geofence_center_latitude, geofence_radius_m, distance_m,
    inside_geofence, outside_reason
  ) values (
    waybill_record.tenant_id, waybill_record.id, p_operation_type,
    'checked_in', now(), mode_value, operator_value, p_longitude,
    p_latitude, p_accuracy_m, nullif(btrim(p_location_text), ''),
    center_longitude, center_latitude, radius_value, distance_value,
    inside_value, nullif(btrim(p_outside_reason), '')
  )
  on conflict (waybill_id, operation_type) do nothing
  returning * into operation_record;

  if operation_record.id is null then
    select * into operation_record
    from public.tms_waybill_cargo_operation
    where waybill_id = p_waybill_id and operation_type = p_operation_type;
  else
    if p_operation_type = 'unloading' and waybill_record.status = 'transporting' then
      update public.tms_waybill
      set status = 'unloading', arrived_at = operation_record.checkin_time
      where id = waybill_record.id;
    end if;

    insert into public.tms_waybill_event (
      tenant_id, waybill_id, event_type, event_time, operator_name,
      location_text, longitude, latitude, payload
    ) values (
      waybill_record.tenant_id, waybill_record.id,
      case p_operation_type when 'unloading' then 'arrived' else 'loading_checked_in' end,
      operation_record.checkin_time, operator_value, operation_record.location_text,
      p_longitude, p_latitude,
      jsonb_build_object(
        'action', case p_operation_type
          when 'unloading' then 'confirm_arrival'
          else 'loading_checkin'
        end,
        'checkinMode', mode_value,
        'insideGeofence', inside_value,
        'distanceM', distance_value,
        'radiusM', radius_value
      )
    );
  end if;

  return public.tms_get_waybill_cargo_operation_context(p_waybill_id, p_operation_type);
end;
$$;

-- Unloading completion no longer implies signature; signature is a separate popup action.
create or replace function public.tms_complete_waybill_cargo_operation(
  p_waybill_id uuid,
  p_operation_type text,
  p_weight_ton numeric,
  p_photo_urls jsonb,
  p_weighbridge_ticket_urls jsonb,
  p_remark text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  operation_record public.tms_waybill_cargo_operation%rowtype;
  is_driver boolean;
  is_manager boolean;
  operator_value text;
begin
  if p_operation_type not in ('loading', 'unloading') then
    raise exception '不支持的装卸货操作类型' using errcode = '22023';
  end if;
  if p_weight_ton is null or p_weight_ton <= 0 then
    raise exception '%重量必须大于 0 吨',
      case p_operation_type when 'loading' then '装货' else '卸货' end
      using errcode = '23514';
  end if;
  if not app_private.tms_valid_url_array(p_photo_urls) then
    raise exception '请上传 1 至 9 张现场照片' using errcode = '23514';
  end if;
  if not app_private.tms_valid_url_array(p_weighbridge_ticket_urls) then
    raise exception '请上传 1 至 9 张磅单' using errcode = '23514';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;
  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_cargo_operation(p_operation_type)
    and (app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id());
  if not is_driver and not is_manager then
    raise exception '无权操作该运单' using errcode = '42501';
  end if;

  select * into operation_record
  from public.tms_waybill_cargo_operation
  where waybill_id = p_waybill_id and operation_type = p_operation_type
  for update;
  if not found then
    raise exception '请先完成%打卡',
      case p_operation_type when 'loading' then '装货' else '到达' end
      using errcode = '23514';
  end if;
  if operation_record.operation_status = 'completed' then
    return public.tms_get_waybill_cargo_operation_context(p_waybill_id, p_operation_type);
  end if;

  if p_operation_type = 'loading' and waybill_record.status not in ('accepted', 'loading') then
    raise exception '当前运单状态不支持提交装货信息' using errcode = '23514';
  end if;
  if p_operation_type = 'unloading' and waybill_record.status <> 'unloading' then
    raise exception '当前运单状态不支持提交卸货信息' using errcode = '23514';
  end if;

  update public.tms_waybill_cargo_operation
  set operation_status = 'completed',
      weight_ton = p_weight_ton,
      photo_urls = p_photo_urls,
      weighbridge_ticket_urls = p_weighbridge_ticket_urls,
      completed_at = coalesce(completed_at, now()),
      remark = nullif(btrim(p_remark), '')
  where id = operation_record.id
  returning * into operation_record;

  if p_operation_type = 'loading' then
    update public.tms_waybill
    set status = case when status = 'accepted' then 'loading' else status end,
        loaded_at = coalesce(loaded_at, operation_record.completed_at),
        cargo_weight_ton = p_weight_ton,
        pickup_photos = p_photo_urls,
        receipt_attachments = coalesce(receipt_attachments, '[]'::jsonb)
          || p_weighbridge_ticket_urls
    where id = waybill_record.id;
  else
    update public.tms_waybill
    set unloaded_at = coalesce(unloaded_at, operation_record.completed_at),
        delivery_photos = p_photo_urls,
        receipt_attachments = coalesce(receipt_attachments, '[]'::jsonb)
          || p_weighbridge_ticket_urls
    where id = waybill_record.id;
  end if;

  operator_value := app_private.tms_current_operator_name();
  insert into public.tms_waybill_event (
    tenant_id, waybill_id, event_type, event_time, operator_name,
    location_text, longitude, latitude, payload, remark
  ) values (
    waybill_record.tenant_id, waybill_record.id,
    case p_operation_type when 'loading' then 'loaded' else 'unloaded' end,
    operation_record.completed_at, operator_value, operation_record.location_text,
    operation_record.longitude, operation_record.latitude,
    jsonb_build_object(
      'action', 'complete_' || p_operation_type,
      'weightTon', p_weight_ton,
      'photoCount', jsonb_array_length(p_photo_urls),
      'ticketCount', jsonb_array_length(p_weighbridge_ticket_urls),
      'checkinMode', operation_record.checkin_mode,
      'insideGeofence', operation_record.inside_geofence
    ),
    nullif(btrim(p_remark), '')
  );

  return public.tms_get_waybill_cargo_operation_context(p_waybill_id, p_operation_type);
end;
$$;
;
