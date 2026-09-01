create or replace function public.smis_list_active_hazard_factor_categories_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not (
    app_private.has_permission('SmisDualControlRiskIdentification:View')
    or app_private.has_permission('SmisDualControlRiskIdentification:Add')
    or app_private.has_permission('SmisDualControlRiskIdentification:Edit')
    or app_private.has_permission('SmisDualControlRiskEvaluationControl:View')
  ) then
    raise exception '当前账号没有读取危害因素类别的权限' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', category.id,
      'categoryCode', category.category_code,
      'categoryName', category.category_name,
      'factorType', category.factor_type
    ) order by category.factor_type, category.sort, category.category_name)
    from public.smis_hazard_factor_category category
    where category.tenant_id = v_tenant_id
      and category.status = 'enabled'
  ), '[]'::jsonb);
end
$$;

alter policy smis_risk_point_select
on public.smis_risk_point
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskIdentification:View'))
      or (select app_private.has_permission('SmisDualControlRiskEvaluationControl:View'))
    )
  )
);

alter policy smis_risk_assessment_model_select
on public.smis_risk_assessment_model
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskAssessmentStandardModel:View'))
      or (select app_private.has_permission('SmisDualControlRiskEvaluationControl:View'))
    )
  )
);

alter policy smis_risk_assessment_dimension_select
on public.smis_risk_assessment_dimension
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskAssessmentStandardModel:View'))
      or (select app_private.has_permission('SmisDualControlRiskEvaluationControl:View'))
    )
  )
);

alter policy smis_risk_assessment_criterion_select
on public.smis_risk_assessment_criterion
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskAssessmentStandardModel:View'))
      or (select app_private.has_permission('SmisDualControlRiskEvaluationControl:View'))
    )
  )
);

alter policy smis_risk_assessment_level_select
on public.smis_risk_assessment_level
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskAssessmentStandardModel:View'))
      or (select app_private.has_permission('SmisDualControlRiskEvaluationControl:View'))
    )
  )
);;
