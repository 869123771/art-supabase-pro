begin;

create table if not exists public.smis_question_category (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  parent_id uuid,
  category_name text not null,
  status text not null default 'enabled',
  sort integer not null default 10,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_question_category_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id),
  constraint smis_question_category_id_tenant_unique unique (id, tenant_id),
  constraint smis_question_category_parent_fkey foreign key (parent_id, tenant_id)
    references public.smis_question_category(id, tenant_id),
  constraint smis_question_category_name_check check (char_length(btrim(category_name)) between 1 and 100),
  constraint smis_question_category_status_check check (status in ('enabled', 'disabled')),
  constraint smis_question_category_remark_check check (remark is null or char_length(remark) <= 500)
);

create unique index if not exists smis_question_category_name_unique
  on public.smis_question_category (
    tenant_id,
    coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(btrim(category_name))
  );

create table if not exists public.smis_question (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  category_id uuid not null,
  question_type text not null,
  stem text not null,
  options jsonb not null default '[]'::jsonb,
  correct_answers text[] not null default '{}'::text[],
  analysis text,
  default_score numeric(6, 2) not null default 1,
  status text not null default 'enabled',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_question_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id),
  constraint smis_question_category_fkey foreign key (category_id, tenant_id)
    references public.smis_question_category(id, tenant_id),
  constraint smis_question_id_tenant_unique unique (id, tenant_id),
  constraint smis_question_type_check check (question_type in ('single', 'multiple', 'judgement')),
  constraint smis_question_options_check check (jsonb_typeof(options) = 'array'),
  constraint smis_question_answers_check check (cardinality(correct_answers) >= 1),
  constraint smis_question_score_check check (default_score > 0),
  constraint smis_question_status_check check (status in ('enabled', 'disabled')),
  constraint smis_question_stem_check check (char_length(btrim(stem)) between 1 and 8000),
  constraint smis_question_analysis_check check (analysis is null or char_length(analysis) <= 8000)
);

create table if not exists public.smis_exam_paper (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  paper_no text not null,
  paper_title text not null,
  assembly_mode text not null default 'fixed',
  random_rule jsonb not null default '[]'::jsonb,
  total_score numeric(8, 2) not null default 0,
  passing_score numeric(8, 2) not null default 60,
  time_limit_minutes integer,
  allow_retake boolean not null default false,
  max_attempts integer not null default 1,
  open_at timestamptz,
  close_at timestamptz,
  status text not null default 'draft',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_exam_paper_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id),
  constraint smis_exam_paper_id_tenant_unique unique (id, tenant_id),
  constraint smis_exam_paper_no_unique unique (tenant_id, paper_no),
  constraint smis_exam_paper_mode_check check (assembly_mode in ('fixed', 'random')),
  constraint smis_exam_paper_rule_check check (jsonb_typeof(random_rule) = 'array'),
  constraint smis_exam_paper_score_check check (total_score >= 0 and passing_score > 0),
  constraint smis_exam_paper_time_check check (time_limit_minutes is null or time_limit_minutes between 1 and 1440),
  constraint smis_exam_paper_attempts_check check (max_attempts between 1 and 20),
  constraint smis_exam_paper_dates_check check (close_at is null or open_at is null or close_at > open_at),
  constraint smis_exam_paper_status_check check (status in ('draft', 'published', 'closed')),
  constraint smis_exam_paper_title_check check (char_length(btrim(paper_title)) between 1 and 200),
  constraint smis_exam_paper_remark_check check (remark is null or char_length(remark) <= 1000)
);

create table if not exists public.smis_exam_paper_question (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  paper_id uuid not null,
  question_id uuid not null,
  question_snapshot jsonb not null,
  score numeric(6, 2) not null,
  sort integer not null default 10,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_exam_paper_question_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id),
  constraint smis_exam_paper_question_paper_fkey foreign key (paper_id, tenant_id)
    references public.smis_exam_paper(id, tenant_id) on delete cascade,
  constraint smis_exam_paper_question_question_fkey foreign key (question_id, tenant_id)
    references public.smis_question(id, tenant_id),
  constraint smis_exam_paper_question_unique unique (tenant_id, paper_id, question_id),
  constraint smis_exam_paper_question_score_check check (score > 0),
  constraint smis_exam_paper_question_snapshot_check check (jsonb_typeof(question_snapshot) = 'object')
);

create table if not exists public.smis_learning_course (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  course_no text not null,
  course_name text not null,
  course_category text not null,
  course_type text not null,
  resource_url text,
  cover_url text,
  introduction text,
  minimum_learning_minutes integer not null default 0,
  credit_hours numeric(6, 2) not null default 0,
  due_date date,
  exam_paper_id uuid,
  status text not null default 'draft',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_learning_course_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id),
  constraint smis_learning_course_id_tenant_unique unique (id, tenant_id),
  constraint smis_learning_course_no_unique unique (tenant_id, course_no),
  constraint smis_learning_course_paper_fkey foreign key (exam_paper_id, tenant_id)
    references public.smis_exam_paper(id, tenant_id),
  constraint smis_learning_course_type_check check (course_type in ('video', 'pdf', 'link')),
  constraint smis_learning_course_status_check check (status in ('draft', 'published', 'closed')),
  constraint smis_learning_course_minutes_check check (minimum_learning_minutes >= 0),
  constraint smis_learning_course_credit_check check (credit_hours >= 0),
  constraint smis_learning_course_name_check check (char_length(btrim(course_name)) between 1 and 200),
  constraint smis_learning_course_intro_check check (introduction is null or char_length(introduction) <= 8000)
);

create table if not exists public.smis_learning_course_assignment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  course_id uuid not null,
  employee_id uuid not null,
  learning_status text not null default 'assigned',
  progress_percent numeric(5, 2) not null default 0,
  total_learning_seconds integer not null default 0,
  started_at timestamptz,
  last_learning_at timestamptz,
  completed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_learning_course_assignment_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id),
  constraint smis_learning_course_assignment_id_tenant_unique unique (id, tenant_id),
  constraint smis_learning_course_assignment_course_fkey foreign key (course_id, tenant_id)
    references public.smis_learning_course(id, tenant_id) on delete cascade,
  constraint smis_learning_course_assignment_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_learning_course_assignment_unique unique (tenant_id, course_id, employee_id),
  constraint smis_learning_course_assignment_status_check check (learning_status in ('assigned', 'in_progress', 'completed')),
  constraint smis_learning_course_assignment_progress_check check (progress_percent between 0 and 100),
  constraint smis_learning_course_assignment_seconds_check check (total_learning_seconds >= 0)
);

create table if not exists public.smis_exam_assignment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  paper_id uuid not null,
  employee_id uuid not null,
  course_assignment_id uuid,
  exam_status text not null default 'not_started',
  attempt_count integer not null default 0,
  best_score numeric(8, 2),
  started_at timestamptz,
  completed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_exam_assignment_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id),
  constraint smis_exam_assignment_id_tenant_unique unique (id, tenant_id),
  constraint smis_exam_assignment_paper_fkey foreign key (paper_id, tenant_id)
    references public.smis_exam_paper(id, tenant_id) on delete cascade,
  constraint smis_exam_assignment_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_exam_assignment_course_fkey foreign key (course_assignment_id, tenant_id)
    references public.smis_learning_course_assignment(id, tenant_id) on delete set null (course_assignment_id),
  constraint smis_exam_assignment_unique unique (tenant_id, paper_id, employee_id),
  constraint smis_exam_assignment_status_check check (exam_status in ('not_started', 'in_progress', 'passed', 'failed')),
  constraint smis_exam_assignment_count_check check (attempt_count >= 0),
  constraint smis_exam_assignment_score_check check (best_score is null or best_score >= 0)
);

create table if not exists public.smis_exam_attempt (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  assignment_id uuid not null,
  paper_id uuid not null,
  employee_id uuid not null,
  attempt_no integer not null,
  attempt_status text not null default 'in_progress',
  question_order uuid[] not null default '{}'::uuid[],
  started_at timestamptz not null default now(),
  expires_at timestamptz,
  submitted_at timestamptz,
  duration_seconds integer,
  score numeric(8, 2),
  passed boolean,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_exam_attempt_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id),
  constraint smis_exam_attempt_id_tenant_unique unique (id, tenant_id),
  constraint smis_exam_attempt_assignment_fkey foreign key (assignment_id, tenant_id)
    references public.smis_exam_assignment(id, tenant_id) on delete cascade,
  constraint smis_exam_attempt_paper_fkey foreign key (paper_id, tenant_id)
    references public.smis_exam_paper(id, tenant_id),
  constraint smis_exam_attempt_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_exam_attempt_unique unique (tenant_id, assignment_id, attempt_no),
  constraint smis_exam_attempt_status_check check (attempt_status in ('in_progress', 'graded')),
  constraint smis_exam_attempt_number_check check (attempt_no >= 1),
  constraint smis_exam_attempt_duration_check check (duration_seconds is null or duration_seconds >= 0),
  constraint smis_exam_attempt_score_check check (score is null or score >= 0)
);

