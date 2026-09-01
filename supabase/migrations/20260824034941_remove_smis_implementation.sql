-- Remove the current SMIS implementation while retaining the registered SMIS
-- application identity as an empty host for the next implementation.

set local lock_timeout = '10s';
set local statement_timeout = '120s';

-- Remove configuration and audit data owned by the current SMIS implementation.
delete from public.sys_document_number_counter
where rule_id in (
  select id
  from public.sys_document_number_rule
  where rule_key like 'smis.%'
     or target_table like 'smis_%'
);

delete from public.sys_document_number_rule
where rule_key like 'smis.%'
   or target_table like 'smis_%';

delete from public.sys_document_number_scene
where rule_key like 'smis.%'
   or target_table like 'smis_%'
   or menu_id in (
     select id from public.sys_menu where app_code = 'smis'
   );

delete from public.sys_role_menu
where menu_id in (
  select id from public.sys_menu where app_code = 'smis'
);

delete from public.sys_menu
where app_code = 'smis';

delete from public.sys_dictionary
where type_id in (
  select id from public.sys_dict_type where code like 'smis%'
)
or code = 'workflowBusinessType_smis_hidden_danger'
or value = 'smis_hidden_danger';

do $$
declare
  deleted_count integer;
begin
  loop
    delete from public.sys_dict_type dictionary_type
    where dictionary_type.code like 'smis%'
      and not exists (
        select 1
        from public.sys_dict_type child
        where child.parent_id = dictionary_type.id
      );

    get diagnostics deleted_count = row_count;
    exit when not exists (
      select 1 from public.sys_dict_type where code like 'smis%'
    );

    if deleted_count = 0 then
      raise exception 'Unable to remove all SMIS dictionary types because non-SMIS children still reference them';
    end if;
  end loop;
end
$$;

delete from public.sys_role_field_permission
where resource_id in (
  select id from public.sys_permission_resource where resource_key like 'smis.%'
);

delete from public.sys_user_field_permission
where resource_id in (
  select id from public.sys_permission_resource where resource_key like 'smis.%'
);

delete from public.sys_permission_field
where resource_id in (
  select id from public.sys_permission_resource where resource_key like 'smis.%'
);

delete from public.sys_permission_resource
where resource_key like 'smis.%';

-- Remove any SMIS workflow runtime/configuration rows without touching the
-- shared workflow engine.
delete from public.sys_notification_delivery
where event_id in (
  select event_row.id
  from public.sys_notification_event event_row
  join public.sys_notification_subject subject_row on subject_row.id = event_row.subject_id
  left join public.sys_notification_scenario scenario_row on scenario_row.id = subject_row.scenario_id
  where subject_row.business_type like 'smis_%'
     or subject_row.route_path like '/smis/%'
     or scenario_row.module_code = 'smis'
     or scenario_row.scenario_code like 'smis_%'
);

delete from public.sys_notification_event
where subject_id in (
  select subject_row.id
  from public.sys_notification_subject subject_row
  left join public.sys_notification_scenario scenario_row on scenario_row.id = subject_row.scenario_id
  where subject_row.business_type like 'smis_%'
     or subject_row.route_path like '/smis/%'
     or scenario_row.module_code = 'smis'
     or scenario_row.scenario_code like 'smis_%'
);

delete from public.sys_notification_rule
where scenario_id in (
  select id
  from public.sys_notification_scenario
  where module_code = 'smis'
     or scenario_code like 'smis_%'
);

delete from public.sys_notification
where business_type like 'smis_%'
   or source_type like 'smis_%'
   or route_path like '/smis/%'
   or instance_id in (
     select id from public.wf_instance where business_type like 'smis_%'
   );

delete from public.sys_notification_subject
where business_type like 'smis_%'
   or route_path like '/smis/%'
   or scenario_id in (
     select id
     from public.sys_notification_scenario
     where module_code = 'smis'
        or scenario_code like 'smis_%'
   );

delete from public.sys_notification_scenario
where module_code = 'smis'
   or scenario_code like 'smis_%';

delete from public.wf_task_reminder_event
where instance_id in (
  select id from public.wf_instance where business_type like 'smis_%'
);

delete from public.wf_action
where instance_id in (
  select id from public.wf_instance where business_type like 'smis_%'
);

delete from public.wf_task
where instance_id in (
  select id from public.wf_instance where business_type like 'smis_%'
);

delete from public.wf_business_callback_attempt
where outbox_id in (
  select id
  from public.wf_business_callback_outbox
  where business_type like 'smis_%'
     or instance_id in (
       select id from public.wf_instance where business_type like 'smis_%'
     )
);

delete from public.wf_business_callback_outbox
where business_type like 'smis_%'
   or instance_id in (
     select id from public.wf_instance where business_type like 'smis_%'
   );

delete from public.wf_instance
where business_type like 'smis_%';

update public.wf_definition
set current_version_id = null
where business_type like 'smis_%'
   or code like 'smis_%';

