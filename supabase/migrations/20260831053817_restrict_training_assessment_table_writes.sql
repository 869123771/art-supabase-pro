begin;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_question_category',
    'smis_question',
    'smis_exam_paper',
    'smis_exam_paper_question',
    'smis_learning_course',
    'smis_learning_course_assignment',
    'smis_exam_assignment',
    'smis_exam_attempt',
    'smis_exam_answer'
  ] loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on table public.%I from authenticated',
      v_table
    );
    execute format('grant select on table public.%I to authenticated', v_table);
  end loop;
end $$;

comment on schema public is
  '业务表默认只向 authenticated 开放 RLS 保护的读取；课程、题库、试卷和考试写入必须经过安全 RPC。';

commit;

;
