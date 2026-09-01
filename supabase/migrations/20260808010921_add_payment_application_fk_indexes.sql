-- 调整为外键列前导索引，同时保留租户内承运商筛选能力。
drop index if exists public.tms_carrier_payment_application_carrier_idx;
create index tms_carrier_payment_application_carrier_idx
  on public.tms_carrier_payment_application(carrier_id, tenant_id, create_time desc);

drop index if exists public.tms_carrier_payment_application_item_carrier_idx;
create index tms_carrier_payment_application_item_carrier_idx
  on public.tms_carrier_payment_application_item(carrier_id, tenant_id);

;