create table if not exists public.smis_exam_answer (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  attempt_id uuid not null,
  question_id uuid not null,
  answer_values text[] not null default '{}'::text[],
  is_correct boolean,
  awarded_score numeric(6, 2),
  answered_at timestamptz not null default now(),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_exam_answer_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id),
  constraint smis_exam_answer_attempt_fkey foreign key (attempt_id, tenant_id)
    references public.smis_exam_attempt(id, tenant_id) on delete cascade,
  constraint smis_exam_answer_question_fkey foreign key (question_id, tenant_id)
    references public.smis_question(id, tenant_id),
  constraint smis_exam_answer_unique unique (tenant_id, attempt_id, question_id),
  constraint smis_exam_answer_score_check check (awarded_score is null or awarded_score >= 0)
);

create index if not exists smis_question_category_tenant_parent_sort_idx
  on public.smis_question_category (tenant_id, parent_id, sort, category_name);
create index if not exists smis_question_tenant_category_status_idx
  on public.smis_question (tenant_id, category_id, status, update_time desc);
create index if not exists smis_exam_paper_tenant_status_time_idx
  on public.smis_exam_paper (tenant_id, status, open_at, close_at);
create index if not exists smis_exam_paper_question_paper_sort_idx
  on public.smis_exam_paper_question (paper_id, sort);
create index if not exists smis_exam_paper_question_question_idx
  on public.smis_exam_paper_question (question_id);
create index if not exists smis_learning_course_tenant_status_due_idx
  on public.smis_learning_course (tenant_id, status, due_date);
create index if not exists smis_learning_course_assignment_employee_status_idx
  on public.smis_learning_course_assignment (tenant_id, employee_id, learning_status);
create index if not exists smis_learning_course_assignment_course_idx
  on public.smis_learning_course_assignment (course_id);
create index if not exists smis_exam_assignment_employee_status_idx
  on public.smis_exam_assignment (tenant_id, employee_id, exam_status);
create index if not exists smis_exam_assignment_paper_idx
  on public.smis_exam_assignment (paper_id);
create index if not exists smis_exam_assignment_course_idx
  on public.smis_exam_assignment (course_assignment_id) where course_assignment_id is not null;
create index if not exists smis_exam_attempt_assignment_status_idx
  on public.smis_exam_attempt (assignment_id, attempt_status, attempt_no desc);
create index if not exists smis_exam_attempt_employee_idx
  on public.smis_exam_attempt (tenant_id, employee_id, started_at desc);
create index if not exists smis_exam_answer_attempt_idx
  on public.smis_exam_answer (attempt_id);
create index if not exists smis_exam_answer_question_idx
  on public.smis_exam_answer (question_id);

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_question_category', 'smis_question', 'smis_exam_paper',
    'smis_exam_paper_question', 'smis_learning_course',
    'smis_learning_course_assignment', 'smis_exam_assignment',
    'smis_exam_attempt', 'smis_exam_answer'
  ] loop
    execute format('drop trigger if exists %I_create_audit on public.%I', v_table, v_table);
    execute format(
      'create trigger %I_create_audit before insert on public.%I for each row execute function public.trg_set_create_time_and_by(''true'', ''true'')',
      v_table, v_table
    );
    execute format('drop trigger if exists %I_update_audit on public.%I', v_table, v_table);
    execute format(
      'create trigger %I_update_audit before update on public.%I for each row execute function public.trg_set_update_time_and_by()',
      v_table, v_table
    );
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from anon', v_table);
    execute format('grant select on table public.%I to authenticated', v_table);
  end loop;
end;
$$;

create policy smis_question_category_select on public.smis_question_category
for select to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisQuestionBankManagement:View')
    or app_private.has_permission('SmisExamManagement:Add')
    or app_private.has_permission('SmisExamManagement:Edit')
  )
);
create policy smis_question_select on public.smis_question
for select to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisQuestionBankManagement:View')
    or app_private.has_permission('SmisExamManagement:Add')
    or app_private.has_permission('SmisExamManagement:Edit')
  )
);
create policy smis_exam_paper_select on public.smis_exam_paper
for select to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisExamManagement:View')
    or exists (
      select 1 from public.smis_exam_assignment assignment
      where assignment.paper_id = id
        and assignment.employee_id = app_private.hr_current_employee_id()
        and app_private.has_permission('SmisExamManagement:Take')
    )
  )
);
create policy smis_exam_paper_question_select on public.smis_exam_paper_question
for select to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('SmisExamManagement:ViewDetail')
);
create policy smis_learning_course_select on public.smis_learning_course
for select to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisCourseManagement:View')
    or exists (
      select 1 from public.smis_learning_course_assignment assignment
      where assignment.course_id = id
        and assignment.employee_id = app_private.hr_current_employee_id()
        and app_private.has_permission('SmisCourseManagement:Learn')
    )
  )
);
create policy smis_learning_course_assignment_select on public.smis_learning_course_assignment
for select to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisCourseManagement:ViewLearningRecord')
    or (
      employee_id = app_private.hr_current_employee_id()
      and app_private.has_permission('SmisCourseManagement:Learn')
    )
  )
);
create policy smis_exam_assignment_select on public.smis_exam_assignment
for select to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisExamManagement:ViewRecord')
    or (
      employee_id = app_private.hr_current_employee_id()
      and app_private.has_permission('SmisExamManagement:Take')
    )
  )
);
create policy smis_exam_attempt_select on public.smis_exam_attempt
for select to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisExamManagement:ViewRecord')
    or (
      employee_id = app_private.hr_current_employee_id()
      and app_private.has_permission('SmisExamManagement:Take')
    )
  )
);
create policy smis_exam_answer_select on public.smis_exam_answer
for select to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and exists (
    select 1 from public.smis_exam_attempt attempt
    where attempt.id = attempt_id
      and (
        app_private.has_permission('SmisExamManagement:ViewRecord')
        or (
          attempt.employee_id = app_private.hr_current_employee_id()
          and app_private.has_permission('SmisExamManagement:Take')
        )
      )
  )
);

with dictionary_parent as (
  select tenant_id, parent_id from public.sys_dict_type where code = 'smisTrainingManagement'
), dictionary_seed(name, code, remark, sort) as (
  values
    ('课程状态', 'smisCourseStatus', '课程草稿、发布与关闭状态。', 20),
    ('课程分类', 'smisCourseCategory', '课程业务主题分类。', 21),
    ('课程类型', 'smisCourseType', '课程资源承载方式。', 22),
    ('学习状态', 'smisCourseLearningStatus', '员工课程学习进度状态。', 23),
    ('题目类型', 'smisQuestionType', '单选、多选和判断题。', 24),
    ('题目状态', 'smisQuestionStatus', '题目启用与停用状态。', 25),
    ('组卷方式', 'smisExamAssemblyMode', '固定试题或随机规则组卷。', 26),
    ('试卷状态', 'smisExamPaperStatus', '试卷草稿、发布与关闭状态。', 27),
    ('考试状态', 'smisExamStatus', '员工考试进度与成绩状态。', 28)
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, create_time, update_by, update_time,
  remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), seed.name, seed.code, '1', '624944977@qq.com', now(),
  '624944977@qq.com', now(), seed.remark, parent.tenant_id, parent.parent_id,
  'dictionary', seed.sort
from dictionary_parent parent cross join dictionary_seed seed
where not exists (select 1 from public.sys_dict_type existing where existing.code = seed.code);

