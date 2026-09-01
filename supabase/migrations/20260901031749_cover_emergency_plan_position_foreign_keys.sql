create index if not exists smis_emergency_rescue_plan_legacy_position_fk_idx
  on public.smis_emergency_rescue_plan (applicable_position_id, tenant_id)
  where applicable_position_id is not null;

create index if not exists smis_emergency_rescue_plan_position_plan_fk_idx
  on public.smis_emergency_rescue_plan_position (rescue_plan_id, tenant_id);

create index if not exists smis_emergency_rescue_plan_position_position_fk_idx
  on public.smis_emergency_rescue_plan_position (position_id, tenant_id);

;