delete from public.wf_version
where definition_id in (
  select id
  from public.wf_definition
  where business_type like 'smis_%'
     or code like 'smis_%'
);

delete from public.wf_definition
where business_type like 'smis_%'
   or code like 'smis_%';

-- Remove SMIS AI configuration, generated artifacts, telemetry and feedback.
delete from public.ai_artifact_review
where feature like 'smis_%'
   or entity_type like 'smis_%'
   or ai_run_id in (
     select id from public.ai_run where feature like 'smis_%'
   );

delete from public.ai_feedback_resolution
where feedback_id in (
  select feedback_row.id
  from public.ai_feedback feedback_row
  join public.ai_run run_row on run_row.id = feedback_row.run_id
  where run_row.feature like 'smis_%'
);

delete from public.ai_feedback
where run_id in (
  select id from public.ai_run where feature like 'smis_%'
);

delete from public.ai_tool_call
where run_id in (
  select id from public.ai_run where feature like 'smis_%'
);

delete from public.ai_run
where feature like 'smis_%';

delete from public.ai_ocr_quality_threshold
where feature like 'smis_%';

delete from public.ai_prompt_template
where feature like 'smis_%';

delete from public.ai_feature_config
where feature like 'smis_%';

-- Restore shared workflow dispatchers to their pre-SMIS behavior.
create or replace function app_private.execute_workflow_business_callback_before_hr(
  p_business_type text,
  p_business_id uuid,
  p_status text,
  p_actor text,
  p_comment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_business_type = 'tms_carrier_payment_application' then
    perform app_private.execute_carrier_payment_application_workflow_callback(
      p_business_id, p_status, p_actor, p_comment
    );
  elsif p_business_type = 'tms_expense_reimbursement' then
    perform app_private.execute_expense_reimbursement_workflow_callback(
      p_business_id, p_status, p_actor, p_comment
    );
  elsif p_business_type = 'vehicle_archive' then
    perform app_private.execute_vehicle_archive_workflow_callback(
      p_business_id, p_status, p_actor, p_comment
    );
  else
    perform app_private.execute_workflow_business_callback_legacy(
      p_business_type, p_business_id, p_status, p_actor, p_comment
    );
  end if;
end
$$;

create or replace function app_private.get_workflow_business_snapshot_v2(
  p_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  business_type_value text;
begin
  select instance_row.business_type
  into business_type_value
  from public.wf_instance instance_row
  where instance_row.id = p_instance_id;

  if business_type_value = 'tms_expense_reimbursement' then
    return app_private.get_expense_reimbursement_workflow_snapshot(p_instance_id);
  end if;

  return app_private.get_workflow_business_snapshot_v2_before_reimbursement(p_instance_id);
end
$$;

do $$
begin
  if to_regprocedure(
    'app_private.seed_field_permission_catalog_before_smis_accident_case(uuid)'
  ) is not null
  and to_regprocedure(
    'app_private.seed_field_permission_catalog_through_hr_employee(uuid)'
  ) is null then
    alter function app_private.seed_field_permission_catalog_before_smis_accident_case(uuid)
      rename to seed_field_permission_catalog_through_hr_employee;
  end if;
end
$$;

create or replace function app_private.seed_field_permission_catalog_before_tms_contract_recovery(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.seed_field_permission_catalog_through_hr_employee(p_tenant_id);
end
$$;

drop function if exists public.vms_list_vehicle_accident_options_secure(text, integer);

-- Drop every function whose name is owned by the SMIS namespace. Trigger
-- functions and table-bound triggers are deliberately removed together.
do $$
declare
  function_row record;
begin
  for function_row in
    select
      namespace_row.nspname as schema_name,
      procedure_row.proname as function_name,
      pg_get_function_identity_arguments(procedure_row.oid) as identity_arguments
    from pg_proc procedure_row
    join pg_namespace namespace_row on namespace_row.oid = procedure_row.pronamespace
    where namespace_row.nspname not in ('pg_catalog', 'information_schema')
      and procedure_row.prokind in ('f', 'p')
      and procedure_row.proname ~* '(^|_)smis(_|$)'
  loop
    execute format(
      'drop function if exists %I.%I(%s) cascade',
      function_row.schema_name,
      function_row.function_name,
      function_row.identity_arguments
    );
  end loop;
end
$$;

drop table if exists
  public.smis_accident_case_event,
  public.smis_hidden_danger_event,
  public.smis_risk_assessment_event,
  public.smis_business_event,
  public.smis_exam_attempt,
  public.smis_inspection_result,
  public.smis_control_measure,
  public.smis_risk_assessment_item,
  public.smis_hidden_danger,
  public.smis_inspection_task,
  public.smis_inspection_plan,
  public.smis_accident_case,
  public.smis_emergency_drill,
  public.smis_emergency_plan,
  public.smis_risk_assessment,
  public.smis_hazard_source,
  public.smis_risk_point,
  public.smis_area,
  public.smis_site,
  public.smis_business_record
cascade;

notify pgrst, 'reload schema';

;
