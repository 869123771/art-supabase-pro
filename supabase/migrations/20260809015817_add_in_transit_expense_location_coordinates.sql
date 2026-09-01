alter table public.tms_in_transit_expense
  add column if not exists expense_region text,
  add column if not exists expense_region_adcode text,
  add column if not exists expense_longitude numeric(10, 7),
  add column if not exists expense_latitude numeric(10, 7),
  add column if not exists expense_coordinate_system text,
  add column if not exists expense_coordinate_source text,
  add column if not exists expense_coordinate_status text not null default 'pending',
  add column if not exists expense_geocode_provider text,
  add column if not exists expense_geocoded_at timestamptz;

comment on column public.tms_in_transit_expense.expense_region is '费用发生地点省/市/区路径，以 / 分隔';
comment on column public.tms_in_transit_expense.expense_region_adcode is '费用发生地点行政区划代码';
comment on column public.tms_in_transit_expense.expense_longitude is '费用发生地点经度';
comment on column public.tms_in_transit_expense.expense_latitude is '费用发生地点纬度';
comment on column public.tms_in_transit_expense.expense_coordinate_system is '坐标系：gcj02、wgs84 或 bd09';
comment on column public.tms_in_transit_expense.expense_coordinate_source is '坐标来源：设备定位、地图选点、地理编码或导入';
comment on column public.tms_in_transit_expense.expense_coordinate_status is '坐标状态：pending、located、failed 或 unconfirmed';
comment on column public.tms_in_transit_expense.expense_geocode_provider is '地理编码服务商';
comment on column public.tms_in_transit_expense.expense_geocoded_at is '定位或地理编码完成时间';

alter table public.tms_in_transit_expense
  add constraint tms_in_transit_expense_longitude_check
    check (expense_longitude is null or expense_longitude between -180 and 180),
  add constraint tms_in_transit_expense_latitude_check
    check (expense_latitude is null or expense_latitude between -90 and 90),
  add constraint tms_in_transit_expense_coordinate_pair_check
    check ((expense_longitude is null) = (expense_latitude is null)),
  add constraint tms_in_transit_expense_coordinate_system_check
    check (expense_coordinate_system is null or expense_coordinate_system in ('gcj02', 'wgs84', 'bd09')),
  add constraint tms_in_transit_expense_coordinate_source_check
    check (expense_coordinate_source is null or expense_coordinate_source in ('device_geolocation', 'map_pick', 'geocode', 'import')),
  add constraint tms_in_transit_expense_coordinate_status_check
    check (expense_coordinate_status in ('pending', 'located', 'failed', 'unconfirmed'));

create or replace view public.tms_in_transit_expense_summary
with (security_invoker = true)
as
select
  e.id,
  e.tenant_id,
  e.expense_no,
  e.waybill_id,
  e.order_id,
  e.driver_id,
  e.expense_type,
  e.amount,
  e.occurred_at,
  e.quantity,
  e.unit_price,
  e.provider_name,
  e.payee_name,
  e.payment_channel,
  e.invoice_no,
  e.meter_no,
  e.expense_location,
  e.description,
  e.attachments,
  e.waybill_no_snapshot,
  e.order_no_snapshot,
  e.plate_no_snapshot,
  e.driver_name_snapshot,
  e.driver_phone_snapshot,
  e.route_snapshot,
  e.latest_ocr_run_id,
  e.ocr_artifact_id,
  e.ocr_status,
  e.report_status,
  e.reimbursement_status,
  e.payment_status,
  e.cost_id,
  e.submitted_at,
  e.submitted_by,
  e.reviewed_at,
  e.reviewed_by,
  e.review_remark,
  e.create_by,
  e.create_time,
  e.update_by,
  e.update_time,
  r.id as reimbursement_id,
  r.reimbursement_no,
  r.status as reimbursement_approval_status,
  p.payment_no,
  p.payment_date,
  p.bank_reference,
  w.status as waybill_status,
  e.expense_region,
  e.expense_region_adcode,
  e.expense_longitude,
  e.expense_latitude,
  e.expense_coordinate_system,
  e.expense_coordinate_source,
  e.expense_coordinate_status,
  e.expense_geocode_provider,
  e.expense_geocoded_at
from public.tms_in_transit_expense e
left join public.tms_expense_reimbursement_item ri on ri.expense_id = e.id
left join public.tms_expense_reimbursement r on r.id = ri.reimbursement_id
left join public.tms_expense_payment p on p.reimbursement_id = r.id
join public.tms_waybill w on w.id = e.waybill_id;;
