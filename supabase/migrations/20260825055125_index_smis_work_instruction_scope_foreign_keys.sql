create index if not exists smis_position_work_instruction_scope_instruction_idx
  on public.smis_position_work_instruction_scope (instruction_id);

create index if not exists smis_position_work_instruction_scope_position_tenant_idx
  on public.smis_position_work_instruction_scope (position_id, tenant_id);;
