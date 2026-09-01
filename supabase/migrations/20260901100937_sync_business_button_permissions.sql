do $$
declare
  v_definition record;
  v_parent public.sys_menu%rowtype;
begin
  for v_definition in
    select * from (values
      ('SmisLeaveInformation', 'SmisLeaveInformation:View', '查看请假信息', 1),
      ('SmisLeaveInformation', 'SmisLeaveInformation:Add', '新增请假信息', 2),
      ('SmisLeaveInformation', 'SmisLeaveInformation:Edit', '编辑请假信息', 3),
      ('SmisLeaveInformation', 'SmisLeaveInformation:Delete', '删除请假信息', 4),
      ('SmisLeaveInformation', 'SmisLeaveInformation:Export', '导出请假信息', 5),
      ('SmisDualControlHazardFactorCategory', 'SmisDualControlHazardFactorCategory:View', '查看危害因素类别', 1),
      ('SmisDualControlHazardFactorCategory', 'SmisDualControlHazardFactorCategory:Add', '新增危害因素类别', 2),
      ('SmisDualControlHazardFactorCategory', 'SmisDualControlHazardFactorCategory:Edit', '编辑危害因素类别', 3),
      ('SmisDualControlHazardFactorCategory', 'SmisDualControlHazardFactorCategory:Delete', '删除危害因素类别', 4),
      ('SmisDualControlRiskIdentification', 'SmisDualControlRiskIdentification:Export', '导出风险点', 8),
      ('SmisDualControlInspectionStandard', 'SmisDualControlInspectionStandard:View', '查看排查标准', 1),
      ('SmisDualControlInspectionStandard', 'SmisDualControlInspectionStandard:Add', '新增排查标准或排查项', 2),
      ('SmisDualControlInspectionStandard', 'SmisDualControlInspectionStandard:Edit', '编辑排查标准或排查项', 3),
      ('SmisDualControlInspectionStandard', 'SmisDualControlInspectionStandard:Delete', '删除排查标准或排查项', 4),
      ('SmisDualControlInspectionStandard', 'SmisDualControlInspectionStandard:Export', '导出排查项', 5),
      ('SmisDualControlInspectionStandard', 'SmisDualControlInspectionStandard:Void', '作废排查标准或排查项', 6),
      ('SmisDualControlInspectionType', 'SmisDualControlInspectionType:View', '查看排查类型', 1),
      ('SmisDualControlInspectionType', 'SmisDualControlInspectionType:Add', '新增排查类型', 2),
      ('SmisDualControlInspectionType', 'SmisDualControlInspectionType:Edit', '编辑排查类型', 3),
      ('SmisDualControlInspectionType', 'SmisDualControlInspectionType:Delete', '删除排查类型', 4),
      ('SmisDualControlInspectionType', 'SmisDualControlInspectionType:Export', '导出排查类型', 5),
      ('SmisDualControlInspectionType', 'SmisDualControlInspectionType:Void', '作废排查类型', 6),
      ('SmisDualControlDuplicateConfiguration', 'SmisDualControlDuplicateConfiguration:View', '查看重复配置', 1),
      ('SmisDualControlDuplicateConfiguration', 'SmisDualControlDuplicateConfiguration:Add', '新增重复配置', 2),
      ('SmisDualControlDuplicateConfiguration', 'SmisDualControlDuplicateConfiguration:Edit', '编辑重复配置', 3),
      ('SmisDualControlDuplicateConfiguration', 'SmisDualControlDuplicateConfiguration:Delete', '删除重复配置', 4),
      ('SmisDualControlDuplicateConfiguration', 'SmisDualControlDuplicateConfiguration:Export', '导出重复配置', 5),
      ('SmisDualControlDuplicateConfiguration', 'SmisDualControlDuplicateConfiguration:Void', '作废重复配置', 6),
      ('SmisDualControlRiskAssessmentStandardModel', 'SmisDualControlRiskAssessmentStandardModel:Add', '新增风险判定标准', 2),
      ('SmisDualControlRiskAssessmentStandardModel', 'SmisDualControlRiskAssessmentStandardModel:Edit', '编辑风险评估标准模型', 3),
      ('SmisDualControlRiskAssessmentStandardModel', 'SmisDualControlRiskAssessmentStandardModel:Delete', '删除风险判定标准', 4),
      ('SmisDualControlRiskEvaluationControl', 'SmisDualControlRiskEvaluationControl:AddMeasure', '新增风险控制措施', 3),
      ('SmisDualControlRiskEvaluationControl', 'SmisDualControlRiskEvaluationControl:EditMeasure', '编辑风险控制措施', 4),
      ('SmisDualControlRiskEvaluationControl', 'SmisDualControlRiskEvaluationControl:DeleteMeasure', '删除风险控制措施', 5),
      ('SmisDualControlRiskEvaluationControl', 'SmisDualControlRiskEvaluationControl:VoidMeasure', '作废风险控制措施', 6),
      ('SmisDualControlRiskEvaluationControl', 'SmisDualControlRiskEvaluationControl:Export', '导出风险评价及措施', 7),
      ('SmisSpecialEquipmentOperatorCertificateLedger', 'SmisSpecialEquipmentOperatorCertificateLedger:View', '查看作业人员证件台账', 1),
      ('SmisSpecialEquipmentOperatorCertificateLedger', 'SmisSpecialEquipmentOperatorCertificateLedger:Add', '新增作业人员证件', 2),
      ('SmisSpecialEquipmentOperatorCertificateLedger', 'SmisSpecialEquipmentOperatorCertificateLedger:Copy', '复制并新增', 3),
      ('SmisSpecialEquipmentOperatorCertificateLedger', 'SmisSpecialEquipmentOperatorCertificateLedger:Edit', '编辑作业人员证件', 4),
      ('SmisSpecialEquipmentOperatorCertificateLedger', 'SmisSpecialEquipmentOperatorCertificateLedger:Delete', '删除作业人员证件', 5),
      ('SmisSpecialEquipmentOperatorCertificateLedger', 'SmisSpecialEquipmentOperatorCertificateLedger:Export', '导出作业人员证件台账', 6),
      ('SmisSpecialEquipmentOperatorCertificateLedger', 'SmisSpecialEquipmentOperatorCertificateLedger:ViewHistory', '查看作业人员复审记录', 7),
      ('SmisSpecialOperationCertificate', 'SmisSpecialOperationCertificate:View', '查看特种作业操作证', 1),
      ('SmisSpecialOperationCertificate', 'SmisSpecialOperationCertificate:Add', '新增特种作业操作证', 2),
      ('SmisSpecialOperationCertificate', 'SmisSpecialOperationCertificate:Copy', '复制并新增', 3),
      ('SmisSpecialOperationCertificate', 'SmisSpecialOperationCertificate:Edit', '编辑特种作业操作证', 4),
      ('SmisSpecialOperationCertificate', 'SmisSpecialOperationCertificate:Delete', '删除特种作业操作证', 5),
      ('SmisSpecialOperationCertificate', 'SmisSpecialOperationCertificate:Export', '导出特种作业操作证', 6),
      ('SmisSpecialOperationCertificate', 'SmisSpecialOperationCertificate:ViewHistory', '查看特种作业复审记录', 7),
      ('SmisSafetyManagerCertificate', 'SmisSafetyManagerCertificate:View', '查看安全管理人员证', 1),
      ('SmisSafetyManagerCertificate', 'SmisSafetyManagerCertificate:Add', '新增安全管理人员证', 2),
      ('SmisSafetyManagerCertificate', 'SmisSafetyManagerCertificate:Copy', '复制并新增', 3),
      ('SmisSafetyManagerCertificate', 'SmisSafetyManagerCertificate:Edit', '编辑安全管理人员证', 4),
      ('SmisSafetyManagerCertificate', 'SmisSafetyManagerCertificate:Delete', '删除安全管理人员证', 5),
      ('SmisSafetyManagerCertificate', 'SmisSafetyManagerCertificate:Export', '导出安全管理人员证', 6),
      ('SmisSafetyManagerCertificate', 'SmisSafetyManagerCertificate:ViewHistory', '查看安全管理人员证复审记录', 7),
      ('SmisRegisteredSafetyEngineerLedger', 'SmisRegisteredSafetyEngineerLedger:View', '查看注册安全工程师台账', 1),
      ('SmisRegisteredSafetyEngineerLedger', 'SmisRegisteredSafetyEngineerLedger:Add', '新增注册安全工程师证', 2),
      ('SmisRegisteredSafetyEngineerLedger', 'SmisRegisteredSafetyEngineerLedger:Copy', '复制并新增', 3),
      ('SmisRegisteredSafetyEngineerLedger', 'SmisRegisteredSafetyEngineerLedger:Edit', '编辑注册安全工程师证', 4),
      ('SmisRegisteredSafetyEngineerLedger', 'SmisRegisteredSafetyEngineerLedger:Delete', '删除注册安全工程师证', 5),
      ('SmisRegisteredSafetyEngineerLedger', 'SmisRegisteredSafetyEngineerLedger:Export', '导出注册安全工程师台账', 6),
      ('SmisRegisteredSafetyEngineerLedger', 'SmisRegisteredSafetyEngineerLedger:ViewHistory', '查看注册安全工程师复审记录', 7),
      ('SmisSafetyTrainingPlan', 'SmisSafetyTrainingPlan:Copy', '复制并新增培训计划', 3),
      ('SmisSafetyTrainingPlan', 'SmisSafetyTrainingPlan:CreateRecord', '创建培训记录', 7),
      ('SmisSafetyTrainingPlan', 'SmisSafetyTrainingPlan:Export', '导出培训计划', 8),
      ('SmisSafetyTrainingRecord', 'SmisSafetyTrainingRecord:Export', '导出培训记录', 6),
      ('SmisTrainingStatisticsReport', 'SmisTrainingStatisticsReport:Export', '导出培训统计报表', 2),
      ('SmisCourseManagement', 'SmisCourseManagement:Export', '导出课程及学习记录', 9),
      ('SmisExamManagement', 'SmisExamManagement:Export', '导出考试记录', 12),
      ('SmisQuestionBankManagement', 'SmisQuestionBankManagement:Export', '导出题库', 7),
      ('HrOrganizationDesign', 'Hr:OrganizationDesign:View', '查看组织变革方案', 1),
      ('HrOrganizationDesign', 'Hr:OrganizationDesign:Scenario:Manage', '管理组织变革草稿', 2),
      ('HrOrganizationDesign', 'Hr:OrganizationDesign:Impact:Review', '提交影响评审', 3),
      ('HrOrganizationDesign', 'Hr:OrganizationDesign:Approve', '审批组织变革方案', 4),
      ('HrOrganizationDesign', 'Hr:OrganizationDesign:Handoff', '移交组织主数据执行', 5),
      ('HrInternalMobility', 'Hr:InternalMobility:View', '查看内部人才市场', 1),
      ('HrInternalMobility', 'Hr:InternalMobility:Opportunity:Manage', '管理内部机会草稿', 2),
      ('HrInternalMobility', 'Hr:InternalMobility:Publish', '发布与关闭内部机会', 3),
      ('HrInternalMobility', 'Hr:InternalMobility:Application:Self', '提交本人内部申请', 4),
      ('HrInternalMobility', 'Hr:InternalMobility:Application:Manage', '评审内部申请', 5),
      ('HrInternalMobility', 'Hr:InternalMobility:Convert', '转正式人事异动', 6)
    ) as definitions(parent_name, permission_code, title, sort_value)
  loop
    select *
    into v_parent
    from public.sys_menu
    where name = v_definition.parent_name
      and type <> 'button'
    limit 1;

    if v_parent.id is null then
      raise exception '未找到菜单：%', v_definition.parent_name;
    end if;

    insert into public.sys_menu(
      parent_id,
      name,
      path,
      component,
      type,
      sort,
      app_code,
      meta,
      create_by,
      update_by
    )
    select
      v_parent.id,
      v_definition.permission_code,
      null,
      null,
      'button',
      v_definition.sort_value,
      v_parent.app_code,
      jsonb_build_object(
        'title', v_definition.title,
        'icon', '',
        'is_hide', true,
        'is_enable', true,
        'roles', '[]'::jsonb
      ),
      '624944977@qq.com',
      '624944977@qq.com'
    where not exists (
      select 1
      from public.sys_menu existing
      where existing.name = v_definition.permission_code
        and existing.parent_id = v_parent.id
    );

    update public.sys_menu
    set sort = v_definition.sort_value,
        meta = jsonb_set(
          jsonb_set(
            coalesce(meta, '{}'::jsonb),
            '{title}',
            to_jsonb(v_definition.title),
            true
          ),
          '{is_enable}',
          'true'::jsonb,
          true
        ),
        update_by = '624944977@qq.com',
        update_time = now()
    where name = v_definition.permission_code
      and parent_id = v_parent.id;
  end loop;

  insert into public.sys_role_menu(
    role_id,
    menu_id,
    tenant_id,
    permission,
    create_by,
    update_by
  )
  select distinct
    page_grant.role_id,
    button.id,
    page_grant.tenant_id,
    '{}'::jsonb,
    '624944977@qq.com',
    '624944977@qq.com'
  from public.sys_role_menu page_grant
  join public.sys_menu page
    on page.id = page_grant.menu_id
  join public.sys_menu button
    on button.parent_id = page.id
   and button.type = 'button'
  where page.name in (
      'SmisLeaveInformation',
      'SmisDualControlHazardFactorCategory',
      'SmisDualControlRiskIdentification',
      'SmisDualControlInspectionStandard',
      'SmisDualControlInspectionType',
      'SmisDualControlDuplicateConfiguration',
      'SmisDualControlRiskAssessmentStandardModel',
      'SmisDualControlRiskEvaluationControl',
      'SmisSpecialEquipmentOperatorCertificateLedger',
      'SmisSpecialOperationCertificate',
      'SmisSafetyManagerCertificate',
      'SmisRegisteredSafetyEngineerLedger',
      'SmisSafetyTrainingPlan',
      'SmisSafetyTrainingRecord',
      'SmisTrainingStatisticsReport',
      'SmisCourseManagement',
      'SmisExamManagement',
      'SmisQuestionBankManagement',
      'HrOrganizationDesign',
      'HrInternalMobility'
  )
  on conflict (role_id, menu_id) do nothing;
end
$$;
