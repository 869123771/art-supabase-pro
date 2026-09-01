-- Accident management is ordinary tenant business data. Write access is governed by
-- button permissions plus tenant isolation; platform-super remains an implicit override.

drop trigger if exists smis_accident_report_platform_super_write
  on public.smis_accident_report;
drop trigger if exists smis_accident_measure_platform_super_write
  on public.smis_accident_prevention_measure;
drop trigger if exists smis_accident_person_platform_super_write
  on public.smis_accident_person;
drop trigger if exists smis_accident_analysis_platform_super_write
  on public.smis_accident_analysis;
drop trigger if exists smis_accident_analysis_participant_platform_super_write
  on public.smis_accident_analysis_participant;
drop trigger if exists smis_work_injury_platform_super_write
  on public.smis_work_injury_declaration;

drop function if exists app_private.guard_smis_accident_platform_super_write();

drop policy if exists smis_accident_report_tenant_insert on public.smis_accident_report;
drop policy if exists smis_accident_report_tenant_update on public.smis_accident_report;
drop policy if exists smis_accident_report_tenant_delete on public.smis_accident_report;

create policy smis_accident_report_tenant_insert
on public.smis_accident_report
for insert
to authenticated
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Add'))
);

create policy smis_accident_report_tenant_update
on public.smis_accident_report
for update
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Edit'))
)
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Edit'))
);

create policy smis_accident_report_tenant_delete
on public.smis_accident_report
for delete
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Delete'))
);

drop policy if exists smis_accident_measure_tenant_insert
  on public.smis_accident_prevention_measure;
drop policy if exists smis_accident_measure_tenant_update
  on public.smis_accident_prevention_measure;
drop policy if exists smis_accident_measure_tenant_delete
  on public.smis_accident_prevention_measure;

create policy smis_accident_measure_tenant_insert
on public.smis_accident_prevention_measure
for insert
to authenticated
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (
    (select app_private.has_permission('SmisAccidentFlashReport:Add'))
    or (select app_private.has_permission('SmisAccidentFlashReport:Edit'))
  )
);

create policy smis_accident_measure_tenant_update
on public.smis_accident_prevention_measure
for update
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Edit'))
)
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Edit'))
);

create policy smis_accident_measure_tenant_delete
on public.smis_accident_prevention_measure
for delete
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Delete'))
);

drop policy if exists smis_accident_person_tenant_insert on public.smis_accident_person;
drop policy if exists smis_accident_person_tenant_update on public.smis_accident_person;
drop policy if exists smis_accident_person_tenant_delete on public.smis_accident_person;

create policy smis_accident_person_tenant_insert
on public.smis_accident_person
for insert
to authenticated
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (
    (select app_private.has_permission('SmisAccidentFlashReport:Add'))
    or (select app_private.has_permission('SmisAccidentFlashReport:Edit'))
  )
);

create policy smis_accident_person_tenant_update
on public.smis_accident_person
for update
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Edit'))
)
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Edit'))
);

create policy smis_accident_person_tenant_delete
on public.smis_accident_person
for delete
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentFlashReport:Delete'))
);

drop policy if exists smis_accident_analysis_tenant_insert on public.smis_accident_analysis;
drop policy if exists smis_accident_analysis_tenant_update on public.smis_accident_analysis;
drop policy if exists smis_accident_analysis_tenant_delete on public.smis_accident_analysis;

create policy smis_accident_analysis_tenant_insert
on public.smis_accident_analysis
for insert
to authenticated
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentInvestigation:Add'))
);

create policy smis_accident_analysis_tenant_update
on public.smis_accident_analysis
for update
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentInvestigation:Edit'))
)
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentInvestigation:Edit'))
);

create policy smis_accident_analysis_tenant_delete
on public.smis_accident_analysis
for delete
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentInvestigation:Delete'))
);

drop policy if exists smis_accident_analysis_participant_tenant_insert
  on public.smis_accident_analysis_participant;
drop policy if exists smis_accident_analysis_participant_tenant_update
  on public.smis_accident_analysis_participant;
drop policy if exists smis_accident_analysis_participant_tenant_delete
  on public.smis_accident_analysis_participant;

create policy smis_accident_analysis_participant_tenant_insert
on public.smis_accident_analysis_participant
for insert
to authenticated
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (
    (select app_private.has_permission('SmisAccidentInvestigation:Add'))
    or (select app_private.has_permission('SmisAccidentInvestigation:Edit'))
  )
);

create policy smis_accident_analysis_participant_tenant_update
on public.smis_accident_analysis_participant
for update
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentInvestigation:Edit'))
)
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentInvestigation:Edit'))
);

create policy smis_accident_analysis_participant_tenant_delete
on public.smis_accident_analysis_participant
for delete
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisAccidentInvestigation:Delete'))
);

drop policy if exists smis_work_injury_tenant_insert on public.smis_work_injury_declaration;
drop policy if exists smis_work_injury_tenant_update on public.smis_work_injury_declaration;
drop policy if exists smis_work_injury_tenant_delete on public.smis_work_injury_declaration;

create policy smis_work_injury_tenant_insert
on public.smis_work_injury_declaration
for insert
to authenticated
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisWorkInjuryDeclaration:Add'))
);

create policy smis_work_injury_tenant_update
on public.smis_work_injury_declaration
for update
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisWorkInjuryDeclaration:Edit'))
)
with check (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisWorkInjuryDeclaration:Edit'))
);

create policy smis_work_injury_tenant_delete
on public.smis_work_injury_declaration
for delete
to authenticated
using (
  (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (select app_private.has_permission('SmisWorkInjuryDeclaration:Delete'))
);

-- RLS does not protect TRUNCATE. Accident data is only maintained through DML/RPC paths.
revoke truncate, references, trigger
on table
  public.smis_accident_report,
  public.smis_accident_prevention_measure,
  public.smis_accident_person,
  public.smis_accident_analysis,
  public.smis_accident_analysis_participant,
  public.smis_work_injury_declaration
from authenticated, anon;

;
