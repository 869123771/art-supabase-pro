create index if not exists tms_carrier_payment_application_creator_tenant_idx
  on public.tms_carrier_payment_application (created_by_user_id, tenant_id);

;
