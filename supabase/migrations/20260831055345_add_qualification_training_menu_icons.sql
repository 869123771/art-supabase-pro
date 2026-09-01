begin;

with icon_seed(name, icon) as (
  values
    ('SmisWorkItem', 'ri:tools-line'),
    ('SmisWorkCategory', 'ri:folder-settings-line'),
    ('SmisPermittedOperationItem', 'ri:shield-check-line'),
    ('SmisSpecialEquipmentPersonnelCertificateLedger', 'ri:id-card-line'),
    ('SmisSpecialEquipmentOperatorCertificateLedger', 'ri:user-settings-line'),
    ('SmisSpecialOperationCertificate', 'ri:shield-flash-line'),
    ('SmisSafetyManagerCertificate', 'ri:shield-user-line'),
    ('SmisRegisteredSafetyEngineerLedger', 'ri:award-line'),
    ('SmisSafetyQualificationReportAnalysis', 'ri:bar-chart-box-line'),
    ('SmisSafetyTrainingPlan', 'ri:calendar-schedule-line'),
    ('SmisSafetyTrainingRecord', 'ri:clipboard-check-line'),
    ('SmisTrainingStatisticsReport', 'ri:bar-chart-grouped-line'),
    ('SmisCourseManagement', 'ri:book-open-line'),
    ('SmisExamManagement', 'ri:file-list-3-line'),
    ('SmisQuestionBankManagement', 'ri:questionnaire-line')
)
update public.sys_menu menu
set meta = jsonb_set(
      coalesce(menu.meta, '{}'::jsonb),
      '{icon}',
      to_jsonb(icon_seed.icon),
      true
    ),
    update_time = now()
from icon_seed
where menu.name = icon_seed.name
  and menu.type in ('folder', 'menu')
  and coalesce(menu.meta->>'icon', '') = '';

commit;;
