begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(32);

select has_table('public', 'smis_question_category', 'question categories exist');
select has_table('public', 'smis_question', 'question bank exists');
select has_table('public', 'smis_exam_paper', 'exam papers exist');
select has_table('public', 'smis_exam_paper_question', 'paper question snapshots exist');
select has_table('public', 'smis_learning_course', 'learning courses exist');
select has_table('public', 'smis_learning_course_assignment', 'course assignments exist');
select has_table('public', 'smis_exam_assignment', 'exam assignments exist');
select has_table('public', 'smis_exam_attempt', 'exam attempts exist');
select has_table('public', 'smis_exam_answer', 'exam answers exist');

select is(
  (select count(*)::integer
   from public.sys_dict_type
   where code in (
     'smisCourseStatus', 'smisCourseCategory', 'smisCourseType',
     'smisCourseLearningStatus', 'smisQuestionType', 'smisQuestionStatus',
     'smisExamAssemblyMode', 'smisExamPaperStatus', 'smisExamStatus'
   )),
  9,
  'all user-facing learning and assessment dictionaries exist'
);

select ok(
  not exists(
    select 1
    from (values
      ('smisCourseType', 'video'), ('smisCourseType', 'pdf'), ('smisCourseType', 'link'),
      ('smisQuestionType', 'single'), ('smisQuestionType', 'multiple'),
      ('smisQuestionType', 'judgement'), ('smisQuestionStatus', 'enabled'),
      ('smisQuestionStatus', 'disabled'), ('smisExamAssemblyMode', 'fixed'),
      ('smisExamAssemblyMode', 'random'), ('smisExamStatus', 'not_started'),
      ('smisExamStatus', 'in_progress'), ('smisExamStatus', 'passed'),
      ('smisExamStatus', 'failed')
    ) expected(dict_code, value)
    where not exists (
      select 1
      from public.sys_dict_type type
      join public.sys_dictionary item
        on item.type_id = type.id
       and item.tenant_id = type.tenant_id
      where type.code = expected.dict_code
        and item.value = expected.value
        and type.status = '1'
        and item.status = '1'
    )
  ),
  'all persisted enum values have enabled dictionary labels'
);

select ok(
  (select bool_and(relrowsecurity)
   from pg_class
   where oid = any(array[
     'public.smis_question_category'::regclass,
     'public.smis_question'::regclass,
     'public.smis_exam_paper'::regclass,
     'public.smis_exam_paper_question'::regclass,
     'public.smis_learning_course'::regclass,
     'public.smis_learning_course_assignment'::regclass,
     'public.smis_exam_assignment'::regclass,
     'public.smis_exam_attempt'::regclass,
     'public.smis_exam_answer'::regclass
   ])),
  'all learning and assessment tables enforce RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.smis_question', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smis_exam_paper', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smis_learning_course', 'DELETE')
  and not has_table_privilege('authenticated', 'public.smis_exam_answer', 'INSERT'),
  'authenticated callers cannot bypass secure RPC write boundaries'
);

select has_function('public', 'smis_list_question_bank_secure', array['integer', 'integer', 'text', 'uuid', 'text', 'text'], 'question list RPC exists');
select has_function('public', 'smis_manage_question_category_secure', array['text', 'jsonb'], 'question category RPC exists');
select has_function('public', 'smis_manage_question_secure', array['text', 'jsonb'], 'question write RPC exists');
select has_function('public', 'smis_generate_exam_questions_secure', array['jsonb'], 'random paper generation RPC exists');
select has_function('public', 'smis_list_exam_papers_secure', array['integer', 'integer', 'text', 'text', 'text'], 'paper list RPC exists');
select has_function('public', 'smis_manage_exam_paper_secure', array['text', 'jsonb'], 'paper write RPC exists');
select has_function('public', 'smis_get_exam_detail_secure', array['uuid', 'uuid', 'boolean'], 'exam detail RPC exists');
select has_function('public', 'smis_start_exam_secure', array['uuid'], 'start exam RPC exists');
select has_function('public', 'smis_save_exam_answer_secure', array['uuid', 'uuid', 'text[]'], 'answer autosave RPC exists');
select has_function('public', 'smis_submit_exam_secure', array['uuid'], 'submit exam RPC exists');
select has_function('public', 'smis_list_exam_records_secure', array['integer', 'integer', 'text', 'text'], 'exam record RPC exists');
select has_function('public', 'smis_list_courses_secure', array['integer', 'integer', 'text', 'text', 'text', 'text'], 'course list RPC exists');
select has_function('public', 'smis_manage_course_secure', array['text', 'jsonb'], 'course write RPC exists');
select has_function('public', 'smis_list_course_learning_records_secure', array['integer', 'integer', 'text', 'text'], 'learning record RPC exists');
select has_function('public', 'smis_update_course_learning_secure', array['uuid', 'numeric', 'integer', 'boolean'], 'learning progress RPC exists');

