-- These tables are intentionally RPC-only for authenticated users.  Their secure
-- RPCs perform tenant and button-permission checks, so direct write policies only
-- duplicated SELECT policies while no table privileges were granted.
drop policy if exists smis_equipment_boiler_write on public.smis_equipment_boiler;
drop policy if exists smis_equipment_relation_write on public.smis_equipment_relation;
drop policy if exists smis_equipment_reminder_config_write on public.smis_equipment_reminder_config;

;
