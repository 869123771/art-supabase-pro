alter table public.ai_feedback
  drop constraint if exists ai_feedback_correction_issue_type_check;

alter table public.ai_feedback
  add constraint ai_feedback_correction_issue_type_check
  check (
    jsonb_typeof(correction) = 'object'
    and (
      correction ->> 'issueType' is null
      or correction ->> 'issueType' in (
        'incorrect',
        'incomplete',
        'irrelevant',
        'unsafe',
        'slow',
        'data_quality',
        'other'
      )
    )
  );

revoke all on table public.ai_feedback from public, anon, authenticated;
grant select, insert, update on table public.ai_feedback to authenticated;
grant all on table public.ai_feedback to service_role;

revoke all on sequence public.ai_feedback_id_seq from public, anon, authenticated;
grant usage, select on sequence public.ai_feedback_id_seq to authenticated;
grant all on sequence public.ai_feedback_id_seq to service_role;

create or replace function public.ai_quality_feedback_overview(p_days integer default 30)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with params as (
    select least(greatest(coalesce(p_days, 30), 1), 90) as days
  ),
  scoped_runs as (
    select run.*
    from public.ai_run run
    cross join params
    where run.started_at >= current_timestamp - make_interval(days => params.days)
  ),
  scoped_feedback as (
    select feedback.*, resolution.status as resolution_status,
      resolution.issue_type, resolution.resolution_note,
      resolution.handled_by, resolution.resolved_by,
      resolution.resolved_at, resolution.update_time as resolution_update_time
    from public.ai_feedback feedback
    join scoped_runs run on run.id = feedback.run_id
    left join public.ai_feedback_resolution resolution on resolution.feedback_id = feedback.id
  ),
  totals as (
    select
      (select count(*) from scoped_runs)::bigint as total_runs,
      count(*)::bigint as total_feedback,
      count(*) filter (where rating = 1)::bigint as positive_feedback,
      count(*) filter (where rating = -1)::bigint as negative_feedback,
      count(*) filter (
        where rating = -1 and coalesce(resolution_status, 'open') in ('open', 'in_progress')
      )::bigint as open_feedback_issues,
      count(*) filter (
        where rating = -1 and resolution_status in ('resolved', 'dismissed')
      )::bigint as closed_feedback_issues
    from scoped_feedback
  )
  select jsonb_build_object(
    'days', params.days,
    'canManageFeedback',
      (select app_private.is_platform_super()) or (select app_private.is_tenant_admin()),
    'totalRuns', totals.total_runs,
    'totalFeedback', totals.total_feedback,
    'unratedRuns', greatest(totals.total_runs - totals.total_feedback, 0),
    'feedbackCoverageRate', case
      when totals.total_runs = 0 then 0
      else round(totals.total_feedback::numeric * 100 / totals.total_runs, 1)
    end,
    'positiveFeedback', totals.positive_feedback,
    'negativeFeedback', totals.negative_feedback,
    'positiveRate', case
      when totals.total_feedback = 0 then 0
      else round(totals.positive_feedback::numeric * 100 / totals.total_feedback, 1)
    end,
    'openFeedbackIssues', totals.open_feedback_issues,
    'closedFeedbackIssues', totals.closed_feedback_issues,
    'resolutionRate', case
      when totals.negative_feedback = 0 then 100
      else round(totals.closed_feedback_issues::numeric * 100 / totals.negative_feedback, 1)
    end,
    'featureQuality', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'feature', stats.feature,
          'totalRuns', stats.total_runs,
          'successRate', stats.success_rate,
          'feedbackCount', stats.feedback_count,
          'feedbackCoverageRate', stats.feedback_coverage_rate,
          'positiveFeedback', stats.positive_feedback,
          'negativeFeedback', stats.negative_feedback,
          'openIssues', stats.open_issues
        )
        order by stats.open_issues desc, stats.feedback_coverage_rate asc, stats.total_runs desc
      )
      from (
        select
          run.feature,
          count(distinct run.id)::bigint as total_runs,
          round(
            count(distinct run.id) filter (where run.status = 'succeeded')::numeric
              * 100 / nullif(count(distinct run.id), 0),
            1
          ) as success_rate,
          count(distinct feedback.id)::bigint as feedback_count,
          round(
            count(distinct feedback.id)::numeric * 100 / nullif(count(distinct run.id), 0),
            1
          ) as feedback_coverage_rate,
          count(distinct feedback.id) filter (where feedback.rating = 1)::bigint as positive_feedback,
          count(distinct feedback.id) filter (where feedback.rating = -1)::bigint as negative_feedback,
          count(distinct feedback.id) filter (
            where feedback.rating = -1
              and coalesce(resolution.status, 'open') in ('open', 'in_progress')
          )::bigint as open_issues
        from scoped_runs run
        left join public.ai_feedback feedback on feedback.run_id = run.id
        left join public.ai_feedback_resolution resolution on resolution.feedback_id = feedback.id
        group by run.feature
      ) stats
    ), '[]'::jsonb),
    'feedbackQueue', coalesce((
      select jsonb_agg(queue.item order by queue.is_closed, queue.feedback_time desc)
      from (
        select
          jsonb_build_object(
            'feedbackId', feedback.id,
            'runId', feedback.run_id,
            'feature', run.feature,
            'model', run.model,
            'comment', feedback.comment,
            'feedbackTime', feedback.create_time,
            'runStartedAt', run.started_at,
            'status', coalesce(resolution.status, 'open'),
            'issueType', coalesce(
              resolution.issue_type,
              nullif(feedback.correction ->> 'issueType', '')
            ),
            'resolutionNote', resolution.resolution_note,
            'resolvedAt', resolution.resolved_at,
            'handledBy', resolution.handled_by
          ) as item,
          (coalesce(resolution.status, 'open') in ('resolved', 'dismissed')) as is_closed,
          feedback.create_time as feedback_time
        from scoped_feedback feedback
        join scoped_runs run on run.id = feedback.run_id
        left join public.ai_feedback_resolution resolution on resolution.feedback_id = feedback.id
        where feedback.rating = -1
        order by is_closed, feedback.create_time desc
        limit 8
      ) queue
    ), '[]'::jsonb)
  )
  from params
  cross join totals;
$$;

revoke all on function public.ai_quality_feedback_overview(integer) from public, anon;
grant execute on function public.ai_quality_feedback_overview(integer) to authenticated;
grant execute on function public.ai_quality_feedback_overview(integer) to service_role;

;