with dictionary_value(dict_code, value, label, sort, tag_type) as (
  values
    ('smisCourseStatus', 'draft', '草稿', 1, 'info'),
    ('smisCourseStatus', 'published', '已发布', 2, 'success'),
    ('smisCourseStatus', 'closed', '已关闭', 3, 'danger'),
    ('smisCourseCategory', 'safety_production', '安全生产', 1, null),
    ('smisCourseCategory', 'equipment', '设备安全', 2, null),
    ('smisCourseCategory', 'emergency', '应急管理', 3, 'warning'),
    ('smisCourseCategory', 'compliance', '法规制度', 4, 'primary'),
    ('smisCourseCategory', 'other', '其他', 5, 'info'),
    ('smisCourseType', 'video', '视频', 1, 'primary'),
    ('smisCourseType', 'pdf', 'PDF 文档', 2, 'danger'),
    ('smisCourseType', 'link', '外部链接', 3, 'info'),
    ('smisCourseLearningStatus', 'assigned', '待学习', 1, 'info'),
    ('smisCourseLearningStatus', 'in_progress', '学习中', 2, 'warning'),
    ('smisCourseLearningStatus', 'completed', '已完成', 3, 'success'),
    ('smisQuestionType', 'single', '单选题', 1, 'primary'),
    ('smisQuestionType', 'multiple', '多选题', 2, 'warning'),
    ('smisQuestionType', 'judgement', '判断题', 3, 'success'),
    ('smisQuestionStatus', 'enabled', '启用', 1, 'success'),
    ('smisQuestionStatus', 'disabled', '停用', 2, 'info'),
    ('smisExamAssemblyMode', 'fixed', '固定试题组卷', 1, 'primary'),
    ('smisExamAssemblyMode', 'random', '随机试题组卷', 2, 'warning'),
    ('smisExamPaperStatus', 'draft', '草稿', 1, 'info'),
    ('smisExamPaperStatus', 'published', '已发布', 2, 'success'),
    ('smisExamPaperStatus', 'closed', '已关闭', 3, 'danger'),
    ('smisExamStatus', 'not_started', '未开始', 1, 'info'),
    ('smisExamStatus', 'in_progress', '考试中', 2, 'warning'),
    ('smisExamStatus', 'passed', '及格', 3, 'success'),
    ('smisExamStatus', 'failed', '不及格', 4, 'danger')
)
insert into public.sys_dictionary (
  id, type_id, code, status, create_by, create_time, update_by, update_time,
  value, label, sort, tenant_id, tag_type
)
select gen_random_uuid(), type.id, value.dict_code || '_' || value.value, '1',
  '624944977@qq.com', now(), '624944977@qq.com', now(), value.value,
  value.label, value.sort, type.tenant_id, value.tag_type
from dictionary_value value join public.sys_dict_type type on type.code = value.dict_code
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = type.id and existing.value = value.value
);

with button_seed(page_name, action, title, sort) as (
  values
    ('SmisCourseManagement', 'View', '查看课程', 1),
    ('SmisCourseManagement', 'Add', '新增课程', 2),
    ('SmisCourseManagement', 'Edit', '编辑课程', 3),
    ('SmisCourseManagement', 'Delete', '删除课程', 4),
    ('SmisCourseManagement', 'Publish', '发布或关闭课程', 5),
    ('SmisCourseManagement', 'Assign', '分配学习人员', 6),
    ('SmisCourseManagement', 'Learn', '开始或继续学习', 7),
    ('SmisCourseManagement', 'ViewLearningRecord', '查看学习记录', 8),
    ('SmisCourseManagement', 'Export', '导出课程及学习记录', 9),
    ('SmisExamManagement', 'View', '查看试卷', 1),
    ('SmisExamManagement', 'Add', '创建试卷', 2),
    ('SmisExamManagement', 'Edit', '编辑试卷', 3),
    ('SmisExamManagement', 'Delete', '删除试卷', 4),
    ('SmisExamManagement', 'Generate', '随机生成试题', 5),
    ('SmisExamManagement', 'Publish', '发布或关闭试卷', 6),
    ('SmisExamManagement', 'Assign', '分配考试人员', 7),
    ('SmisExamManagement', 'Preview', '考试预览', 8),
    ('SmisExamManagement', 'Take', '开始或继续考试', 9),
    ('SmisExamManagement', 'ViewRecord', '查看考试记录', 10),
    ('SmisExamManagement', 'ViewDetail', '查看试卷与答卷详情', 11),
    ('SmisExamManagement', 'Export', '导出考试记录', 12),
    ('SmisQuestionBankManagement', 'View', '查看题库', 1),
    ('SmisQuestionBankManagement', 'Add', '新增题目', 2),
    ('SmisQuestionBankManagement', 'Edit', '编辑题目', 3),
    ('SmisQuestionBankManagement', 'Delete', '删除题目', 4),
    ('SmisQuestionBankManagement', 'ManageCategory', '维护题库分类', 5),
    ('SmisQuestionBankManagement', 'ToggleStatus', '启用或停用题目', 6),
    ('SmisQuestionBankManagement', 'Export', '导出题库', 7)
), inserted as (
  insert into public.sys_menu (
    id, parent_id, name, path, component, meta, sort, create_by,
    create_time, update_by, update_time, type, app_code
  )
  select gen_random_uuid(), page.id, seed.page_name || ':' || seed.action, '', null,
    jsonb_build_object('icon', '', 'roles', jsonb_build_array(), 'title', seed.title,
      'is_hide', true, 'is_enable', true),
    seed.sort, '624944977@qq.com', now(), '624944977@qq.com', now(), 'button', page.app_code
  from button_seed seed join public.sys_menu page on page.name = seed.page_name
  where not exists (
    select 1 from public.sys_menu existing where existing.name = seed.page_name || ':' || seed.action
  ) returning id, parent_id
)
insert into public.sys_role_menu (role_id, menu_id, tenant_id)
select distinct assignment.role_id, button.id, assignment.tenant_id
from inserted button join public.sys_role_menu assignment on assignment.menu_id = button.parent_id
on conflict do nothing;

comment on table public.smis_question_category is '租户隔离的安全培训题库分类。';
comment on table public.smis_question is '安全培训客观题库；试卷使用快照保证历史答案不被题库修改影响。';
comment on table public.smis_exam_paper is '固定或随机组卷的安全培训试卷主表。';
comment on table public.smis_exam_paper_question is '试卷题目及不可变题目快照。';
comment on table public.smis_learning_course is '安全培训课程内容、发布状态和关联考试。';
comment on table public.smis_learning_course_assignment is '课程与员工之间的学习任务及进度。';
comment on table public.smis_exam_assignment is '试卷与员工之间的考试任务及最佳成绩。';
comment on table public.smis_exam_attempt is '员工每一次独立考试尝试。';
comment on table public.smis_exam_answer is '考试尝试的逐题作答与自动评分结果。';