select ok(
  not has_function_privilege('anon', 'public.smis_manage_exam_paper_secure(text,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.smis_manage_exam_paper_secure(text,jsonb)', 'EXECUTE'),
  'only authenticated callers can invoke paper writes'
);

select is(
  (select count(*)::integer
   from pg_proc
   join pg_namespace on pg_namespace.oid = pronamespace
   where nspname = 'public'
     and proname in (
       'smis_list_question_bank_secure', 'smis_manage_question_category_secure',
       'smis_manage_question_secure', 'smis_generate_exam_questions_secure',
       'smis_list_exam_papers_secure', 'smis_manage_exam_paper_secure',
       'smis_get_exam_detail_secure', 'smis_start_exam_secure',
       'smis_save_exam_answer_secure', 'smis_submit_exam_secure',
       'smis_list_exam_records_secure', 'smis_list_courses_secure',
       'smis_manage_course_secure', 'smis_list_course_learning_records_secure',
       'smis_update_course_learning_secure'
     )
     and prosecdef),
  15,
  'all module RPCs execute through the security-definer boundary'
);

select ok(
  not exists(
    select 1
    from pg_proc
    join pg_namespace on pg_namespace.oid = pronamespace
    where nspname = 'public'
      and proname like 'smis_%_secure'
      and proname in (
        'smis_list_question_bank_secure', 'smis_manage_question_category_secure',
        'smis_manage_question_secure', 'smis_generate_exam_questions_secure',
        'smis_list_exam_papers_secure', 'smis_manage_exam_paper_secure',
        'smis_get_exam_detail_secure', 'smis_start_exam_secure',
        'smis_save_exam_answer_secure', 'smis_submit_exam_secure',
        'smis_list_exam_records_secure', 'smis_list_courses_secure',
        'smis_manage_course_secure', 'smis_list_course_learning_records_secure',
        'smis_update_course_learning_secure'
      )
      and not (coalesce(proconfig, '{}') @> array['search_path=""'])
  ),
  'all module RPCs pin an empty search path'
);

select ok(
  (select count(*)
   from pg_indexes
   where schemaname = 'public'
     and indexname in (
       'smis_question_category_tenant_parent_sort_idx',
       'smis_question_tenant_category_status_idx',
       'smis_exam_paper_tenant_status_time_idx',
       'smis_exam_paper_question_paper_sort_idx',
       'smis_exam_paper_question_question_idx',
       'smis_learning_course_tenant_status_due_idx',
       'smis_learning_course_assignment_employee_status_idx',
       'smis_learning_course_assignment_course_idx',
       'smis_exam_assignment_employee_status_idx',
       'smis_exam_assignment_paper_idx',
       'smis_exam_assignment_course_idx',
       'smis_exam_attempt_assignment_status_idx',
       'smis_exam_attempt_employee_idx',
       'smis_exam_answer_attempt_idx',
       'smis_exam_answer_question_idx'
     )) = 15,
  'tenant, lifecycle, assignment, attempt, and answer queries are indexed'
);

select * from finish();
rollback;
