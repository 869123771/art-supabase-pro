-- 同一应急预案允许制定多次演练计划；旧唯一约束会把每个状态限制为一条。
alter table public.smis_emergency_drill_plan
  drop constraint if exists smis_emergency_drill_plan_source_draft_uq;

-- 兼容不同历史环境中同一约束的自动命名。
alter table public.smis_emergency_drill_plan
  drop constraint if exists smis_emergency_drill_plan_tenant_id_source_plan_id_status_key;

create index if not exists smis_emergency_drill_plan_tenant_source_idx
  on public.smis_emergency_drill_plan(tenant_id,source_plan_id);

;