create or replace function public.smis_list_question_bank_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_category_id uuid default null,
  p_question_type text default null,
  p_status text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisQuestionBankManagement:View')
     and not app_private.has_permission('SmisExamManagement:Add')
     and not app_private.has_permission('SmisExamManagement:Edit') then
    raise exception '没有查看题库的权限' using errcode = '42501';
  end if;
  v_tenant := app_private.current_user_tenant_id();

  return (
    with filtered as (
      select question.*, category.category_name
      from public.smis_question question
      join public.smis_question_category category
        on category.id = question.category_id and category.tenant_id = question.tenant_id
      where question.tenant_id = v_tenant
        and (p_category_id is null or question.category_id = p_category_id)
        and (p_question_type is null or question.question_type = p_question_type)
        and (p_status is null or question.status = p_status)
        and (nullif(btrim(coalesce(p_keyword, '')), '') is null
          or question.stem ilike '%' || btrim(p_keyword) || '%'
          or coalesce(question.analysis, '') ilike '%' || btrim(p_keyword) || '%')
    ), page as (
      select * from filtered order by update_time desc, id offset v_from limit v_to - v_from + 1
    )
    select jsonb_build_object(
      'records', coalesce((select jsonb_agg(jsonb_build_object(
        'id', item.id, 'categoryId', item.category_id, 'categoryName', item.category_name,
        'questionType', item.question_type, 'stem', item.stem, 'options', item.options,
        'correctAnswers', to_jsonb(item.correct_answers), 'analysis', item.analysis,
        'defaultScore', item.default_score, 'status', item.status,
        'createTime', item.create_time, 'updateTime', item.update_time
      ) order by item.update_time desc) from page item), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'overview', jsonb_build_object(
        'total', (select count(*) from public.smis_question where tenant_id = v_tenant),
        'enabled', (select count(*) from public.smis_question where tenant_id = v_tenant and status = 'enabled'),
        'single', (select count(*) from public.smis_question where tenant_id = v_tenant and question_type = 'single'),
        'multiple', (select count(*) from public.smis_question where tenant_id = v_tenant and question_type = 'multiple'),
        'judgement', (select count(*) from public.smis_question where tenant_id = v_tenant and question_type = 'judgement')
      ),
      'categories', coalesce((select jsonb_agg(jsonb_build_object(
        'id', category.id, 'parentId', category.parent_id, 'categoryName', category.category_name,
        'status', category.status, 'sort', category.sort, 'remark', category.remark,
        'questionCount', (select count(*) from public.smis_question question where question.category_id = category.id and question.tenant_id = v_tenant)
      ) order by category.sort, category.category_name)
      from public.smis_question_category category where category.tenant_id = v_tenant), '[]'::jsonb)
    )
  );
end;
$function$;

create or replace function public.smis_manage_question_category_secure(
  p_action text,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare v_tenant uuid; v_id uuid; v_parent uuid; v_name text;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisQuestionBankManagement:ManageCategory') then
    raise exception '没有维护题库分类的权限' using errcode = '42501';
  end if;
  v_tenant := app_private.current_user_tenant_id();
  v_id := nullif(p_payload ->> 'id', '')::uuid;
  if p_action = 'delete' then
    if exists (select 1 from public.smis_question where tenant_id = v_tenant and category_id = v_id) then
      raise exception '分类下已有题目，不能删除';
    end if;
    delete from public.smis_question_category where id = v_id and tenant_id = v_tenant;
    if not found then raise exception '题库分类不存在'; end if;
    return v_id;
  end if;
  if p_action <> 'save' then raise exception '不支持的分类操作'; end if;
  v_name := btrim(coalesce(p_payload ->> 'category_name', ''));
  v_parent := nullif(p_payload ->> 'parent_id', '')::uuid;
  if v_name = '' then raise exception '请输入分类名称'; end if;
  if v_parent is not null and not exists (
    select 1 from public.smis_question_category where id = v_parent and tenant_id = v_tenant
  ) then raise exception '上级分类不存在'; end if;
  if v_id is null then
    insert into public.smis_question_category (tenant_id, parent_id, category_name, status, sort, remark)
    values (v_tenant, v_parent, v_name, coalesce(nullif(p_payload ->> 'status', ''), 'enabled'),
      greatest(coalesce((p_payload ->> 'sort')::integer, 10), 0), nullif(btrim(p_payload ->> 'remark'), ''))
    returning id into v_id;
  else
    if v_parent = v_id then raise exception '上级分类不能选择自身'; end if;
    update public.smis_question_category set parent_id = v_parent, category_name = v_name,
      status = coalesce(nullif(p_payload ->> 'status', ''), status),
      sort = greatest(coalesce((p_payload ->> 'sort')::integer, sort), 0),
      remark = nullif(btrim(p_payload ->> 'remark'), '')
    where id = v_id and tenant_id = v_tenant;
    if not found then raise exception '题库分类不存在'; end if;
  end if;
  return v_id;
end;
$function$;

create or replace function public.smis_manage_question_secure(
  p_action text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid; v_id uuid; v_ids uuid[]; v_type text; v_options jsonb;
  v_answers text[]; v_required_permission text;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  v_required_permission := case p_action when 'delete' then 'SmisQuestionBankManagement:Delete'
    when 'toggle' then 'SmisQuestionBankManagement:ToggleStatus'
    else case when nullif(p_payload ->> 'id', '') is null then 'SmisQuestionBankManagement:Add' else 'SmisQuestionBankManagement:Edit' end end;
  if not app_private.has_permission(v_required_permission) then
    raise exception '没有执行题库操作的权限' using errcode = '42501';
  end if;
  v_tenant := app_private.current_user_tenant_id();
  if p_action in ('delete', 'toggle') then
    select coalesce(array_agg(value::uuid), '{}'::uuid[]) into v_ids
    from jsonb_array_elements_text(coalesce(p_payload -> 'ids', '[]'::jsonb));
    if cardinality(v_ids) = 0 then raise exception '请选择题目'; end if;
    if p_action = 'delete' then
      if exists (select 1 from public.smis_exam_paper_question where tenant_id = v_tenant and question_id = any(v_ids)) then
        raise exception '题目已被试卷引用，请停用而不是删除';
      end if;
      delete from public.smis_question where tenant_id = v_tenant and id = any(v_ids);
    else
      update public.smis_question set status = coalesce(nullif(p_payload ->> 'status', ''), 'disabled')
      where tenant_id = v_tenant and id = any(v_ids);
    end if;
    return jsonb_build_object('affected', cardinality(v_ids));
  end if;
  if p_action <> 'save' then raise exception '不支持的题目操作'; end if;
  v_id := nullif(p_payload ->> 'id', '')::uuid;
  v_type := p_payload ->> 'question_type';
  v_options := coalesce(p_payload -> 'options', '[]'::jsonb);
  select coalesce(array_agg(value), '{}'::text[]) into v_answers
  from jsonb_array_elements_text(coalesce(p_payload -> 'correct_answers', '[]'::jsonb));
  if v_type not in ('single', 'multiple', 'judgement') then raise exception '请选择题目类型'; end if;
  if btrim(coalesce(p_payload ->> 'stem', '')) = '' then raise exception '请输入题目'; end if;
  if jsonb_typeof(v_options) <> 'array' or jsonb_array_length(v_options) < 2 then raise exception '至少维护两个答案选项'; end if;
  if cardinality(v_answers) = 0 then raise exception '请设置正确答案'; end if;
  if v_type in ('single', 'judgement') and cardinality(v_answers) <> 1 then raise exception '单选题和判断题只能设置一个正确答案'; end if;
  if not exists (select 1 from public.smis_question_category where id = (p_payload ->> 'category_id')::uuid and tenant_id = v_tenant and status = 'enabled') then
    raise exception '请选择已启用的题库分类';
  end if;
  if v_id is null then
    insert into public.smis_question (tenant_id, category_id, question_type, stem, options, correct_answers, analysis, default_score, status)
    values (v_tenant, (p_payload ->> 'category_id')::uuid, v_type, btrim(p_payload ->> 'stem'), v_options,
      v_answers, nullif(btrim(p_payload ->> 'analysis'), ''), greatest(coalesce((p_payload ->> 'default_score')::numeric, 1), 0.01),
      coalesce(nullif(p_payload ->> 'status', ''), 'enabled')) returning id into v_id;
  else
    if exists (select 1 from public.smis_exam_paper_question pq join public.smis_exam_paper p on p.id = pq.paper_id and p.tenant_id = pq.tenant_id
      where pq.tenant_id = v_tenant and pq.question_id = v_id and p.status <> 'draft') then
      raise exception '题目已被发布试卷使用；请新增题目版本，避免影响业务口径';
    end if;
    update public.smis_question set category_id = (p_payload ->> 'category_id')::uuid,
      question_type = v_type, stem = btrim(p_payload ->> 'stem'), options = v_options,
      correct_answers = v_answers, analysis = nullif(btrim(p_payload ->> 'analysis'), ''),
      default_score = greatest(coalesce((p_payload ->> 'default_score')::numeric, 1), 0.01),
      status = coalesce(nullif(p_payload ->> 'status', ''), status)
    where id = v_id and tenant_id = v_tenant;
    if not found then raise exception '题目不存在'; end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$function$;

create or replace function public.smis_generate_exam_questions_secure(p_rules jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_tenant uuid; v_rule jsonb; v_result jsonb := '[]'::jsonb; v_found integer;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisExamManagement:Generate') then raise exception '没有随机组卷权限' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(p_rules, 'null'::jsonb)) <> 'array' or jsonb_array_length(p_rules) = 0 then raise exception '请至少配置一条抽题规则'; end if;
  v_tenant := app_private.current_user_tenant_id();
  for v_rule in select value from jsonb_array_elements(p_rules) loop
    if coalesce((v_rule ->> 'count')::integer, 0) <= 0 or coalesce((v_rule ->> 'score')::numeric, 0) <= 0 then raise exception '抽题数量和每题分值必须大于 0'; end if;
    select count(*) into v_found from public.smis_question
    where tenant_id = v_tenant and status = 'enabled'
      and (nullif(v_rule ->> 'category_id', '') is null or category_id = (v_rule ->> 'category_id')::uuid)
      and (nullif(v_rule ->> 'question_type', '') is null or question_type = v_rule ->> 'question_type');
    if v_found < (v_rule ->> 'count')::integer then raise exception '抽题规则可用题目不足：需要 % 道，仅有 % 道', (v_rule ->> 'count')::integer, v_found; end if;
    v_result := v_result || coalesce((select jsonb_agg(jsonb_build_object(
      'questionId', sample.id, 'categoryId', sample.category_id, 'questionType', sample.question_type,
      'stem', sample.stem, 'score', (v_rule ->> 'score')::numeric
    )) from (select * from public.smis_question question where question.tenant_id = v_tenant and question.status = 'enabled'
      and (nullif(v_rule ->> 'category_id', '') is null or question.category_id = (v_rule ->> 'category_id')::uuid)
      and (nullif(v_rule ->> 'question_type', '') is null or question.question_type = v_rule ->> 'question_type')
      order by random() limit (v_rule ->> 'count')::integer) sample), '[]'::jsonb);
  end loop;
  if (select count(*) from jsonb_array_elements(v_result)) <> (select count(distinct item ->> 'questionId') from jsonb_array_elements(v_result) item) then
    raise exception '不同随机规则抽到了重复题目，请细化分类或题型条件';
  end if;
  return v_result;
end;
$function$;

create or replace function public.smis_list_exam_papers_secure(
  p_from integer default 0, p_to integer default 19, p_keyword text default null,
  p_status text default null, p_scope text default 'manage'
)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_employee uuid; v_can_manage boolean; v_from integer := greatest(coalesce(p_from,0),0); v_to integer := greatest(coalesce(p_to,19),greatest(coalesce(p_from,0),0));
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  v_can_manage := app_private.has_permission('SmisExamManagement:View');
  if not v_can_manage and not app_private.has_permission('SmisExamManagement:Take') then raise exception '没有查看考试的权限' using errcode='42501'; end if;
  v_tenant := app_private.current_user_tenant_id(); v_employee := app_private.hr_current_employee_id();
  return (with base as (
    select paper.*, assignment.id assignment_id, assignment.exam_status, assignment.attempt_count, assignment.best_score,
      (select count(*) from public.smis_exam_paper_question pq where pq.paper_id=paper.id and pq.tenant_id=v_tenant) question_count,
      (select count(*) from public.smis_exam_assignment ea where ea.paper_id=paper.id and ea.tenant_id=v_tenant) assignee_count
    from public.smis_exam_paper paper
    left join public.smis_exam_assignment assignment on assignment.paper_id=paper.id and assignment.tenant_id=paper.tenant_id and assignment.employee_id=v_employee
    where paper.tenant_id=v_tenant and (v_can_manage and p_scope='manage' or assignment.id is not null)
  ), filtered as (select * from base where (p_status is null or status=p_status)
    and (nullif(btrim(coalesce(p_keyword,'')),'') is null or paper_no ilike '%'||btrim(p_keyword)||'%' or paper_title ilike '%'||btrim(p_keyword)||'%')),
  page as (select * from filtered order by update_time desc offset v_from limit v_to-v_from+1)
  select jsonb_build_object('records',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'paperNo',paper_no,'paperTitle',paper_title,'assemblyMode',assembly_mode,'randomRule',random_rule,
    'totalScore',total_score,'passingScore',passing_score,'timeLimitMinutes',time_limit_minutes,'allowRetake',allow_retake,
    'maxAttempts',max_attempts,'openAt',open_at,'closeAt',close_at,'status',status,'remark',remark,
    'questionCount',question_count,'assigneeCount',assignee_count,'assignmentId',assignment_id,'examStatus',exam_status,
    'attemptCount',attempt_count,'bestScore',best_score,'createTime',create_time,'updateTime',update_time) order by update_time desc) from page),'[]'::jsonb),
    'total',(select count(*) from filtered),'overview',jsonb_build_object('total',(select count(*) from base),'draft',(select count(*) from base where status='draft'),
      'published',(select count(*) from base where status='published'),'inProgress',(select count(*) from base where exam_status='in_progress'),
      'completed',(select count(*) from base where exam_status in ('passed','failed')))));
