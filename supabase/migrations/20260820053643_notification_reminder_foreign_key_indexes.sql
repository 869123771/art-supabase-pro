-- Cover every notification foreign key from its leading columns so deletes,
-- tenant cleanup, and reminder joins do not fall back to full-table scans.

create index if not exists sys_notification_rule_scenario_fk_idx
  on public.sys_notification_rule (scenario_id);

create index if not exists sys_notification_subject_owner_tenant_fk_idx
  on public.sys_notification_subject (owner_user_id, tenant_id);

create index if not exists sys_notification_subject_scenario_fk_idx
  on public.sys_notification_subject (scenario_id);

create index if not exists sys_notification_event_tenant_fk_idx
  on public.sys_notification_event (tenant_id);

create index if not exists sys_notification_event_rule_tenant_fk_idx
  on public.sys_notification_event (rule_id, tenant_id);

create index if not exists sys_notification_event_subject_tenant_fk_idx
  on public.sys_notification_event (subject_id, tenant_id);

create index if not exists sys_notification_delivery_tenant_fk_idx
  on public.sys_notification_delivery (tenant_id);

create index if not exists sys_notification_delivery_event_tenant_fk_idx
  on public.sys_notification_delivery (event_id, tenant_id);

create index if not exists sys_notification_delivery_user_tenant_fk_idx
  on public.sys_notification_delivery (recipient_user_id, tenant_id);

;
