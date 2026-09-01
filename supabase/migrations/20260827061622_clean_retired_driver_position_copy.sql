update public.hr_position
set
  description = '司机任职岗位；司机运营资料在司机管理中独立维护。',
  update_time = now(),
  update_by = '624944977@qq.com'
where description ilike '%同步创建司机档案%'
   or description ilike '%触发司机档案联动%';

;