end;$function$;

create or replace function public.smis_manage_exam_paper_secure(p_action text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_id uuid; v_ids uuid[]; v_status text; v_questions jsonb; v_employees jsonb; v_total numeric; v_item jsonb; v_sort integer:=0; v_required text;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  v_required := case p_action when 'delete' then 'SmisExamManagement:Delete' when 'publish' then 'SmisExamManagement:Publish' when 'close' then 'SmisExamManagement:Publish'
    else case when nullif(p_payload->>'id','') is null then 'SmisExamManagement:Add' else 'SmisExamManagement:Edit' end end;
  if not app_private.has_permission(v_required) then raise exception '没有执行试卷操作的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  if p_action='delete' then
    select coalesce(array_agg(value::uuid),'{}'::uuid[]) into v_ids from jsonb_array_elements_text(coalesce(p_payload->'ids','[]'::jsonb));
    if exists(select 1 from public.smis_exam_paper where tenant_id=v_tenant and id=any(v_ids) and status<>'draft') then raise exception '只能删除草稿试卷'; end if;
    delete from public.smis_exam_paper where tenant_id=v_tenant and id=any(v_ids); return jsonb_build_object('affected',cardinality(v_ids));
  end if;
  v_id:=nullif(p_payload->>'id','')::uuid;
  if p_action in ('publish','close') then
    v_status:=case when p_action='publish' then 'published' else 'closed' end;
    if p_action='publish' and not exists(select 1 from public.smis_exam_paper_question where paper_id=v_id and tenant_id=v_tenant) then raise exception '发布前至少选择一道题目'; end if;
    update public.smis_exam_paper set status=v_status where id=v_id and tenant_id=v_tenant and (status='draft' or p_action='close');
    if not found then raise exception '试卷状态不允许此操作'; end if; return jsonb_build_object('id',v_id,'status',v_status);
  end if;
  if p_action<>'save' then raise exception '不支持的试卷操作'; end if;
  v_questions:=coalesce(p_payload->'questions','[]'::jsonb); v_employees:=coalesce(p_payload->'employee_ids','[]'::jsonb);
  if btrim(coalesce(p_payload->>'paper_title',''))='' then raise exception '请输入试卷标题'; end if;
  if jsonb_typeof(v_questions)<>'array' or jsonb_array_length(v_questions)=0 then raise exception '至少选择一道题目'; end if;
  if jsonb_typeof(v_employees)<>'array' then raise exception '考试人员数据格式不正确'; end if;
  if jsonb_array_length(v_employees)>0 and not app_private.has_permission('SmisExamManagement:Assign') then raise exception '没有分配考试人员的权限' using errcode='42501'; end if;
  select sum((item->>'score')::numeric) into v_total from jsonb_array_elements(v_questions) item;
  if coalesce(v_total,0)<=0 then raise exception '试卷总分必须大于 0'; end if;
  if coalesce((p_payload->>'passing_score')::numeric,0)<=0 or (p_payload->>'passing_score')::numeric>v_total then raise exception '及格分数必须大于 0 且不超过试卷总分'; end if;
  if v_id is null then
    insert into public.smis_exam_paper(tenant_id,paper_no,paper_title,assembly_mode,random_rule,total_score,passing_score,time_limit_minutes,allow_retake,max_attempts,open_at,close_at,status,remark)
    values(v_tenant,coalesce(nullif(btrim(p_payload->>'paper_no'),''),'SJ'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')),btrim(p_payload->>'paper_title'),
      coalesce(nullif(p_payload->>'assembly_mode',''),'fixed'),coalesce(p_payload->'random_rule','[]'::jsonb),v_total,(p_payload->>'passing_score')::numeric,
      nullif(p_payload->>'time_limit_minutes','')::integer,coalesce((p_payload->>'allow_retake')::boolean,false),greatest(coalesce((p_payload->>'max_attempts')::integer,1),1),
      nullif(p_payload->>'open_at','')::timestamptz,nullif(p_payload->>'close_at','')::timestamptz,'draft',nullif(btrim(p_payload->>'remark'),'')) returning id into v_id;
  else
    update public.smis_exam_paper set paper_no=coalesce(nullif(btrim(p_payload->>'paper_no'),''),paper_no),paper_title=btrim(p_payload->>'paper_title'),
      assembly_mode=coalesce(nullif(p_payload->>'assembly_mode',''),'fixed'),random_rule=coalesce(p_payload->'random_rule','[]'::jsonb),total_score=v_total,
      passing_score=(p_payload->>'passing_score')::numeric,time_limit_minutes=nullif(p_payload->>'time_limit_minutes','')::integer,
      allow_retake=coalesce((p_payload->>'allow_retake')::boolean,false),max_attempts=greatest(coalesce((p_payload->>'max_attempts')::integer,1),1),
      open_at=nullif(p_payload->>'open_at','')::timestamptz,close_at=nullif(p_payload->>'close_at','')::timestamptz,remark=nullif(btrim(p_payload->>'remark'),'')
    where id=v_id and tenant_id=v_tenant and status='draft'; if not found then raise exception '只能编辑草稿试卷'; end if;
    delete from public.smis_exam_paper_question where paper_id=v_id and tenant_id=v_tenant;
  end if;
  for v_item in select value from jsonb_array_elements(v_questions) loop
    v_sort:=v_sort+10;
    insert into public.smis_exam_paper_question(tenant_id,paper_id,question_id,question_snapshot,score,sort)
    select v_tenant,v_id,q.id,jsonb_build_object('categoryId',q.category_id,'questionType',q.question_type,'stem',q.stem,'options',q.options,
      'correctAnswers',to_jsonb(q.correct_answers),'analysis',q.analysis),greatest((v_item->>'score')::numeric,0.01),v_sort
    from public.smis_question q where q.id=(v_item->>'question_id')::uuid and q.tenant_id=v_tenant and q.status='enabled';
    if not found then raise exception '所选题目不存在或已停用'; end if;
  end loop;
  if jsonb_array_length(v_employees)>0 then
    insert into public.smis_exam_assignment(tenant_id,paper_id,employee_id)
    select v_tenant,v_id,value::uuid from jsonb_array_elements_text(v_employees)
    where exists(select 1 from public.hr_employee employee where employee.id=value::uuid and employee.tenant_id=v_tenant)
    on conflict(tenant_id,paper_id,employee_id) do nothing;
  end if;
  return jsonb_build_object('id',v_id,'totalScore',v_total);
end;$function$;

create or replace function public.smis_get_exam_detail_secure(p_paper_id uuid, p_attempt_id uuid default null, p_preview boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_employee uuid; v_manage boolean; v_graded boolean:=false;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  v_manage:=app_private.has_permission('SmisExamManagement:ViewDetail') or (p_preview and app_private.has_permission('SmisExamManagement:Preview'));
  if not v_manage and not app_private.has_permission('SmisExamManagement:Take') then raise exception '没有查看试卷的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id(); v_employee:=app_private.hr_current_employee_id();
  if not v_manage and not exists(select 1 from public.smis_exam_assignment where tenant_id=v_tenant and paper_id=p_paper_id and employee_id=v_employee) then raise exception '考试任务不属于当前员工' using errcode='42501'; end if;
  if p_attempt_id is not null then select attempt_status='graded' into v_graded from public.smis_exam_attempt where id=p_attempt_id and tenant_id=v_tenant and (v_manage or employee_id=v_employee); end if;
  return (select jsonb_build_object('paper',jsonb_build_object('id',paper.id,'paperNo',paper.paper_no,'paperTitle',paper.paper_title,'totalScore',paper.total_score,
    'passingScore',paper.passing_score,'timeLimitMinutes',paper.time_limit_minutes,'allowRetake',paper.allow_retake,'maxAttempts',paper.max_attempts,'openAt',paper.open_at,'closeAt',paper.close_at,'status',paper.status,'remark',paper.remark),
    'attempt',case when attempt.id is null then null else jsonb_build_object('id',attempt.id,'attemptNo',attempt.attempt_no,'attemptStatus',attempt.attempt_status,'startedAt',attempt.started_at,
      'expiresAt',attempt.expires_at,'submittedAt',attempt.submitted_at,'durationSeconds',attempt.duration_seconds,'score',attempt.score,'passed',attempt.passed) end,
    'questions',coalesce((select jsonb_agg(jsonb_build_object('id',pq.question_id,'sort',pq.sort,'score',pq.score,
      'questionType',pq.question_snapshot->>'questionType','stem',pq.question_snapshot->>'stem','options',pq.question_snapshot->'options',
      'correctAnswers',case when v_manage or v_graded then pq.question_snapshot->'correctAnswers' else null end,
      'analysis',case when v_manage or v_graded then pq.question_snapshot->'analysis' else null end,
      'answerValues',coalesce(to_jsonb(answer.answer_values),'[]'::jsonb),'isCorrect',case when v_manage or v_graded then answer.is_correct else null end,
      'awardedScore',case when v_manage or v_graded then answer.awarded_score else null end) order by pq.sort)
      from public.smis_exam_paper_question pq left join public.smis_exam_answer answer on answer.attempt_id=p_attempt_id and answer.question_id=pq.question_id and answer.tenant_id=v_tenant
      where pq.paper_id=paper.id and pq.tenant_id=v_tenant),'[]'::jsonb))
    from public.smis_exam_paper paper left join public.smis_exam_attempt attempt on attempt.id=p_attempt_id and attempt.paper_id=paper.id and attempt.tenant_id=paper.tenant_id
    where paper.id=p_paper_id and paper.tenant_id=v_tenant);
end;$function$;

create or replace function public.smis_start_exam_secure(p_paper_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_employee uuid; v_assignment public.smis_exam_assignment%rowtype; v_paper public.smis_exam_paper%rowtype; v_attempt uuid;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  if not app_private.has_permission('SmisExamManagement:Take') then raise exception '没有参加考试的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id(); v_employee:=app_private.hr_current_employee_id(); if v_employee is null then raise exception '当前账号未关联员工花名册'; end if;
  select * into v_paper from public.smis_exam_paper where id=p_paper_id and tenant_id=v_tenant;
  if v_paper.id is null or v_paper.status<>'published' then raise exception '试卷尚未发布或已关闭'; end if;
  if v_paper.open_at is not null and now()<v_paper.open_at then raise exception '考试尚未开始'; end if;
  if v_paper.close_at is not null and now()>v_paper.close_at then raise exception '考试已经结束'; end if;
  select * into v_assignment from public.smis_exam_assignment where paper_id=p_paper_id and employee_id=v_employee and tenant_id=v_tenant for update;
  if v_assignment.id is null then raise exception '当前员工未被分配此考试'; end if;
  select id into v_attempt from public.smis_exam_attempt where assignment_id=v_assignment.id and tenant_id=v_tenant and attempt_status='in_progress' order by attempt_no desc limit 1;
  if v_attempt is null then
    if v_assignment.attempt_count>=v_paper.max_attempts or (v_assignment.attempt_count>0 and not v_paper.allow_retake) then raise exception '已达到允许考试次数'; end if;
    insert into public.smis_exam_attempt(tenant_id,assignment_id,paper_id,employee_id,attempt_no,question_order,expires_at)
    select v_tenant,v_assignment.id,p_paper_id,v_employee,v_assignment.attempt_count+1,array_agg(question_id order by sort),
      case when v_paper.time_limit_minutes is null then null else now()+make_interval(mins=>v_paper.time_limit_minutes) end
    from public.smis_exam_paper_question where paper_id=p_paper_id and tenant_id=v_tenant returning id into v_attempt;
    update public.smis_exam_assignment set exam_status='in_progress',attempt_count=attempt_count+1,started_at=coalesce(started_at,now()) where id=v_assignment.id and tenant_id=v_tenant;
  end if;
  return public.smis_get_exam_detail_secure(p_paper_id,v_attempt,false);
end;$function$;

create or replace function public.smis_save_exam_answer_secure(p_attempt_id uuid,p_question_id uuid,p_answer_values text[])
returns void language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_employee uuid; v_attempt public.smis_exam_attempt%rowtype;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  if not app_private.has_permission('SmisExamManagement:Take') then raise exception '没有参加考试的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id(); v_employee:=app_private.hr_current_employee_id();
  select * into v_attempt from public.smis_exam_attempt where id=p_attempt_id and tenant_id=v_tenant and employee_id=v_employee for update;
  if v_attempt.id is null or v_attempt.attempt_status<>'in_progress' then raise exception '考试已结束，不能继续作答'; end if;
  if v_attempt.expires_at is not null and now()>v_attempt.expires_at then raise exception '考试时间已到，请提交试卷'; end if;
  if not exists(select 1 from public.smis_exam_paper_question where paper_id=v_attempt.paper_id and question_id=p_question_id and tenant_id=v_tenant) then raise exception '题目不属于当前试卷'; end if;
  insert into public.smis_exam_answer(tenant_id,attempt_id,question_id,answer_values,answered_at)
  values(v_tenant,p_attempt_id,p_question_id,coalesce(p_answer_values,'{}'::text[]),now())
  on conflict(tenant_id,attempt_id,question_id) do update set answer_values=excluded.answer_values,answered_at=now(),is_correct=null,awarded_score=null;
end;$function$;

create or replace function public.smis_submit_exam_secure(p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_employee uuid; v_attempt public.smis_exam_attempt%rowtype; v_paper public.smis_exam_paper%rowtype; v_score numeric; v_passed boolean;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  if not app_private.has_permission('SmisExamManagement:Take') then raise exception '没有参加考试的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id(); v_employee:=app_private.hr_current_employee_id();
  select * into v_attempt from public.smis_exam_attempt where id=p_attempt_id and tenant_id=v_tenant and employee_id=v_employee for update;
  if v_attempt.id is null or v_attempt.attempt_status<>'in_progress' then raise exception '考试已提交或不存在'; end if;
  select * into v_paper from public.smis_exam_paper where id=v_attempt.paper_id and tenant_id=v_tenant;
  insert into public.smis_exam_answer(tenant_id,attempt_id,question_id,answer_values)
  select v_tenant,v_attempt.id,pq.question_id,'{}'::text[] from public.smis_exam_paper_question pq
  where pq.paper_id=v_attempt.paper_id and pq.tenant_id=v_tenant on conflict(tenant_id,attempt_id,question_id) do nothing;
  update public.smis_exam_answer answer set
    is_correct=coalesce((select array_agg(value order by value) from unnest(answer.answer_values) value)=(select array_agg(value order by value) from jsonb_array_elements_text(pq.question_snapshot->'correctAnswers') value),false),
    awarded_score=case when (select array_agg(value order by value) from unnest(answer.answer_values) value)=(select array_agg(value order by value) from jsonb_array_elements_text(pq.question_snapshot->'correctAnswers') value) then pq.score else 0 end
  from public.smis_exam_paper_question pq where answer.attempt_id=v_attempt.id and answer.tenant_id=v_tenant and pq.paper_id=v_attempt.paper_id and pq.question_id=answer.question_id and pq.tenant_id=v_tenant;
  select coalesce(sum(awarded_score),0) into v_score from public.smis_exam_answer where attempt_id=v_attempt.id and tenant_id=v_tenant;
  v_passed:=v_score>=v_paper.passing_score;
  update public.smis_exam_attempt set attempt_status='graded',submitted_at=now(),duration_seconds=greatest(extract(epoch from (now()-started_at))::integer,0),score=v_score,passed=v_passed where id=v_attempt.id and tenant_id=v_tenant;
  update public.smis_exam_assignment set exam_status=case when v_passed then 'passed' else 'failed' end,best_score=greatest(coalesce(best_score,0),v_score),completed_at=now() where id=v_attempt.assignment_id and tenant_id=v_tenant;
  return public.smis_get_exam_detail_secure(v_attempt.paper_id,v_attempt.id,false);
end;$function$;

create or replace function public.smis_list_exam_records_secure(p_from integer default 0,p_to integer default 19,p_keyword text default null,p_status text default null)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_employee uuid; v_manage boolean; v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),greatest(coalesce(p_from,0),0));
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  v_manage:=app_private.has_permission('SmisExamManagement:ViewRecord'); if not v_manage and not app_private.has_permission('SmisExamManagement:Take') then raise exception '没有查看考试记录的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id(); v_employee:=app_private.hr_current_employee_id();
  return(with filtered as(select attempt.id,attempt.paper_id,attempt.employee_id,attempt.attempt_no,attempt.attempt_status,attempt.started_at,attempt.submitted_at,attempt.duration_seconds,attempt.score,attempt.passed,
    paper.paper_no,paper.paper_title,paper.total_score,paper.passing_score,employee.employee_no,employee.employee_name,organization.organization_name,employee.job_title
    from public.smis_exam_attempt attempt join public.smis_exam_paper paper on paper.id=attempt.paper_id and paper.tenant_id=attempt.tenant_id
    join public.hr_employee employee on employee.id=attempt.employee_id and employee.tenant_id=attempt.tenant_id left join public.sys_organization organization on organization.id=employee.organization_id and organization.tenant_id=employee.tenant_id
    where attempt.tenant_id=v_tenant and (v_manage or attempt.employee_id=v_employee) and (p_status is null or (case when attempt.attempt_status='in_progress' then 'in_progress' when attempt.passed then 'passed' else 'failed' end)=p_status)
      and (nullif(btrim(coalesce(p_keyword,'')),'') is null or paper.paper_no ilike '%'||btrim(p_keyword)||'%' or paper.paper_title ilike '%'||btrim(p_keyword)||'%' or employee.employee_name ilike '%'||btrim(p_keyword)||'%')),
  page as(select * from filtered order by started_at desc offset v_from limit v_to-v_from+1)
  select jsonb_build_object('records',coalesce((select jsonb_agg(jsonb_build_object('id',id,'paperId',paper_id,'paperNo',paper_no,'paperTitle',paper_title,'totalScore',total_score,'passingScore',passing_score,
    'employeeId',employee_id,'employeeNo',employee_no,'employeeName',employee_name,'organizationName',organization_name,'jobTitle',job_title,'attemptNo',attempt_no,
    'attemptStatus',attempt_status,'startedAt',started_at,'submittedAt',submitted_at,'durationSeconds',duration_seconds,'score',score,'passed',passed) order by started_at desc) from page),'[]'::jsonb),
    'total',(select count(*) from filtered),'overview',jsonb_build_object('total',(select count(*) from filtered),'inProgress',(select count(*) from filtered where attempt_status='in_progress'),
    'passed',(select count(*) from filtered where passed=true),'failed',(select count(*) from filtered where attempt_status='graded' and passed=false))));
end;$function$;

create or replace function public.smis_list_courses_secure(p_from integer default 0,p_to integer default 19,p_keyword text default null,p_status text default null,p_category text default null,p_scope text default 'manage')
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_employee uuid; v_manage boolean; v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),greatest(coalesce(p_from,0),0));
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  v_manage:=app_private.has_permission('SmisCourseManagement:View'); if not v_manage and not app_private.has_permission('SmisCourseManagement:Learn') then raise exception '没有查看课程的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id(); v_employee:=app_private.hr_current_employee_id();
  return(with base as(select course.*,paper.paper_title,assignment.id assignment_id,assignment.learning_status,assignment.progress_percent,assignment.total_learning_seconds,assignment.started_at,assignment.last_learning_at,assignment.completed_at,
      (select count(*) from public.smis_learning_course_assignment ca where ca.course_id=course.id and ca.tenant_id=v_tenant) learner_count,
      (select count(*) from public.smis_learning_course_assignment ca where ca.course_id=course.id and ca.tenant_id=v_tenant and ca.learning_status='completed') completed_count
    from public.smis_learning_course course left join public.smis_exam_paper paper on paper.id=course.exam_paper_id and paper.tenant_id=course.tenant_id
    left join public.smis_learning_course_assignment assignment on assignment.course_id=course.id and assignment.tenant_id=course.tenant_id and assignment.employee_id=v_employee
    where course.tenant_id=v_tenant and (v_manage and p_scope='manage' or assignment.id is not null)),
  filtered as(select * from base where (p_status is null or status=p_status) and (p_category is null or course_category=p_category)
    and (nullif(btrim(coalesce(p_keyword,'')),'') is null or course_no ilike '%'||btrim(p_keyword)||'%' or course_name ilike '%'||btrim(p_keyword)||'%')),
  page as(select * from filtered order by update_time desc offset v_from limit v_to-v_from+1)
  select jsonb_build_object('records',coalesce((select jsonb_agg(jsonb_build_object('id',id,'courseNo',course_no,'courseName',course_name,'courseCategory',course_category,'courseType',course_type,
    'resourceUrl',resource_url,'coverUrl',cover_url,'introduction',introduction,'minimumLearningMinutes',minimum_learning_minutes,'creditHours',credit_hours,'dueDate',due_date,'examPaperId',exam_paper_id,
    'examPaperTitle',paper_title,'status',status,'learnerCount',learner_count,'completedCount',completed_count,'assignmentId',assignment_id,'learningStatus',learning_status,'progressPercent',progress_percent,
    'totalLearningSeconds',total_learning_seconds,'startedAt',started_at,'lastLearningAt',last_learning_at,'completedAt',completed_at,'createTime',create_time,'updateTime',update_time) order by update_time desc) from page),'[]'::jsonb),
    'total',(select count(*) from filtered),'overview',jsonb_build_object('total',(select count(*) from base),'draft',(select count(*) from base where status='draft'),'published',(select count(*) from base where status='published'),
      'learning',(select count(*) from base where learning_status='in_progress'),'completed',(select count(*) from base where learning_status='completed'))));
end;$function$;

create or replace function public.smis_manage_course_secure(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_id uuid; v_ids uuid[]; v_employees jsonb; v_required text; v_paper uuid;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  v_required:=case p_action when 'delete' then 'SmisCourseManagement:Delete' when 'publish' then 'SmisCourseManagement:Publish' when 'close' then 'SmisCourseManagement:Publish'
    else case when nullif(p_payload->>'id','') is null then 'SmisCourseManagement:Add' else 'SmisCourseManagement:Edit' end end;
  if not app_private.has_permission(v_required) then raise exception '没有执行课程操作的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  if p_action='delete' then select coalesce(array_agg(value::uuid),'{}'::uuid[]) into v_ids from jsonb_array_elements_text(coalesce(p_payload->'ids','[]'::jsonb));
    if exists(select 1 from public.smis_learning_course where tenant_id=v_tenant and id=any(v_ids) and status<>'draft') then raise exception '只能删除草稿课程'; end if;
    delete from public.smis_learning_course where tenant_id=v_tenant and id=any(v_ids); return jsonb_build_object('affected',cardinality(v_ids)); end if;
  v_id:=nullif(p_payload->>'id','')::uuid;
  if p_action in ('publish','close') then
    if p_action='publish' and exists(select 1 from public.smis_learning_course where id=v_id and tenant_id=v_tenant and (resource_url is null or btrim(resource_url)='')) then raise exception '发布前请配置课程资源'; end if;
    update public.smis_learning_course set status=case when p_action='publish' then 'published' else 'closed' end where id=v_id and tenant_id=v_tenant and (status='draft' or p_action='close');
    if not found then raise exception '课程状态不允许此操作'; end if; return jsonb_build_object('id',v_id); end if;
  if p_action<>'save' then raise exception '不支持的课程操作'; end if;
  if btrim(coalesce(p_payload->>'course_name',''))='' then raise exception '请输入课程名称'; end if;
  if p_payload->>'course_type' not in ('video','pdf','link') then raise exception '请选择课程类型'; end if;
  v_employees:=coalesce(p_payload->'employee_ids','[]'::jsonb); if jsonb_typeof(v_employees)<>'array' then raise exception '学习人员数据格式不正确'; end if;
  if jsonb_array_length(v_employees)>0 and not app_private.has_permission('SmisCourseManagement:Assign') then raise exception '没有分配学习人员的权限' using errcode='42501'; end if;
  v_paper:=nullif(p_payload->>'exam_paper_id','')::uuid;
  if v_paper is not null and not exists(select 1 from public.smis_exam_paper where id=v_paper and tenant_id=v_tenant and status in ('draft','published')) then raise exception '关联试卷不存在'; end if;
  if v_id is null then insert into public.smis_learning_course(tenant_id,course_no,course_name,course_category,course_type,resource_url,cover_url,introduction,minimum_learning_minutes,credit_hours,due_date,exam_paper_id,status)
    values(v_tenant,coalesce(nullif(btrim(p_payload->>'course_no'),''),'KC'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')),btrim(p_payload->>'course_name'),p_payload->>'course_category',p_payload->>'course_type',
      nullif(btrim(p_payload->>'resource_url'),''),nullif(btrim(p_payload->>'cover_url'),''),nullif(btrim(p_payload->>'introduction'),''),greatest(coalesce((p_payload->>'minimum_learning_minutes')::integer,0),0),
      greatest(coalesce((p_payload->>'credit_hours')::numeric,0),0),nullif(p_payload->>'due_date','')::date,v_paper,'draft') returning id into v_id;
  else update public.smis_learning_course set course_no=coalesce(nullif(btrim(p_payload->>'course_no'),''),course_no),course_name=btrim(p_payload->>'course_name'),course_category=p_payload->>'course_category',
      course_type=p_payload->>'course_type',resource_url=nullif(btrim(p_payload->>'resource_url'),''),cover_url=nullif(btrim(p_payload->>'cover_url'),''),introduction=nullif(btrim(p_payload->>'introduction'),''),
      minimum_learning_minutes=greatest(coalesce((p_payload->>'minimum_learning_minutes')::integer,0),0),credit_hours=greatest(coalesce((p_payload->>'credit_hours')::numeric,0),0),due_date=nullif(p_payload->>'due_date','')::date,exam_paper_id=v_paper
    where id=v_id and tenant_id=v_tenant and status='draft'; if not found then raise exception '只能编辑草稿课程'; end if; end if;
  if jsonb_array_length(v_employees)>0 then
    insert into public.smis_learning_course_assignment(tenant_id,course_id,employee_id) select v_tenant,v_id,value::uuid from jsonb_array_elements_text(v_employees)
    where exists(select 1 from public.hr_employee employee where employee.id=value::uuid and employee.tenant_id=v_tenant) on conflict(tenant_id,course_id,employee_id) do nothing;
    if v_paper is not null then insert into public.smis_exam_assignment(tenant_id,paper_id,employee_id,course_assignment_id)
      select v_tenant,v_paper,ca.employee_id,ca.id from public.smis_learning_course_assignment ca where ca.course_id=v_id and ca.tenant_id=v_tenant and ca.employee_id in(select value::uuid from jsonb_array_elements_text(v_employees))
      on conflict(tenant_id,paper_id,employee_id) do update set course_assignment_id=excluded.course_assignment_id; end if;
  end if;
  return jsonb_build_object('id',v_id);
end;$function$;

create or replace function public.smis_list_course_learning_records_secure(p_from integer default 0,p_to integer default 19,p_keyword text default null,p_status text default null)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_employee uuid; v_manage boolean; v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),greatest(coalesce(p_from,0),0));
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  v_manage:=app_private.has_permission('SmisCourseManagement:ViewLearningRecord'); if not v_manage and not app_private.has_permission('SmisCourseManagement:Learn') then raise exception '没有查看学习记录的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id(); v_employee:=app_private.hr_current_employee_id();
  return(with filtered as(select assignment.id,assignment.course_id,assignment.employee_id,assignment.learning_status,assignment.progress_percent,assignment.total_learning_seconds,assignment.started_at,assignment.last_learning_at,assignment.completed_at,
      course.course_no,course.course_name,course.minimum_learning_minutes,course.due_date,employee.employee_no,employee.employee_name,organization.organization_name,employee.job_title
    from public.smis_learning_course_assignment assignment join public.smis_learning_course course on course.id=assignment.course_id and course.tenant_id=assignment.tenant_id
    join public.hr_employee employee on employee.id=assignment.employee_id and employee.tenant_id=assignment.tenant_id left join public.sys_organization organization on organization.id=employee.organization_id and organization.tenant_id=employee.tenant_id
    where assignment.tenant_id=v_tenant and (v_manage or assignment.employee_id=v_employee) and (p_status is null or assignment.learning_status=p_status)
      and (nullif(btrim(coalesce(p_keyword,'')),'') is null or course.course_no ilike '%'||btrim(p_keyword)||'%' or course.course_name ilike '%'||btrim(p_keyword)||'%' or employee.employee_name ilike '%'||btrim(p_keyword)||'%')),
  page as(select * from filtered order by coalesce(last_learning_at,started_at) desc nulls last offset v_from limit v_to-v_from+1)
  select jsonb_build_object('records',coalesce((select jsonb_agg(jsonb_build_object(
    'id',item.id,'courseId',item.course_id,'courseNo',item.course_no,'courseName',item.course_name,
    'minimumLearningMinutes',item.minimum_learning_minutes,'dueDate',item.due_date,
    'employeeId',item.employee_id,'employeeNo',item.employee_no,'employeeName',item.employee_name,
    'organizationName',item.organization_name,'jobTitle',item.job_title,'learningStatus',item.learning_status,
    'progressPercent',item.progress_percent,'totalLearningSeconds',item.total_learning_seconds,
    'startedAt',item.started_at,'lastLearningAt',item.last_learning_at,'completedAt',item.completed_at
  ) order by coalesce(last_learning_at,started_at) desc nulls last) from page item),'[]'::jsonb),'total',(select count(*) from filtered),
    'overview',jsonb_build_object('total',(select count(*) from filtered),'assigned',(select count(*) from filtered where learning_status='assigned'),'inProgress',(select count(*) from filtered where learning_status='in_progress'),'completed',(select count(*) from filtered where learning_status='completed'))));
end;$function$;

create or replace function public.smis_update_course_learning_secure(p_assignment_id uuid,p_progress_percent numeric,p_elapsed_seconds integer default 0,p_complete boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_tenant uuid; v_employee uuid; v_assignment public.smis_learning_course_assignment%rowtype; v_course public.smis_learning_course%rowtype; v_progress numeric;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode='42501'; end if;
  if not app_private.has_permission('SmisCourseManagement:Learn') then raise exception '没有学习课程的权限' using errcode='42501'; end if;
  v_tenant:=app_private.current_user_tenant_id(); v_employee:=app_private.hr_current_employee_id();
  select * into v_assignment from public.smis_learning_course_assignment where id=p_assignment_id and tenant_id=v_tenant and employee_id=v_employee for update;
  if v_assignment.id is null then raise exception '学习任务不属于当前员工'; end if;
  select * into v_course from public.smis_learning_course where id=v_assignment.course_id and tenant_id=v_tenant;
  if v_course.status<>'published' then raise exception '课程尚未发布或已关闭'; end if;
  v_progress:=least(greatest(coalesce(p_progress_percent,v_assignment.progress_percent),v_assignment.progress_percent),100);
  if p_complete and v_assignment.total_learning_seconds+greatest(coalesce(p_elapsed_seconds,0),0)<v_course.minimum_learning_minutes*60 then raise exception '尚未达到课程最低学习时长'; end if;
  update public.smis_learning_course_assignment set progress_percent=case when p_complete then 100 else v_progress end,total_learning_seconds=total_learning_seconds+greatest(coalesce(p_elapsed_seconds,0),0),
    learning_status=case when p_complete then 'completed' when learning_status='assigned' then 'in_progress' else learning_status end,started_at=coalesce(started_at,now()),last_learning_at=now(),completed_at=case when p_complete then now() else completed_at end
  where id=p_assignment_id and tenant_id=v_tenant returning * into v_assignment;
  return jsonb_build_object('id',v_assignment.id,'learningStatus',v_assignment.learning_status,'progressPercent',v_assignment.progress_percent,'totalLearningSeconds',v_assignment.total_learning_seconds,'completedAt',v_assignment.completed_at);
end;$function$;

do $$
declare v_signature text;
begin
  foreach v_signature in array array[
    'public.smis_list_question_bank_secure(integer,integer,text,uuid,text,text)',
    'public.smis_manage_question_category_secure(text,jsonb)',
    'public.smis_manage_question_secure(text,jsonb)',
    'public.smis_generate_exam_questions_secure(jsonb)',
    'public.smis_list_exam_papers_secure(integer,integer,text,text,text)',
    'public.smis_manage_exam_paper_secure(text,jsonb)',
    'public.smis_get_exam_detail_secure(uuid,uuid,boolean)',
    'public.smis_start_exam_secure(uuid)',
    'public.smis_save_exam_answer_secure(uuid,uuid,text[])',
    'public.smis_submit_exam_secure(uuid)',
    'public.smis_list_exam_records_secure(integer,integer,text,text)',
    'public.smis_list_courses_secure(integer,integer,text,text,text,text)',
    'public.smis_manage_course_secure(text,jsonb)',
    'public.smis_list_course_learning_records_secure(integer,integer,text,text)',
    'public.smis_update_course_learning_secure(uuid,numeric,integer,boolean)'
  ] loop
    execute format('revoke all on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated', v_signature);
  end loop;
end $$;

commit;

;
