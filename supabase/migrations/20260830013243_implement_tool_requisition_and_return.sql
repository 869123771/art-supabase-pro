-- 工器具个人领用、发放及自动确认基于已验证的同类业务契约建立独立数据边界。
-- 表结构与 RPC 均为独立对象；只复用组织、员工、岗位、物料和仓库主数据。

create table if not exists public.smis_tool_issuance_record (
  "id" uuid default gen_random_uuid() not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "issuance_no" text not null,
  "employee_id" uuid not null,
  "employee_no_snapshot" text not null,
  "employee_name_snapshot" text not null,
  "position_name_snapshot" text,
  "organization_id" uuid,
  "organization_name_snapshot" text,
  "warehouse_id" uuid not null,
  "warehouse_name_snapshot" text not null,
  "issuer_employee_id" uuid not null,
  "issuer_name_snapshot" text not null,
  "issue_date" date not null,
  "status" text default 'draft'::text not null,
  "posted_at" timestamp with time zone,
  "remark" text,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  "update_by" text,
  "update_time" timestamp with time zone default now() not null,
  constraint "smis_tool_issuance_record_remark_check" CHECK (((remark IS NULL) OR (char_length(remark) <= 1000))),
  constraint "smis_tool_issuance_record_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'posted'::text, 'voided'::text]))),
  constraint "smis_tool_issuance_record_pkey" PRIMARY KEY (id),
  constraint "smis_tool_issuance_id_tenant_unique" UNIQUE (id, tenant_id),
  constraint "smis_tool_issuance_no_unique" UNIQUE (tenant_id, issuance_no)
);

create table if not exists public.smis_tool_issuance_record_item (
  "id" uuid default gen_random_uuid() not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "issuance_record_id" uuid not null,
  "requisition_item_id" uuid,
  "material_id" uuid not null,
  "material_category_snapshot" text,
  "material_name_snapshot" text not null,
  "specification_model_snapshot" text,
  "unit_snapshot" text not null,
  "issue_quantity" numeric(12,3) not null,
  "remark" text,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  "update_by" text,
  "update_time" timestamp with time zone default now() not null,
  constraint "smis_tool_issuance_record_item_issue_quantity_check" CHECK ((issue_quantity > (0)::numeric)),
  constraint "smis_tool_issuance_record_item_remark_check" CHECK (((remark IS NULL) OR (char_length(remark) <= 500))),
  constraint "smis_tool_issuance_record_item_pkey" PRIMARY KEY (id),
  constraint "smis_tool_issuance_item_requisition_unique" UNIQUE (requisition_item_id)
);

create table if not exists public.smis_tool_issuance_standard (
  "id" uuid default gen_random_uuid() not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "standard_no" text not null,
  "standard_name" text not null,
  "rated_quantity" numeric(12,3) default 1 not null,
  "issuance_cycle" text not null,
  "issuance_frequency" integer default 1 not null,
  "status" text default 'enabled'::text not null,
  "description" text,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  "update_by" text,
  "update_time" timestamp with time zone default now() not null,
  constraint "smis_tool_issuance_standard_cycle_check" CHECK ((issuance_cycle = ANY (ARRAY['day'::text, 'week'::text, 'month'::text, 'half_year'::text, 'quarter'::text, 'year'::text]))),
  constraint "smis_tool_issuance_standard_description_check" CHECK (((description IS NULL) OR (char_length(description) <= 1000))),
  constraint "smis_tool_issuance_standard_frequency_check" CHECK (((issuance_frequency >= 1) AND (issuance_frequency <= 9999))),
  constraint "smis_tool_issuance_standard_name_check" CHECK (((btrim(standard_name) <> ''::text) AND (char_length(standard_name) <= 120))),
  constraint "smis_tool_issuance_standard_no_check" CHECK (((btrim(standard_no) <> ''::text) AND (char_length(standard_no) <= 60))),
  constraint "smis_tool_issuance_standard_quantity_check" CHECK ((rated_quantity > (0)::numeric)),
  constraint "smis_tool_issuance_standard_status_check" CHECK ((status = ANY (ARRAY['enabled'::text, 'disabled'::text]))),
  constraint "smis_tool_issuance_standard_pkey" PRIMARY KEY (id),
  constraint "smis_tool_issuance_standard_id_tenant_unique" UNIQUE (id, tenant_id)
);

create table if not exists public.smis_tool_issuance_standard_detail (
  "id" uuid default gen_random_uuid() not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "standard_id" uuid not null,
  "material_id" uuid not null,
  "quota_quantity" numeric(12,3) not null,
  "issuance_cycle" text not null,
  "issuance_frequency" integer default 1 not null,
  "status" text default 'enabled'::text not null,
  "remark" text,
  "sort" integer default 10 not null,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  "update_by" text,
  "update_time" timestamp with time zone default now() not null,
  constraint "smis_tool_standard_detail_cycle_check" CHECK ((issuance_cycle = ANY (ARRAY['day'::text, 'week'::text, 'month'::text, 'half_year'::text, 'quarter'::text, 'year'::text]))),
  constraint "smis_tool_standard_detail_frequency_check" CHECK (((issuance_frequency >= 1) AND (issuance_frequency <= 9999))),
  constraint "smis_tool_standard_detail_quantity_check" CHECK ((quota_quantity > (0)::numeric)),
  constraint "smis_tool_standard_detail_remark_check" CHECK (((remark IS NULL) OR (char_length(remark) <= 500))),
  constraint "smis_tool_standard_detail_status_check" CHECK ((status = ANY (ARRAY['enabled'::text, 'disabled'::text]))),
  constraint "smis_tool_issuance_standard_detail_pkey" PRIMARY KEY (id),
  constraint "smis_tool_standard_detail_unique" UNIQUE (standard_id, material_id)
);

create table if not exists public.smis_tool_issuance_standard_organization (
  "standard_id" uuid not null,
  "organization_id" uuid not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  constraint "smis_tool_issuance_standard_organization_pkey" PRIMARY KEY (standard_id, organization_id)
);

create table if not exists public.smis_tool_issuance_standard_position (
  "standard_id" uuid not null,
  "position_id" uuid not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  constraint "smis_tool_issuance_standard_position_pkey" PRIMARY KEY (standard_id, position_id)
);

create table if not exists public.smis_tool_personal_requisition (
  "id" uuid default gen_random_uuid() not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "requisition_no" text not null,
  "employee_id" uuid not null,
  "employee_no_snapshot" text not null,
  "employee_name_snapshot" text not null,
  "position_id" uuid,
  "position_name_snapshot" text,
  "organization_id" uuid,
  "organization_name_snapshot" text,
  "operation_department_snapshot" text,
  "operation_area_snapshot" text,
  "team_snapshot" text,
  "planned_issue_date" date not null,
  "status" text default 'pending_issue'::text not null,
  "source" text default 'standard'::text not null,
  "reminder" text,
  "remark" text,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  "update_by" text,
  "update_time" timestamp with time zone default now() not null,
  constraint "smis_tool_personal_requisition_source_check" CHECK ((source = ANY (ARRAY['standard'::text, 'manual'::text, 'import'::text]))),
  constraint "smis_tool_personal_requisition_status_check" CHECK ((status = ANY (ARRAY['pending_issue'::text, 'partial'::text, 'issued_pending_confirmation'::text, 'confirmed'::text, 'denied'::text, 'cancelled'::text]))),
  constraint "smis_tool_personal_requisition_pkey" PRIMARY KEY (id),
  constraint "smis_tool_requisition_employee_due_unique" UNIQUE (tenant_id, employee_id, planned_issue_date),
  constraint "smis_tool_requisition_id_tenant_unique" UNIQUE (id, tenant_id),
  constraint "smis_tool_requisition_no_unique" UNIQUE (tenant_id, requisition_no)
);

create table if not exists public.smis_tool_personal_requisition_item (
  "id" uuid default gen_random_uuid() not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "requisition_id" uuid not null,
  "personal_standard_item_id" uuid,
  "material_id" uuid not null,
  "material_category_snapshot" text,
  "material_name_snapshot" text not null,
  "specification_model_snapshot" text,
  "unit_snapshot" text not null,
  "image_urls" jsonb default '[]'::jsonb not null,
  "quota_quantity" numeric(12,3) not null,
  "requested_quantity" numeric(12,3) not null,
  "quota_cycle_months" integer not null,
  "status" text default 'pending_issue'::text not null,
  "issued_at" timestamp with time zone,
  "confirmed_at" timestamp with time zone,
  "confirmation_source" text,
  "denial_reason" text,
  "remark" text,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  "update_by" text,
  "update_time" timestamp with time zone default now() not null,
  constraint "smis_tool_personal_requisition_item_confirmation_source_check" CHECK (((confirmation_source IS NULL) OR (confirmation_source = ANY (ARRAY['employee'::text, 'system'::text])))),
  constraint "smis_tool_personal_requisition_item_denial_reason_check" CHECK (((denial_reason IS NULL) OR (char_length(denial_reason) <= 500))),
  constraint "smis_tool_personal_requisition_item_image_urls_check" CHECK ((jsonb_typeof(image_urls) = 'array'::text)),
  constraint "smis_tool_personal_requisition_item_quota_cycle_months_check" CHECK (((quota_cycle_months >= 1) AND (quota_cycle_months <= 1200))),
  constraint "smis_tool_personal_requisition_item_quota_quantity_check" CHECK ((quota_quantity > (0)::numeric)),
  constraint "smis_tool_personal_requisition_item_remark_check" CHECK (((remark IS NULL) OR (char_length(remark) <= 500))),
  constraint "smis_tool_personal_requisition_item_requested_quantity_check" CHECK ((requested_quantity > (0)::numeric)),
  constraint "smis_tool_personal_requisition_item_status_check" CHECK ((status = ANY (ARRAY['pending_issue'::text, 'issued_pending_confirmation'::text, 'confirmed'::text, 'denied'::text, 'cancelled'::text]))),
  constraint "smis_tool_personal_requisition_item_pkey" PRIMARY KEY (id),
  constraint "smis_tool_requisition_item_source_unique" UNIQUE (requisition_id, personal_standard_item_id)
);

create table if not exists public.smis_tool_personal_standard (
  "id" uuid default gen_random_uuid() not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "employee_id" uuid not null,
  "organization_id" uuid,
  "position_id" uuid,
  "generated_at" timestamp with time zone default now() not null,
  "status" text default 'enabled'::text not null,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  "update_by" text,
  "update_time" timestamp with time zone default now() not null,
  constraint "smis_tool_personal_status_check" CHECK ((status = ANY (ARRAY['enabled'::text, 'disabled'::text]))),
  constraint "smis_tool_personal_standard_pkey" PRIMARY KEY (id),
  constraint "smis_tool_personal_id_tenant_unique" UNIQUE (id, tenant_id),
  constraint "smis_tool_personal_tenant_employee_unique" UNIQUE (tenant_id, employee_id)
);

create table if not exists public.smis_tool_personal_standard_item (
  "id" uuid default gen_random_uuid() not null,
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "personal_standard_id" uuid not null,
  "source_standard_id" uuid not null,
  "source_detail_id" uuid not null,
  "material_id" uuid not null,
  "quota_quantity" numeric(12,3) not null,
  "issuance_cycle" text not null,
  "issuance_frequency" integer not null,
  "status" text default 'enabled'::text not null,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  "update_by" text,
  "update_time" timestamp with time zone default now() not null,
  "initial_issue_date" date,
  "last_issue_date" date,
  "next_issue_date" date,
  constraint "smis_tool_personal_item_cycle_check" CHECK ((issuance_cycle = ANY (ARRAY['day'::text, 'week'::text, 'month'::text, 'half_year'::text, 'quarter'::text, 'year'::text]))),
  constraint "smis_tool_personal_item_frequency_check" CHECK (((issuance_frequency >= 1) AND (issuance_frequency <= 9999))),
  constraint "smis_tool_personal_item_quantity_check" CHECK ((quota_quantity > (0)::numeric)),
  constraint "smis_tool_personal_item_status_check" CHECK ((status = ANY (ARRAY['enabled'::text, 'disabled'::text]))),
  constraint "smis_tool_personal_standard_item_pkey" PRIMARY KEY (id),
  constraint "smis_tool_personal_item_source_unique" UNIQUE (personal_standard_id, source_detail_id)
);

create table if not exists public.smis_tool_setting (
  "tenant_id" uuid default app_private.current_user_tenant_id() not null,
  "auto_confirm_days" integer default 3 not null,
  "create_by" text,
  "create_time" timestamp with time zone default now() not null,
  "update_by" text,
  "update_time" timestamp with time zone default now() not null,
  constraint "smis_tool_setting_auto_confirm_days_check" CHECK (((auto_confirm_days >= 1) AND (auto_confirm_days <= 30))),
  constraint "smis_tool_setting_pkey" PRIMARY KEY (tenant_id)
);

alter table public.smis_tool_issuance_record drop constraint if exists "smis_tool_issuance_record_employee_id_fkey";
alter table public.smis_tool_issuance_record add constraint "smis_tool_issuance_record_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES hr_employee(id) ON DELETE RESTRICT;
alter table public.smis_tool_issuance_record drop constraint if exists "smis_tool_issuance_record_issuer_employee_id_fkey";
alter table public.smis_tool_issuance_record add constraint "smis_tool_issuance_record_issuer_employee_id_fkey" FOREIGN KEY (issuer_employee_id) REFERENCES hr_employee(id) ON DELETE RESTRICT;
alter table public.smis_tool_issuance_record drop constraint if exists "smis_tool_issuance_record_organization_id_fkey";
alter table public.smis_tool_issuance_record add constraint "smis_tool_issuance_record_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES sys_organization(id) ON DELETE SET NULL;
alter table public.smis_tool_issuance_record drop constraint if exists "smis_tool_issuance_record_tenant_id_fkey";
alter table public.smis_tool_issuance_record add constraint "smis_tool_issuance_record_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES sys_tenant(id);
alter table public.smis_tool_issuance_record drop constraint if exists "smis_tool_issuance_record_warehouse_id_fkey";
alter table public.smis_tool_issuance_record add constraint "smis_tool_issuance_record_warehouse_id_fkey" FOREIGN KEY (warehouse_id) REFERENCES smis_storage_location(id) ON DELETE RESTRICT;
alter table public.smis_tool_issuance_record_item drop constraint if exists "smis_tool_issuance_item_parent_fkey";
alter table public.smis_tool_issuance_record_item add constraint "smis_tool_issuance_item_parent_fkey" FOREIGN KEY (issuance_record_id, tenant_id) REFERENCES smis_tool_issuance_record(id, tenant_id) ON DELETE CASCADE;
alter table public.smis_tool_issuance_record_item drop constraint if exists "smis_tool_issuance_record_item_material_id_fkey";
alter table public.smis_tool_issuance_record_item add constraint "smis_tool_issuance_record_item_material_id_fkey" FOREIGN KEY (material_id) REFERENCES smis_material(id) ON DELETE RESTRICT;
alter table public.smis_tool_issuance_record_item drop constraint if exists "smis_tool_issuance_record_item_requisition_item_id_fkey";
alter table public.smis_tool_issuance_record_item add constraint "smis_tool_issuance_record_item_requisition_item_id_fkey" FOREIGN KEY (requisition_item_id) REFERENCES smis_tool_personal_requisition_item(id) ON DELETE RESTRICT;
alter table public.smis_tool_issuance_record_item drop constraint if exists "smis_tool_issuance_record_item_tenant_id_fkey";
alter table public.smis_tool_issuance_record_item add constraint "smis_tool_issuance_record_item_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES sys_tenant(id);
alter table public.smis_tool_issuance_standard drop constraint if exists "smis_tool_issuance_standard_tenant_fkey";
alter table public.smis_tool_issuance_standard add constraint "smis_tool_issuance_standard_tenant_fkey" FOREIGN KEY (tenant_id) REFERENCES sys_tenant(id);
alter table public.smis_tool_issuance_standard_detail drop constraint if exists "smis_tool_standard_detail_material_fkey";
alter table public.smis_tool_issuance_standard_detail add constraint "smis_tool_standard_detail_material_fkey" FOREIGN KEY (material_id) REFERENCES smis_material(id) ON DELETE RESTRICT;
alter table public.smis_tool_issuance_standard_detail drop constraint if exists "smis_tool_standard_detail_standard_fkey";
alter table public.smis_tool_issuance_standard_detail add constraint "smis_tool_standard_detail_standard_fkey" FOREIGN KEY (standard_id, tenant_id) REFERENCES smis_tool_issuance_standard(id, tenant_id) ON DELETE CASCADE;
alter table public.smis_tool_issuance_standard_detail drop constraint if exists "smis_tool_standard_detail_tenant_fkey";
alter table public.smis_tool_issuance_standard_detail add constraint "smis_tool_standard_detail_tenant_fkey" FOREIGN KEY (tenant_id) REFERENCES sys_tenant(id);
alter table public.smis_tool_issuance_standard_organization drop constraint if exists "smis_tool_standard_org_org_fkey";
alter table public.smis_tool_issuance_standard_organization add constraint "smis_tool_standard_org_org_fkey" FOREIGN KEY (organization_id) REFERENCES sys_organization(id) ON DELETE RESTRICT;
alter table public.smis_tool_issuance_standard_organization drop constraint if exists "smis_tool_standard_org_standard_fkey";
alter table public.smis_tool_issuance_standard_organization add constraint "smis_tool_standard_org_standard_fkey" FOREIGN KEY (standard_id, tenant_id) REFERENCES smis_tool_issuance_standard(id, tenant_id) ON DELETE CASCADE;
alter table public.smis_tool_issuance_standard_position drop constraint if exists "smis_tool_standard_position_position_fkey";
alter table public.smis_tool_issuance_standard_position add constraint "smis_tool_standard_position_position_fkey" FOREIGN KEY (position_id) REFERENCES hr_position(id) ON DELETE RESTRICT;
alter table public.smis_tool_issuance_standard_position drop constraint if exists "smis_tool_standard_position_standard_fkey";
alter table public.smis_tool_issuance_standard_position add constraint "smis_tool_standard_position_standard_fkey" FOREIGN KEY (standard_id, tenant_id) REFERENCES smis_tool_issuance_standard(id, tenant_id) ON DELETE CASCADE;
alter table public.smis_tool_personal_requisition drop constraint if exists "smis_tool_personal_requisition_employee_id_fkey";
alter table public.smis_tool_personal_requisition add constraint "smis_tool_personal_requisition_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES hr_employee(id) ON DELETE RESTRICT;
alter table public.smis_tool_personal_requisition drop constraint if exists "smis_tool_personal_requisition_organization_id_fkey";
alter table public.smis_tool_personal_requisition add constraint "smis_tool_personal_requisition_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES sys_organization(id) ON DELETE SET NULL;
alter table public.smis_tool_personal_requisition drop constraint if exists "smis_tool_personal_requisition_position_id_fkey";
alter table public.smis_tool_personal_requisition add constraint "smis_tool_personal_requisition_position_id_fkey" FOREIGN KEY (position_id) REFERENCES hr_position(id) ON DELETE SET NULL;
alter table public.smis_tool_personal_requisition drop constraint if exists "smis_tool_personal_requisition_tenant_id_fkey";
alter table public.smis_tool_personal_requisition add constraint "smis_tool_personal_requisition_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES sys_tenant(id);
alter table public.smis_tool_personal_requisition_item drop constraint if exists "smis_tool_personal_requisition_it_personal_standard_item_id_fkey";
alter table public.smis_tool_personal_requisition_item add constraint "smis_tool_personal_requisition_it_personal_standard_item_id_fkey" FOREIGN KEY (personal_standard_item_id) REFERENCES smis_tool_personal_standard_item(id) ON DELETE SET NULL;
alter table public.smis_tool_personal_requisition_item drop constraint if exists "smis_tool_personal_requisition_item_material_id_fkey";
alter table public.smis_tool_personal_requisition_item add constraint "smis_tool_personal_requisition_item_material_id_fkey" FOREIGN KEY (material_id) REFERENCES smis_material(id) ON DELETE RESTRICT;
alter table public.smis_tool_personal_requisition_item drop constraint if exists "smis_tool_personal_requisition_item_tenant_id_fkey";
alter table public.smis_tool_personal_requisition_item add constraint "smis_tool_personal_requisition_item_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES sys_tenant(id);
alter table public.smis_tool_personal_requisition_item drop constraint if exists "smis_tool_requisition_item_parent_fkey";
alter table public.smis_tool_personal_requisition_item add constraint "smis_tool_requisition_item_parent_fkey" FOREIGN KEY (requisition_id, tenant_id) REFERENCES smis_tool_personal_requisition(id, tenant_id) ON DELETE CASCADE;
alter table public.smis_tool_personal_standard drop constraint if exists "smis_tool_personal_employee_fkey";
alter table public.smis_tool_personal_standard add constraint "smis_tool_personal_employee_fkey" FOREIGN KEY (employee_id) REFERENCES hr_employee(id) ON DELETE CASCADE;
alter table public.smis_tool_personal_standard drop constraint if exists "smis_tool_personal_org_fkey";
alter table public.smis_tool_personal_standard add constraint "smis_tool_personal_org_fkey" FOREIGN KEY (organization_id) REFERENCES sys_organization(id) ON DELETE SET NULL;
alter table public.smis_tool_personal_standard drop constraint if exists "smis_tool_personal_position_fkey";
alter table public.smis_tool_personal_standard add constraint "smis_tool_personal_position_fkey" FOREIGN KEY (position_id) REFERENCES hr_position(id) ON DELETE SET NULL;
alter table public.smis_tool_personal_standard drop constraint if exists "smis_tool_personal_tenant_fkey";
alter table public.smis_tool_personal_standard add constraint "smis_tool_personal_tenant_fkey" FOREIGN KEY (tenant_id) REFERENCES sys_tenant(id);
alter table public.smis_tool_personal_standard_item drop constraint if exists "smis_tool_personal_item_detail_fkey";
alter table public.smis_tool_personal_standard_item add constraint "smis_tool_personal_item_detail_fkey" FOREIGN KEY (source_detail_id) REFERENCES smis_tool_issuance_standard_detail(id) ON DELETE RESTRICT;
alter table public.smis_tool_personal_standard_item drop constraint if exists "smis_tool_personal_item_material_fkey";
alter table public.smis_tool_personal_standard_item add constraint "smis_tool_personal_item_material_fkey" FOREIGN KEY (material_id) REFERENCES smis_material(id) ON DELETE RESTRICT;
alter table public.smis_tool_personal_standard_item drop constraint if exists "smis_tool_personal_item_personal_fkey";
alter table public.smis_tool_personal_standard_item add constraint "smis_tool_personal_item_personal_fkey" FOREIGN KEY (personal_standard_id, tenant_id) REFERENCES smis_tool_personal_standard(id, tenant_id) ON DELETE CASCADE;
alter table public.smis_tool_personal_standard_item drop constraint if exists "smis_tool_personal_item_standard_fkey";
alter table public.smis_tool_personal_standard_item add constraint "smis_tool_personal_item_standard_fkey" FOREIGN KEY (source_standard_id, tenant_id) REFERENCES smis_tool_issuance_standard(id, tenant_id) ON DELETE RESTRICT;
alter table public.smis_tool_personal_standard_item drop constraint if exists "smis_tool_personal_item_tenant_fkey";
alter table public.smis_tool_personal_standard_item add constraint "smis_tool_personal_item_tenant_fkey" FOREIGN KEY (tenant_id) REFERENCES sys_tenant(id);
alter table public.smis_tool_setting drop constraint if exists "smis_tool_setting_tenant_id_fkey";
alter table public.smis_tool_setting add constraint "smis_tool_setting_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES sys_tenant(id) ON DELETE CASCADE;

create index if not exists smis_tool_issuance_record_employee_fk_idx ON public.smis_tool_issuance_record USING btree (employee_id);
create index if not exists smis_tool_issuance_record_issuer_fk_idx ON public.smis_tool_issuance_record USING btree (issuer_employee_id);
create index if not exists smis_tool_issuance_record_org_fk_idx ON public.smis_tool_issuance_record USING btree (organization_id);
create index if not exists smis_tool_issuance_record_warehouse_fk_idx ON public.smis_tool_issuance_record USING btree (warehouse_id);
create index if not exists smis_tool_issuance_scope_idx ON public.smis_tool_issuance_record USING btree (tenant_id, issue_date DESC, organization_id, employee_id, status);
create index if not exists smis_tool_issuance_item_material_fk_idx ON public.smis_tool_issuance_record_item USING btree (material_id);
create index if not exists smis_tool_issuance_item_material_idx ON public.smis_tool_issuance_record_item USING btree (tenant_id, material_id);
create index if not exists smis_tool_issuance_item_record_fk_idx ON public.smis_tool_issuance_record_item USING btree (issuance_record_id);
create index if not exists smis_tool_issuance_standard_name_idx ON public.smis_tool_issuance_standard USING btree (tenant_id, status, standard_name);
create unique index if not exists smis_tool_issuance_standard_no_unique ON public.smis_tool_issuance_standard USING btree (tenant_id, lower(btrim(standard_no)));
create index if not exists smis_tool_standard_detail_material_fk_idx ON public.smis_tool_issuance_standard_detail USING btree (material_id);
create index if not exists smis_tool_standard_detail_material_idx ON public.smis_tool_issuance_standard_detail USING btree (tenant_id, material_id);
create index if not exists smis_tool_standard_detail_standard_fk_idx ON public.smis_tool_issuance_standard_detail USING btree (standard_id);
create index if not exists smis_tool_standard_detail_standard_idx ON public.smis_tool_issuance_standard_detail USING btree (tenant_id, standard_id, sort);
create index if not exists smis_tool_standard_org_org_fk_idx ON public.smis_tool_issuance_standard_organization USING btree (organization_id);
create index if not exists smis_tool_standard_org_standard_fk_idx ON public.smis_tool_issuance_standard_organization USING btree (standard_id);
create index if not exists smis_tool_standard_org_tenant_idx ON public.smis_tool_issuance_standard_organization USING btree (tenant_id, organization_id);
create index if not exists smis_tool_standard_position_position_fk_idx ON public.smis_tool_issuance_standard_position USING btree (position_id);
create index if not exists smis_tool_standard_position_standard_fk_idx ON public.smis_tool_issuance_standard_position USING btree (standard_id);
create index if not exists smis_tool_standard_position_tenant_idx ON public.smis_tool_issuance_standard_position USING btree (tenant_id, position_id);
create index if not exists smis_tool_requisition_employee_fk_idx ON public.smis_tool_personal_requisition USING btree (employee_id);
create index if not exists smis_tool_requisition_org_fk_idx ON public.smis_tool_personal_requisition USING btree (organization_id);
create index if not exists smis_tool_requisition_position_fk_idx ON public.smis_tool_personal_requisition USING btree (position_id);
create index if not exists smis_tool_requisition_scope_idx ON public.smis_tool_personal_requisition USING btree (tenant_id, planned_issue_date DESC, organization_id, employee_id);
create index if not exists smis_tool_requisition_item_material_fk_idx ON public.smis_tool_personal_requisition_item USING btree (material_id);
create index if not exists smis_tool_requisition_item_parent_fk_idx ON public.smis_tool_personal_requisition_item USING btree (requisition_id);
create index if not exists smis_tool_requisition_item_plan_fk_idx ON public.smis_tool_personal_requisition_item USING btree (personal_standard_item_id);
create index if not exists smis_tool_requisition_status_idx ON public.smis_tool_personal_requisition_item USING btree (tenant_id, status, issued_at);
create index if not exists smis_tool_personal_employee_fk_idx ON public.smis_tool_personal_standard USING btree (employee_id);
create index if not exists smis_tool_personal_org_fk_idx ON public.smis_tool_personal_standard USING btree (organization_id);
create index if not exists smis_tool_personal_position_fk_idx ON public.smis_tool_personal_standard USING btree (position_id);
create index if not exists smis_tool_personal_scope_idx ON public.smis_tool_personal_standard USING btree (tenant_id, organization_id, position_id);
create index if not exists smis_tool_personal_item_detail_fk_idx ON public.smis_tool_personal_standard_item USING btree (source_detail_id);
create index if not exists smis_tool_personal_item_due_idx ON public.smis_tool_personal_standard_item USING btree (tenant_id, status, next_issue_date) WHERE (status = 'enabled'::text);
create index if not exists smis_tool_personal_item_material_fk_idx ON public.smis_tool_personal_standard_item USING btree (material_id);
create index if not exists smis_tool_personal_item_parent_idx ON public.smis_tool_personal_standard_item USING btree (tenant_id, personal_standard_id);
create index if not exists smis_tool_personal_item_personal_fk_idx ON public.smis_tool_personal_standard_item USING btree (personal_standard_id);
create index if not exists smis_tool_personal_item_standard_fk_idx ON public.smis_tool_personal_standard_item USING btree (source_standard_id);

alter table public.smis_tool_issuance_record enable row level security;
alter table public.smis_tool_issuance_record_item enable row level security;
alter table public.smis_tool_issuance_standard enable row level security;
alter table public.smis_tool_issuance_standard_detail enable row level security;
alter table public.smis_tool_issuance_standard_organization enable row level security;
alter table public.smis_tool_issuance_standard_position enable row level security;
alter table public.smis_tool_personal_requisition enable row level security;
alter table public.smis_tool_personal_requisition_item enable row level security;
alter table public.smis_tool_personal_standard enable row level security;
alter table public.smis_tool_personal_standard_item enable row level security;
alter table public.smis_tool_setting enable row level security;

drop policy if exists "smis_tool_issuance_delete" on public.smis_tool_issuance_record;
create policy "smis_tool_issuance_delete" on public.smis_tool_issuance_record for delete to "authenticated" using (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceRecord:Delete'::text) AS has_permission)));
drop policy if exists "smis_tool_issuance_insert" on public.smis_tool_issuance_record;
create policy "smis_tool_issuance_insert" on public.smis_tool_issuance_record for insert to "authenticated" with check (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceRecord:Add'::text) AS has_permission)));
drop policy if exists "smis_tool_issuance_select" on public.smis_tool_issuance_record;
create policy "smis_tool_issuance_select" on public.smis_tool_issuance_record for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceRecord:View'::text) AS has_permission))));
drop policy if exists "smis_tool_issuance_update" on public.smis_tool_issuance_record;
create policy "smis_tool_issuance_update" on public.smis_tool_issuance_record for update to "authenticated" using (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND (( SELECT app_private.has_permission('SmisToolIssuanceRecord:Edit'::text) AS has_permission) OR ( SELECT app_private.has_permission('SmisToolIssuanceRecord:Issue'::text) AS has_permission)))) with check ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)));
drop policy if exists "smis_tool_issuance_item_delete" on public.smis_tool_issuance_record_item;
create policy "smis_tool_issuance_item_delete" on public.smis_tool_issuance_record_item for delete to "authenticated" using (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceRecord:Delete'::text) AS has_permission)));
drop policy if exists "smis_tool_issuance_item_insert" on public.smis_tool_issuance_record_item;
create policy "smis_tool_issuance_item_insert" on public.smis_tool_issuance_record_item for insert to "authenticated" with check (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceRecord:Add'::text) AS has_permission)));
drop policy if exists "smis_tool_issuance_item_select" on public.smis_tool_issuance_record_item;
create policy "smis_tool_issuance_item_select" on public.smis_tool_issuance_record_item for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceRecord:View'::text) AS has_permission))));
drop policy if exists "smis_tool_issuance_item_update" on public.smis_tool_issuance_record_item;
create policy "smis_tool_issuance_item_update" on public.smis_tool_issuance_record_item for update to "authenticated" using (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND (( SELECT app_private.has_permission('SmisToolIssuanceRecord:Edit'::text) AS has_permission) OR ( SELECT app_private.has_permission('SmisToolIssuanceRecord:Issue'::text) AS has_permission)))) with check ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)));
drop policy if exists "smis_tool_issuance_standard_select" on public.smis_tool_issuance_standard;
create policy "smis_tool_issuance_standard_select" on public.smis_tool_issuance_standard for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceStandard:View'::text) AS has_permission))));
drop policy if exists "smis_tool_issuance_standard_detail_select" on public.smis_tool_issuance_standard_detail;
create policy "smis_tool_issuance_standard_detail_select" on public.smis_tool_issuance_standard_detail for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceStandard:View'::text) AS has_permission))));
drop policy if exists "smis_tool_issuance_standard_organization_select" on public.smis_tool_issuance_standard_organization;
create policy "smis_tool_issuance_standard_organization_select" on public.smis_tool_issuance_standard_organization for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceStandard:View'::text) AS has_permission))));
drop policy if exists "smis_tool_issuance_standard_position_select" on public.smis_tool_issuance_standard_position;
create policy "smis_tool_issuance_standard_position_select" on public.smis_tool_issuance_standard_position for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolIssuanceStandard:View'::text) AS has_permission))));
drop policy if exists "smis_tool_requisition_delete" on public.smis_tool_personal_requisition;
create policy "smis_tool_requisition_delete" on public.smis_tool_personal_requisition for delete to "authenticated" using (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalRequisition:Generate'::text) AS has_permission)));
drop policy if exists "smis_tool_requisition_insert" on public.smis_tool_personal_requisition;
create policy "smis_tool_requisition_insert" on public.smis_tool_personal_requisition for insert to "authenticated" with check (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalRequisition:Generate'::text) AS has_permission)));
drop policy if exists "smis_tool_requisition_select" on public.smis_tool_personal_requisition;
create policy "smis_tool_requisition_select" on public.smis_tool_personal_requisition for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalRequisition:View'::text) AS has_permission))));
drop policy if exists "smis_tool_requisition_update" on public.smis_tool_personal_requisition;
create policy "smis_tool_requisition_update" on public.smis_tool_personal_requisition for update to "authenticated" using (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND (( SELECT app_private.has_permission('SmisToolPersonalRequisition:Push'::text) AS has_permission) OR ( SELECT app_private.has_permission('SmisToolPersonalRequisition:Confirm'::text) AS has_permission)))) with check ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)));
drop policy if exists "smis_tool_requisition_item_delete" on public.smis_tool_personal_requisition_item;
create policy "smis_tool_requisition_item_delete" on public.smis_tool_personal_requisition_item for delete to "authenticated" using (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalRequisition:Generate'::text) AS has_permission)));
drop policy if exists "smis_tool_requisition_item_insert" on public.smis_tool_personal_requisition_item;
create policy "smis_tool_requisition_item_insert" on public.smis_tool_personal_requisition_item for insert to "authenticated" with check (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalRequisition:Generate'::text) AS has_permission)));
drop policy if exists "smis_tool_requisition_item_select" on public.smis_tool_personal_requisition_item;
create policy "smis_tool_requisition_item_select" on public.smis_tool_personal_requisition_item for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalRequisition:View'::text) AS has_permission))));
drop policy if exists "smis_tool_requisition_item_update" on public.smis_tool_personal_requisition_item;
create policy "smis_tool_requisition_item_update" on public.smis_tool_personal_requisition_item for update to "authenticated" using (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND (( SELECT app_private.has_permission('SmisToolPersonalRequisition:Push'::text) AS has_permission) OR ( SELECT app_private.has_permission('SmisToolPersonalRequisition:Confirm'::text) AS has_permission)))) with check ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)));
drop policy if exists "smis_tool_personal_standard_select" on public.smis_tool_personal_standard;
create policy "smis_tool_personal_standard_select" on public.smis_tool_personal_standard for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalStandard:View'::text) AS has_permission))));
drop policy if exists "smis_tool_personal_standard_item_select" on public.smis_tool_personal_standard_item;
create policy "smis_tool_personal_standard_item_select" on public.smis_tool_personal_standard_item for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR ((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalStandard:View'::text) AS has_permission))));
drop policy if exists "smis_tool_setting_insert" on public.smis_tool_setting;
create policy "smis_tool_setting_insert" on public.smis_tool_setting for insert to "authenticated" with check (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalRequisition:Configure'::text) AS has_permission)));
drop policy if exists "smis_tool_setting_select" on public.smis_tool_setting;
create policy "smis_tool_setting_select" on public.smis_tool_setting for select to "authenticated" using ((( SELECT app_private.is_platform_super() AS is_platform_super) OR (tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id))));
drop policy if exists "smis_tool_setting_update" on public.smis_tool_setting;
create policy "smis_tool_setting_update" on public.smis_tool_setting for update to "authenticated" using (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalRequisition:Configure'::text) AS has_permission))) with check (((tenant_id = ( SELECT app_private.auth_user_tenant_id() AS auth_user_tenant_id)) AND ( SELECT app_private.has_permission('SmisToolPersonalRequisition:Configure'::text) AS has_permission)));

drop trigger if exists "smis_tool_issuance_create_audit" on public.smis_tool_issuance_record;
create trigger "smis_tool_issuance_create_audit" before insert on public.smis_tool_issuance_record for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'true');
drop trigger if exists "smis_tool_issuance_update_audit" on public.smis_tool_issuance_record;
create trigger "smis_tool_issuance_update_audit" before update on public.smis_tool_issuance_record for row EXECUTE FUNCTION trg_set_update_time_and_by();
drop trigger if exists "smis_tool_issuance_item_create_audit" on public.smis_tool_issuance_record_item;
create trigger "smis_tool_issuance_item_create_audit" before insert on public.smis_tool_issuance_record_item for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'true');
drop trigger if exists "smis_tool_issuance_item_update_audit" on public.smis_tool_issuance_record_item;
create trigger "smis_tool_issuance_item_update_audit" before update on public.smis_tool_issuance_record_item for row EXECUTE FUNCTION trg_set_update_time_and_by();
drop trigger if exists "smis_tool_issuance_standard_create_audit" on public.smis_tool_issuance_standard;
create trigger "smis_tool_issuance_standard_create_audit" before insert on public.smis_tool_issuance_standard for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'true');
drop trigger if exists "smis_tool_issuance_standard_update_audit" on public.smis_tool_issuance_standard;
create trigger "smis_tool_issuance_standard_update_audit" before update on public.smis_tool_issuance_standard for row EXECUTE FUNCTION trg_set_update_time_and_by();
drop trigger if exists "smis_tool_standard_detail_create_audit" on public.smis_tool_issuance_standard_detail;
create trigger "smis_tool_standard_detail_create_audit" before insert on public.smis_tool_issuance_standard_detail for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'true');
drop trigger if exists "smis_tool_standard_detail_update_audit" on public.smis_tool_issuance_standard_detail;
create trigger "smis_tool_standard_detail_update_audit" before update on public.smis_tool_issuance_standard_detail for row EXECUTE FUNCTION trg_set_update_time_and_by();
drop trigger if exists "smis_tool_standard_org_create_audit" on public.smis_tool_issuance_standard_organization;
create trigger "smis_tool_standard_org_create_audit" before insert on public.smis_tool_issuance_standard_organization for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'false');
drop trigger if exists "smis_tool_standard_position_create_audit" on public.smis_tool_issuance_standard_position;
create trigger "smis_tool_standard_position_create_audit" before insert on public.smis_tool_issuance_standard_position for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'false');
drop trigger if exists "smis_tool_requisition_create_audit" on public.smis_tool_personal_requisition;
create trigger "smis_tool_requisition_create_audit" before insert on public.smis_tool_personal_requisition for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'true');
drop trigger if exists "smis_tool_requisition_update_audit" on public.smis_tool_personal_requisition;
create trigger "smis_tool_requisition_update_audit" before update on public.smis_tool_personal_requisition for row EXECUTE FUNCTION trg_set_update_time_and_by();
drop trigger if exists "smis_tool_requisition_item_create_audit" on public.smis_tool_personal_requisition_item;
create trigger "smis_tool_requisition_item_create_audit" before insert on public.smis_tool_personal_requisition_item for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'true');
drop trigger if exists "smis_tool_requisition_item_update_audit" on public.smis_tool_personal_requisition_item;
create trigger "smis_tool_requisition_item_update_audit" before update on public.smis_tool_personal_requisition_item for row EXECUTE FUNCTION trg_set_update_time_and_by();
drop trigger if exists "smis_tool_personal_create_audit" on public.smis_tool_personal_standard;
create trigger "smis_tool_personal_create_audit" before insert on public.smis_tool_personal_standard for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'true');
drop trigger if exists "smis_tool_personal_update_audit" on public.smis_tool_personal_standard;
create trigger "smis_tool_personal_update_audit" before update on public.smis_tool_personal_standard for row EXECUTE FUNCTION trg_set_update_time_and_by();
drop trigger if exists "smis_tool_personal_item_create_audit" on public.smis_tool_personal_standard_item;
create trigger "smis_tool_personal_item_create_audit" before insert on public.smis_tool_personal_standard_item for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'true');
drop trigger if exists "smis_tool_personal_item_update_audit" on public.smis_tool_personal_standard_item;
create trigger "smis_tool_personal_item_update_audit" before update on public.smis_tool_personal_standard_item for row EXECUTE FUNCTION trg_set_update_time_and_by();
drop trigger if exists "smis_tool_setting_create_audit" on public.smis_tool_setting;
create trigger "smis_tool_setting_create_audit" before insert on public.smis_tool_setting for row EXECUTE FUNCTION trg_set_create_time_and_by('true', 'true');
drop trigger if exists "smis_tool_setting_update_audit" on public.smis_tool_setting;
create trigger "smis_tool_setting_update_audit" before update on public.smis_tool_setting for row EXECUTE FUNCTION trg_set_update_time_and_by();

-- 复用已验证的同类业务行为，并将表、权限与提示全部隔离到工器具域。
CREATE OR REPLACE FUNCTION app_private.auto_confirm_tool_requisitions()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_count integer; v_requisition uuid;
begin
  update public.smis_tool_personal_requisition_item i
  set status='confirmed', confirmed_at=now(), confirmation_source='system', denial_reason=null
  from public.smis_tool_personal_requisition r
  left join public.smis_tool_setting s on s.tenant_id=r.tenant_id
  where i.requisition_id=r.id and i.status='issued_pending_confirmation'
    and i.issued_at <= now() - make_interval(days => coalesce(s.auto_confirm_days,3));
  get diagnostics v_count = row_count;
  for v_requisition in select distinct r.id from public.smis_tool_personal_requisition r
    join public.smis_tool_personal_requisition_item i on i.requisition_id=r.id
    where r.status in ('issued_pending_confirmation','partial')
  loop perform app_private.refresh_tool_requisition_status(v_requisition); end loop;
  return v_count;
end $function$;

CREATE OR REPLACE FUNCTION app_private.generate_due_tool_requisitions(p_due_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_employee record; v_requisition_id uuid; v_count integer := 0; v_item_count integer := 0; v_inserted integer;
begin
  for v_employee in
    select ps.tenant_id, ps.employee_id, e.employee_no, e.employee_name, e.position_id,
      p.position_name, e.organization_id, o.organization_name,
      min(i.next_issue_date) as planned_issue_date
    from public.smis_tool_personal_standard ps
    join public.smis_tool_personal_standard_item i on i.personal_standard_id = ps.id
    join public.hr_employee e on e.id = ps.employee_id
    left join public.hr_position p on p.id = e.position_id
    left join public.sys_organization o on o.id = e.organization_id
    where ps.status = 'enabled' and i.status = 'enabled'
      and coalesce(i.next_issue_date, i.initial_issue_date) <= p_due_date
      and not exists (
        select 1 from public.smis_tool_personal_requisition_item ri
        join public.smis_tool_personal_requisition r on r.id = ri.requisition_id
        where ri.personal_standard_item_id = i.id
          and ri.status in ('pending_issue','issued_pending_confirmation')
      )
    group by ps.tenant_id, ps.employee_id, e.employee_no, e.employee_name,
      e.position_id, p.position_name, e.organization_id, o.organization_name
  loop
    insert into public.smis_tool_personal_requisition(
      tenant_id,requisition_no,employee_id,employee_no_snapshot,employee_name_snapshot,
      position_id,position_name_snapshot,organization_id,organization_name_snapshot,
      planned_issue_date,status,source,reminder)
    values (v_employee.tenant_id,
      app_private.next_document_number('smis.tool_personal_requisition',v_employee.tenant_id),
      v_employee.employee_id,v_employee.employee_no,v_employee.employee_name,
      v_employee.position_id,v_employee.position_name,v_employee.organization_id,
      v_employee.organization_name,v_employee.planned_issue_date,'pending_issue','standard','已到工器具领用周期')
    on conflict (tenant_id,employee_id,planned_issue_date) do update set update_time = now()
    returning id into v_requisition_id;

    insert into public.smis_tool_personal_requisition_item(
      tenant_id,requisition_id,personal_standard_item_id,material_id,material_category_snapshot,
      material_name_snapshot,specification_model_snapshot,unit_snapshot,image_urls,
      quota_quantity,requested_quantity,quota_cycle_months,status)
    select i.tenant_id,v_requisition_id,i.id,i.material_id,c.category_name,m.material_name,
      m.specification_model,m.basic_unit,m.image_urls,i.quota_quantity,i.quota_quantity,
      app_private.tool_cycle_months(i.issuance_cycle,i.issuance_frequency),'pending_issue'
    from public.smis_tool_personal_standard_item i
    join public.smis_material m on m.id = i.material_id
    join public.smis_material_category c on c.id = m.category_id
    where i.personal_standard_id in (
      select ps.id from public.smis_tool_personal_standard ps
      where ps.tenant_id = v_employee.tenant_id and ps.employee_id = v_employee.employee_id)
      and i.status = 'enabled' and coalesce(i.next_issue_date,i.initial_issue_date) <= p_due_date
      and not exists (
        select 1 from public.smis_tool_personal_requisition_item existing
        where existing.personal_standard_item_id = i.id
          and existing.status in ('pending_issue','issued_pending_confirmation'))
    on conflict (requisition_id,personal_standard_item_id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted > 0 then v_count := v_count + 1; v_item_count := v_item_count + v_inserted; end if;
  end loop;
  return jsonb_build_object('documentCount',v_count,'itemCount',v_item_count);
end $function$;

CREATE OR REPLACE FUNCTION app_private.hr_atoolnd_candidate_stage(p_candidate_id uuid, p_to_stage text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_candidate public.hr_candidate;
  v_valid boolean := false;
begin
  select * into v_candidate
  from public.hr_candidate
  where id = p_candidate_id
  for update;
  if not found then raise exception '候选人不存在'; end if;
  if v_candidate.stage = p_to_stage then return; end if;

  v_valid :=
    (v_candidate.stage = 'new' and p_to_stage in ('screening', 'rejected', 'withdrawn')) or
    (v_candidate.stage = 'screening' and p_to_stage in ('interview', 'rejected', 'withdrawn')) or
    (v_candidate.stage = 'interview' and p_to_stage in ('offer', 'rejected', 'withdrawn')) or
    (v_candidate.stage = 'offer' and p_to_stage in ('hired', 'rejected', 'withdrawn'));
  if not v_valid then
    raise exception '候选人阶段不能从 % 变更为 %', v_candidate.stage, p_to_stage;
  end if;
  if p_to_stage in ('rejected', 'withdrawn') and nullif(btrim(p_reason), '') is null then
    raise exception '淘汰或放弃候选人必须填写原因';
  end if;

  perform pg_catalog.set_config('app.hr_recruitment_engine', 'on', true);
  update public.hr_candidate
  set stage = p_to_stage,
      rejection_reason = case when p_to_stage in ('rejected', 'withdrawn') then btrim(p_reason) else null end
  where id = p_candidate_id;
  insert into public.hr_candidate_stage_history(
    tenant_id, candidate_id, from_stage, to_stage, transition_reason, changed_by
  ) values (
    v_candidate.tenant_id, v_candidate.id, v_candidate.stage, p_to_stage,
    nullif(btrim(p_reason), ''), coalesce(app_private.current_user_email(), 'system')
  );
end
$function$;

-- 归还表必须先于审批回调函数创建，回调函数使用表行类型作为局部变量。
create table if not exists public.smis_tool_return (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  return_no text not null,
  employee_id uuid not null references public.hr_employee(id) on delete restrict,
  employee_no_snapshot text not null,
  employee_name_snapshot text not null,
  position_name_snapshot text,
  organization_id uuid references public.sys_organization(id) on delete set null,
  organization_name_snapshot text,
  source_document_no text not null,
  return_date date not null default current_date,
  status text not null default 'draft'
    check (status in ('draft','pending_approval','approved','rejected')),
  submitted_at timestamptz,
  approved_at timestamptz,
  rejection_reason text check (rejection_reason is null or char_length(rejection_reason) <= 500),
  remark text check (remark is null or char_length(remark) <= 1000),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_tool_return_id_tenant_unique unique(id, tenant_id),
  constraint smis_tool_return_no_unique unique(tenant_id, return_no)
);

create table if not exists public.smis_tool_return_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  return_id uuid not null,
  source_issuance_record_id uuid not null
    references public.smis_tool_issuance_record(id) on delete restrict,
  source_issuance_item_id uuid not null
    references public.smis_tool_issuance_record_item(id) on delete restrict,
  source_issuance_no_snapshot text not null,
  material_id uuid not null references public.smis_material(id) on delete restrict,
  material_category_snapshot text,
  material_name_snapshot text not null,
  specification_model_snapshot text,
  unit_snapshot text not null,
  issued_quantity numeric not null check (issued_quantity > 0),
  return_quantity numeric not null check (return_quantity > 0),
  remark text check (remark is null or char_length(remark) <= 500),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_tool_return_item_parent_fkey
    foreign key(return_id, tenant_id)
    references public.smis_tool_return(id, tenant_id) on delete cascade,
  constraint smis_tool_return_item_source_unique unique(return_id, source_issuance_item_id)
);

create or replace function app_private.execute_tool_return_workflow_callback(
  p_business_id uuid,
  p_status text,
  p_actor text,
  p_comment text
) returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  update public.smis_tool_return
  set status = case p_status
        when 'running' then 'pending_approval'
        when 'approved' then 'approved'
        when 'rejected' then 'rejected'
        when 'draft' then 'draft'
        when 'cancelled' then 'rejected'
        else status
      end,
      submitted_at = case when p_status = 'running' then now() else submitted_at end,
      approved_at = case when p_status = 'approved' then now() else null end,
      rejection_reason = case
        when p_status in ('rejected','cancelled') then nullif(btrim(coalesce(p_comment,'')), '')
        when p_status in ('running','approved','draft') then null
        else rejection_reason
      end,
      update_by = coalesce(nullif(btrim(p_actor),''), 'workflow-engine')
  where id = p_business_id;
  if not found then
    raise exception '工器具归还单不存在或已删除';
  end if;
end
$function$;

create or replace function app_private.execute_workflow_business_callback(
  p_business_type text,
  p_business_id uuid,
  p_status text,
  p_actor text,
  p_comment text
) returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_business_type = 'smis_tool_return' then
    perform app_private.execute_tool_return_workflow_callback(
      p_business_id, p_status, p_actor, p_comment
    );
  elsif p_business_type = 'hr_recruitment_requisition' then
    perform app_private.execute_hr_recruitment_workflow_callback(
      p_business_id, p_status, p_actor, p_comment
    );
  else
    perform app_private.execute_workflow_business_callback_before_hr_p2(
      p_business_type, p_business_id, p_status, p_actor, p_comment
    );
  end if;
end
$function$;

create or replace function app_private.get_tool_return_workflow_snapshot(p_instance_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_instance public.wf_instance;
  v_return public.smis_tool_return;
  v_quantity numeric;
  v_item_count integer;
begin
  if auth.uid() is null or not app_private.can_view_workflow_instance(p_instance_id) then
    raise exception '无权查看该审批业务信息' using errcode = '42501';
  end if;
  select * into v_instance from public.wf_instance where id = p_instance_id;
  if not found or v_instance.business_type <> 'smis_tool_return' then
    raise exception '工器具归还审批实例不存在';
  end if;
  select * into v_return from public.smis_tool_return where id = v_instance.business_id;
  if not found then
    return jsonb_build_object(
      'instanceId', v_instance.id,
      'businessType', v_instance.business_type,
      'businessId', v_instance.business_id,
      'title', v_instance.business_title,
      'warnings', jsonb_build_array('业务原单已删除，当前仅展示流程快照'),
      'metrics', '[]'::jsonb,
      'fields', '[]'::jsonb,
      'attachments', '[]'::jsonb
    );
  end if;
  select count(*)::integer, coalesce(sum(return_quantity),0)
  into v_item_count, v_quantity
  from public.smis_tool_return_item where return_id = v_return.id;
  return jsonb_build_object(
    'instanceId', v_instance.id,
    'businessType', v_instance.business_type,
    'businessId', v_instance.business_id,
    'title', v_instance.business_title,
    'subtitle', concat_ws(' · ', v_return.employee_name_snapshot, v_return.organization_name_snapshot),
    'businessNo', v_return.return_no,
    'status', v_return.status,
    'routePath', '/smis/safety-production/tool-requisition/tool-requisition-return',
    'metrics', jsonb_build_array(
      jsonb_build_object('label','归还明细','value',v_item_count::text || ' 项','tone','primary'),
      jsonb_build_object('label','归还数量','value',trim(trailing '.' from trim(trailing '0' from v_quantity::text)),'tone','success'),
      jsonb_build_object('label','归还日期','value',v_return.return_date::text,'tone','info')
    ),
    'fields', jsonb_build_array(
      jsonb_build_object('label','归还单号','value',v_return.return_no),
      jsonb_build_object('label','源发放单号','value',v_return.source_document_no),
      jsonb_build_object('label','领用人','value',v_return.employee_name_snapshot),
      jsonb_build_object('label','所属部门','value',coalesce(v_return.organization_name_snapshot,'--')),
      jsonb_build_object('label','备注','value',coalesce(v_return.remark,'--'))
    ),
    'warnings', '[]'::jsonb,
    'attachments', '[]'::jsonb
  );
end
$function$;

create or replace function app_private.get_workflow_business_snapshot_v3(p_instance_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  business_type_value text;
begin
  select instance_row.business_type
  into business_type_value
  from public.wf_instance instance_row
  where instance_row.id = p_instance_id;

  if business_type_value = 'smis_tool_return' then
    return app_private.get_tool_return_workflow_snapshot(p_instance_id);
  end if;
  if business_type_value in (
    'hr_personnel_change',
    'hr_lifecycle_case',
    'hr_self_service_request',
    'hr_recruitment_requisition'
  ) then
    return app_private.get_hr_workflow_business_snapshot(p_instance_id);
  end if;
  return app_private.get_workflow_business_snapshot_v2(p_instance_id);
end
$function$;

create or replace function public.smis_submit_tool_return_secure(p_return_id uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_return public.smis_tool_return;
  v_instance_id uuid;
begin
  if auth.uid() is null
     or not app_private.has_permission('SmisToolRequisitionReturn:Submit') then
    raise exception '当前账号没有提交归还审批的权限' using errcode = '42501';
  end if;
  select * into v_return
  from public.smis_tool_return
  where id = p_return_id
    and (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and status in ('draft','rejected')
  for update;
  if not found then
    raise exception '归还单不存在、无权提交或当前状态不允许提交' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.smis_tool_return_item where return_id = p_return_id
  ) then
    raise exception '归还单没有可提交的明细' using errcode = '22023';
  end if;
  v_instance_id := app_private.start_workflow(
    'smis_tool_return',
    v_return.id,
    '工器具归还 ' || v_return.return_no,
    jsonb_build_object(
      'returnNo', v_return.return_no,
      'employeeId', v_return.employee_id,
      'employeeName', v_return.employee_name_snapshot,
      'sourceDocumentNo', v_return.source_document_no,
      'returnDate', v_return.return_date,
      'itemCount', (select count(*) from public.smis_tool_return_item where return_id = v_return.id),
      'returnQuantity', (select coalesce(sum(return_quantity),0) from public.smis_tool_return_item where return_id = v_return.id)
    ),
    gen_random_uuid()::text
  );
  return v_instance_id;
end
$function$;

CREATE OR REPLACE FUNCTION app_private.post_tool_issuance_record(p_record_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_record record; v_item record; v_months integer;
begin
  select * into v_record from public.smis_tool_issuance_record where id=p_record_id for update;
  if v_record.id is null or v_record.status<>'draft' then raise exception '仅草稿状态允许发放过账' using errcode='P0001'; end if;
  update public.smis_tool_issuance_record set status='posted',posted_at=now() where id=p_record_id;
  for v_item in select i.*,ri.requisition_id,ri.personal_standard_item_id,ri.quota_cycle_months from public.smis_tool_issuance_record_item i left join public.smis_tool_personal_requisition_item ri on ri.id=i.requisition_item_id where i.issuance_record_id=p_record_id loop
    if v_item.requisition_item_id is not null then
      update public.smis_tool_personal_requisition_item set status='issued_pending_confirmation',issued_at=now() where id=v_item.requisition_item_id;
      perform app_private.refresh_tool_requisition_status(v_item.requisition_id);
    end if;
    update public.smis_tool_personal_standard_item psi set last_issue_date=v_record.issue_date,next_issue_date=v_record.issue_date+make_interval(months=>app_private.tool_cycle_months(psi.issuance_cycle,psi.issuance_frequency)) where psi.id=v_item.personal_standard_item_id;
  end loop;
  return v_record.issuance_no;
end $function$;

CREATE OR REPLACE FUNCTION app_private.tool_cycle_months(p_cycle text, p_frequency integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select greatest(1, case p_cycle
    when 'day' then ceil(p_frequency::numeric / 30)::integer
    when 'week' then ceil(p_frequency::numeric * 7 / 30)::integer
    when 'month' then p_frequency
    when 'quarter' then p_frequency * 3
    when 'half_year' then p_frequency * 6
    when 'year' then p_frequency * 12
    else p_frequency end)
$function$;

CREATE OR REPLACE FUNCTION app_private.refresh_tool_requisition_status(p_requisition_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_status text;
begin
  select case
    when bool_and(i.status = 'confirmed') then 'confirmed'
    when bool_and(i.status = 'denied') then 'denied'
    when bool_and(i.status in ('confirmed','denied')) then 'partial'
    when bool_or(i.status = 'issued_pending_confirmation') then 'issued_pending_confirmation'
    when bool_or(i.status = 'pending_issue') then 'pending_issue'
    else 'partial' end
  into v_status from public.smis_tool_personal_requisition_item i
  where i.requisition_id = p_requisition_id;
  update public.smis_tool_personal_requisition set status = coalesce(v_status, status)
  where id = p_requisition_id;
end $function$;

CREATE OR REPLACE FUNCTION app_private.run_daily_tool_automation()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_generated jsonb; v_confirmed integer;
begin
  v_generated := app_private.generate_due_tool_requisitions(current_date);
  v_confirmed := app_private.auto_confirm_tool_requisitions();
  return jsonb_build_object('generated',v_generated,'confirmedItemCount',v_confirmed);
end $function$;

CREATE OR REPLACE FUNCTION public.smis_confirm_tool_requisition_items_secure(p_item_ids uuid[], p_confirmed boolean, p_reason text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_current_employee uuid; v_count integer; v_requisition uuid;
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisToolPersonalRequisition:Confirm') then raise exception '当前账号没有确认领用的权限' using errcode='42501'; end if;
  select hr_employee_id into v_current_employee from public.sys_user where auth_user_id=(select auth.uid()) and deleted_at is null;
  if v_current_employee is null then raise exception '当前登录账号未关联员工花名册，无法确认领用' using errcode='42501'; end if;
  if cardinality(coalesce(p_item_ids,array[]::uuid[]))=0 then raise exception '请选择待确认的领用明细' using errcode='22023'; end if;
  if exists(select 1 from public.smis_tool_personal_requisition_item i join public.smis_tool_personal_requisition r on r.id=i.requisition_id where i.id=any(p_item_ids) and (r.employee_id<>v_current_employee or i.status<>'issued_pending_confirmation')) then raise exception '只能确认本人已发放且待确认的领用明细' using errcode='42501'; end if;
  if not p_confirmed and nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception '否认领用时必须填写原因' using errcode='22023'; end if;
  update public.smis_tool_personal_requisition_item set status=case when p_confirmed then 'confirmed' else 'denied' end,confirmed_at=now(),confirmation_source='employee',denial_reason=case when p_confirmed then null else btrim(p_reason) end where id=any(p_item_ids);
  get diagnostics v_count=row_count;
  for v_requisition in select distinct requisition_id from public.smis_tool_personal_requisition_item where id=any(p_item_ids) loop perform app_private.refresh_tool_requisition_status(v_requisition); end loop;
  return v_count;
end $function$;

CREATE OR REPLACE FUNCTION public.smis_delete_tool_issuance_records_secure(p_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count integer;
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisToolIssuanceRecord:Delete') then raise exception '当前账号没有删除发放记录的权限' using errcode='42501'; end if;
  if exists(select 1 from public.smis_tool_issuance_record where id=any(coalesce(p_ids,array[]::uuid[])) and status<>'draft') then raise exception '仅草稿状态允许删除' using errcode='P0001'; end if;
  delete from public.smis_tool_issuance_record where id=any(coalesce(p_ids,array[]::uuid[])) and (app_private.is_platform_super() or tenant_id=app_private.auth_user_tenant_id());
  get diagnostics v_count=row_count; return v_count;
end $function$;

CREATE OR REPLACE FUNCTION public.smis_delete_tool_issuance_standards_secure(p_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_count integer; begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if; if not app_private.has_permission('SmisToolIssuanceStandard:Delete') then raise exception '当前账号没有删除权限' using errcode='42501'; end if;
  if exists(select 1 from public.smis_tool_personal_standard_item where source_standard_id=any(coalesce(p_ids,array[]::uuid[]))) then raise exception '所选标准已生成个人标准，请改为停用' using errcode='23503'; end if;
  delete from public.smis_tool_issuance_standard where (app_private.is_platform_super() or tenant_id=app_private.auth_user_tenant_id()) and id=any(coalesce(p_ids,array[]::uuid[])); get diagnostics v_count=row_count; return v_count;
end $function$;

CREATE OR REPLACE FUNCTION public.smis_generate_due_tool_requisitions_secure(p_due_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisToolPersonalRequisition:Generate') then raise exception '当前账号没有生成领用单的权限' using errcode='42501'; end if;
  return app_private.generate_due_tool_requisitions(coalesce(p_due_date,current_date));
end $function$;

CREATE OR REPLACE FUNCTION public.smis_generate_tool_personal_standards_secure(p_employee_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_employee record; v_personal uuid; v_employees integer:=0; v_items integer:=0; v_unmatched integer:=0; v_inserted integer;
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if; if not app_private.has_permission('SmisToolPersonalStandard:Generate') then raise exception '当前账号没有生成个人标准的权限' using errcode='42501'; end if;
  if cardinality(coalesce(p_employee_ids,array[]::uuid[]))=0 then raise exception '请选择需要生成个人标准的员工' using errcode='22023'; end if;
  for v_employee in select e.* from public.hr_employee e where e.id=any(p_employee_ids) and (app_private.is_platform_super() or e.tenant_id=app_private.auth_user_tenant_id()) loop
    insert into public.smis_tool_personal_standard(tenant_id,employee_id,organization_id,position_id,generated_at,status) values(v_employee.tenant_id,v_employee.id,v_employee.organization_id,v_employee.position_id,now(),'enabled')
    on conflict(tenant_id,employee_id) do update set organization_id=excluded.organization_id,position_id=excluded.position_id,generated_at=excluded.generated_at,status='enabled' returning id into v_personal;
    delete from public.smis_tool_personal_standard_item where personal_standard_id=v_personal;
    insert into public.smis_tool_personal_standard_item(tenant_id,personal_standard_id,source_standard_id,source_detail_id,material_id,quota_quantity,issuance_cycle,issuance_frequency,status)
    select v_employee.tenant_id,v_personal,s.id,d.id,d.material_id,d.quota_quantity,d.issuance_cycle,d.issuance_frequency,d.status
    from public.smis_tool_issuance_standard s join public.smis_tool_issuance_standard_detail d on d.standard_id=s.id
    where s.tenant_id=v_employee.tenant_id and s.status='enabled' and d.status='enabled'
      and (not exists(select 1 from public.smis_tool_issuance_standard_position sp where sp.standard_id=s.id) or exists(select 1 from public.smis_tool_issuance_standard_position sp where sp.standard_id=s.id and sp.position_id=v_employee.position_id))
      and (not exists(select 1 from public.smis_tool_issuance_standard_organization so where so.standard_id=s.id) or exists(select 1 from public.smis_tool_issuance_standard_organization so where so.standard_id=s.id and so.organization_id=v_employee.organization_id));
    get diagnostics v_inserted=row_count; v_items:=v_items+v_inserted; v_employees:=v_employees+1; if v_inserted=0 then v_unmatched:=v_unmatched+1; end if;
  end loop;
  return jsonb_build_object('employeeCount',v_employees,'itemCount',v_items,'unmatchedCount',v_unmatched);
end $function$;

CREATE OR REPLACE FUNCTION public.smis_get_tool_issuance_statistics_secure(p_date_from date, p_date_to date, p_organization_id uuid DEFAULT NULL::uuid, p_employee_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (select auth.uid()) is null or not (app_private.is_platform_super() or app_private.has_permission('SmisToolIssuanceRecord:Statistics') or app_private.has_permission('SmisToolPersonalRequisition:Statistics')) then raise exception '当前账号没有统计分析权限' using errcode='42501'; end if;
  return (with base as (
    select r.id as record_id,r.organization_id,r.organization_name_snapshot,r.employee_id,r.employee_name_snapshot,r.issue_date,i.material_name_snapshot,i.specification_model_snapshot,i.unit_snapshot,i.issue_quantity
    from public.smis_tool_issuance_record r join public.smis_tool_issuance_record_item i on i.issuance_record_id=r.id
    where r.status='posted' and (app_private.current_read_tenant_id() is null or r.tenant_id=app_private.current_read_tenant_id())
      and (p_date_from is null or r.issue_date>=p_date_from) and (p_date_to is null or r.issue_date<=p_date_to)
      and (p_organization_id is null or r.organization_id=p_organization_id) and (p_employee_id is null or r.employee_id=p_employee_id)
  ) select jsonb_build_object('summary',jsonb_build_object('documentCount',(select count(distinct record_id) from base),'employeeCount',(select count(distinct employee_id) from base),'materialCount',(select count(distinct (material_name_snapshot,specification_model_snapshot)) from base),'totalQuantity',coalesce((select sum(issue_quantity) from base),0)),
    'rows',coalesce((select jsonb_agg(x order by x."organizationName",x."materialName") from (select organization_id as "organizationId",coalesce(organization_name_snapshot,'未分配组织') as "organizationName",material_name_snapshot as "materialName",specification_model_snapshot as "specificationModel",unit_snapshot as unit,sum(issue_quantity) as quantity,count(distinct employee_id) as "employeeCount" from base group by organization_id,organization_name_snapshot,material_name_snapshot,specification_model_snapshot,unit_snapshot) x),'[]'::jsonb)));
end $function$;

CREATE OR REPLACE FUNCTION public.smis_get_tool_setting_secure()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tenant uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisToolPersonalRequisition:View')) then raise exception '当前账号没有查看领用配置的权限' using errcode='42501'; end if;
  v_tenant := app_private.current_read_tenant_id();
  return jsonb_build_object('autoConfirmDays',coalesce((select auto_confirm_days from public.smis_tool_setting where tenant_id=v_tenant),3));
end $function$;

CREATE OR REPLACE FUNCTION public.smis_list_tool_issuance_records_secure(p_from integer DEFAULT 0, p_to integer DEFAULT 19, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_organization_id uuid DEFAULT NULL::uuid, p_employee_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_keyword text DEFAULT NULL::text, p_purpose text DEFAULT 'list'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),v_from); v_keyword text:=nullif(btrim(coalesce(p_keyword,'')),'');
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if p_purpose='export' and not app_private.has_permission('SmisToolIssuanceRecord:Export') then raise exception '当前账号没有导出发放记录的权限' using errcode='42501'; end if;
  if p_purpose='list' and not (app_private.is_platform_super() or app_private.has_permission('SmisToolIssuanceRecord:View')) then raise exception '当前账号没有查看发放记录的权限' using errcode='42501'; end if;
  return (with filtered as (
    select r.* from public.smis_tool_issuance_record r
    where (app_private.current_read_tenant_id() is null or r.tenant_id=app_private.current_read_tenant_id())
      and (p_date_from is null or r.issue_date>=p_date_from) and (p_date_to is null or r.issue_date<=p_date_to)
      and (p_organization_id is null or r.organization_id=p_organization_id)
      and (p_employee_id is null or r.employee_id=p_employee_id) and (p_status is null or r.status=p_status)
      and (v_keyword is null or r.issuance_no ilike '%'||v_keyword||'%' or r.employee_name_snapshot ilike '%'||v_keyword||'%' or r.warehouse_name_snapshot ilike '%'||v_keyword||'%')
  ), rows as (
    select r.id,r.tenant_id as "tenantId",r.issuance_no as "issuanceNo",r.employee_id as "employeeId",
      r.employee_no_snapshot as "employeeNo",r.employee_name_snapshot as "employeeName",r.position_name_snapshot as "positionName",
      r.organization_id as "organizationId",r.organization_name_snapshot as "organizationName",r.warehouse_id as "warehouseId",
      r.warehouse_name_snapshot as "warehouseName",r.issuer_employee_id as "issuerEmployeeId",r.issuer_name_snapshot as "issuerName",
      r.issue_date as "issueDate",r.status,r.posted_at as "postedAt",r.remark,r.create_time as "createTime",
      coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'requisitionItemId',i.requisition_item_id,'materialId',i.material_id,
        'materialCategory',i.material_category_snapshot,'materialName',i.material_name_snapshot,'specificationModel',i.specification_model_snapshot,
        'unit',i.unit_snapshot,'issueQuantity',i.issue_quantity,'remark',i.remark) order by i.material_name_snapshot)
        from public.smis_tool_issuance_record_item i where i.issuance_record_id=r.id),'[]'::jsonb) items
    from filtered r order by r.issue_date desc,r.create_time desc offset v_from limit v_to-v_from+1
  ) select jsonb_build_object('records',coalesce((select jsonb_agg(rows) from rows),'[]'::jsonb),'total',(select count(*) from filtered),
    'overview',(select jsonb_build_object('total',count(*),'draft',count(*) filter(where status='draft'),'posted',count(*) filter(where status='posted'),'today',count(*) filter(where issue_date=current_date),'quantity',coalesce(sum((select sum(i.issue_quantity) from public.smis_tool_issuance_record_item i where i.issuance_record_id=filtered.id)),0)) from filtered)));
end $function$;

CREATE OR REPLACE FUNCTION public.smis_list_tool_issuance_standards_secure(p_from integer DEFAULT 0, p_to integer DEFAULT 19, p_keyword text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_purpose text DEFAULT 'list'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),v_from); v_keyword text:=nullif(btrim(coalesce(p_keyword,'')),'');
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看发放标准' using errcode='42501'; end if;
  if p_purpose='export' and not app_private.has_permission('SmisToolIssuanceStandard:Export') then raise exception '当前账号没有导出权限' using errcode='42501'; end if;
  if p_purpose='list' and not (app_private.is_platform_super() or app_private.has_permission('SmisToolIssuanceStandard:View')) then raise exception '当前账号没有查看权限' using errcode='42501'; end if;
  return (with filtered as (
    select s.* from public.smis_tool_issuance_standard s where (app_private.current_read_tenant_id() is null or s.tenant_id=app_private.current_read_tenant_id()) and (p_status is null or s.status=p_status) and (v_keyword is null or s.standard_no ilike '%'||v_keyword||'%' or s.standard_name ilike '%'||v_keyword||'%')
  ), rows as (
    select s.id,s.tenant_id as "tenantId",s.standard_no as "standardNo",s.standard_name as "standardName",s.rated_quantity as "ratedQuantity",s.issuance_cycle as "issuanceCycle",s.issuance_frequency as "issuanceFrequency",s.status,s.description,s.create_time as "createTime",s.update_time as "updateTime",
      coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.position_code,'name',p.position_name,'organizationName',o.organization_name) order by p.sort,p.position_name) from public.smis_tool_issuance_standard_position sp join public.hr_position p on p.id=sp.position_id left join public.sys_organization o on o.id=p.organization_id where sp.standard_id=s.id),'[]'::jsonb) positions,
      coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'parentId',o.parent_id,'code',o.organization_code,'name',o.organization_name,'type',o.organization_type) order by o.sort,o.organization_name) from public.smis_tool_issuance_standard_organization so join public.sys_organization o on o.id=so.organization_id where so.standard_id=s.id),'[]'::jsonb) organizations,
      coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'materialId',m.id,'materialCode',m.material_code,'materialName',m.material_name,'categoryName',c.category_name,'specificationModel',m.specification_model,'basicUnit',m.basic_unit,'imageUrls',m.image_urls,'quotaQuantity',d.quota_quantity,'issuanceCycle',d.issuance_cycle,'issuanceFrequency',d.issuance_frequency,'status',d.status,'remark',d.remark,'sort',d.sort) order by d.sort,m.material_name) from public.smis_tool_issuance_standard_detail d join public.smis_material m on m.id=d.material_id join public.smis_material_category c on c.id=m.category_id where d.standard_id=s.id),'[]'::jsonb) details
    from filtered s order by s.update_time desc offset v_from limit v_to-v_from+1
  ) select jsonb_build_object('records',coalesce((select jsonb_agg(rows order by "updateTime" desc) from rows),'[]'::jsonb),'total',(select count(*) from filtered),'overview',(select jsonb_build_object('total',count(*),'enabled',count(*) filter(where status='enabled'),'disabled',count(*) filter(where status='disabled'),'detailTotal',coalesce(sum((select count(*) from public.smis_tool_issuance_standard_detail d where d.standard_id=filtered.id)),0)) from filtered)));
end $function$;

CREATE OR REPLACE FUNCTION public.smis_list_tool_personal_requisitions_secure(p_from integer DEFAULT 0, p_to integer DEFAULT 19, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_organization_id uuid DEFAULT NULL::uuid, p_employee_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_keyword text DEFAULT NULL::text, p_purpose text DEFAULT 'list'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),v_from); v_keyword text:=nullif(btrim(coalesce(p_keyword,'')),'');
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if p_purpose='export' and not app_private.has_permission('SmisToolPersonalRequisition:Export') then raise exception '当前账号没有导出领用单的权限' using errcode='42501'; end if;
  if p_purpose='list' and not (app_private.is_platform_super() or app_private.has_permission('SmisToolPersonalRequisition:View')) then raise exception '当前账号没有查看领用单的权限' using errcode='42501'; end if;
  return (with filtered as (
    select i.*,r.requisition_no,r.employee_id,r.employee_no_snapshot,r.employee_name_snapshot,
      r.position_name_snapshot,r.organization_id,r.organization_name_snapshot,
      r.operation_department_snapshot,r.operation_area_snapshot,r.team_snapshot,r.planned_issue_date,
      r.reminder,r.remark as header_remark
    from public.smis_tool_personal_requisition_item i
    join public.smis_tool_personal_requisition r on r.id=i.requisition_id
    where (app_private.current_read_tenant_id() is null or r.tenant_id=app_private.current_read_tenant_id())
      and (p_date_from is null or r.planned_issue_date>=p_date_from)
      and (p_date_to is null or r.planned_issue_date<=p_date_to)
      and (p_organization_id is null or r.organization_id=p_organization_id)
      and (p_employee_id is null or r.employee_id=p_employee_id)
      and (p_status is null or i.status=p_status)
      and (v_keyword is null or r.requisition_no ilike '%'||v_keyword||'%' or r.employee_name_snapshot ilike '%'||v_keyword||'%' or i.material_name_snapshot ilike '%'||v_keyword||'%')
  ), rows as (
    select id,"tenantId","requisitionId","requisitionNo","employeeId","employeeNo","employeeName","positionName",
      "organizationId","organizationName","operationDepartment","operationArea","team","materialId","materialCategory",
      "materialName","specificationModel","unit","imageUrls","quotaQuantity","requestedQuantity","quotaCycleMonths",
      "plannedIssueDate",status,"reminder","issuedAt","confirmedAt","confirmationSource","denialReason",remark
    from (select f.id,f.tenant_id as "tenantId",f.requisition_id as "requisitionId",f.requisition_no as "requisitionNo",
      f.employee_id as "employeeId",f.employee_no_snapshot as "employeeNo",f.employee_name_snapshot as "employeeName",
      f.position_name_snapshot as "positionName",f.organization_id as "organizationId",f.organization_name_snapshot as "organizationName",
      f.operation_department_snapshot as "operationDepartment",f.operation_area_snapshot as "operationArea",f.team_snapshot as team,
      f.material_id as "materialId",f.material_category_snapshot as "materialCategory",f.material_name_snapshot as "materialName",
      f.specification_model_snapshot as "specificationModel",f.unit_snapshot as unit,f.image_urls as "imageUrls",
      f.quota_quantity as "quotaQuantity",f.requested_quantity as "requestedQuantity",f.quota_cycle_months as "quotaCycleMonths",
      f.planned_issue_date as "plannedIssueDate",f.status,f.reminder,f.issued_at as "issuedAt",f.confirmed_at as "confirmedAt",
      f.confirmation_source as "confirmationSource",f.denial_reason as "denialReason",coalesce(f.remark,f.header_remark) as remark
      from filtered f order by f.planned_issue_date desc,f.requisition_no,f.employee_name_snapshot,f.material_name_snapshot
      offset v_from limit v_to-v_from+1) page
  ) select jsonb_build_object('records',coalesce((select jsonb_agg(rows) from rows),'[]'::jsonb),'total',(select count(*) from filtered),
    'overview',(select jsonb_build_object('total',count(*),'pending',count(*) filter(where status='pending_issue'),'waitingConfirmation',count(*) filter(where status='issued_pending_confirmation'),'confirmed',count(*) filter(where status='confirmed'),'overdue',count(*) filter(where status='pending_issue' and planned_issue_date<current_date)) from filtered)));
end $function$;

CREATE OR REPLACE FUNCTION public.smis_list_tool_personal_standard_items_secure(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin
  if (select auth.uid()) is null or not (app_private.is_platform_super() or app_private.has_permission('SmisToolPersonalStandard:View')) then raise exception '当前账号没有查看个人标准明细的权限' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',i.id,'sourceStandardId',s.id,'sourceStandardNo',s.standard_no,'sourceStandardName',s.standard_name,
    'materialId',m.id,'materialCode',m.material_code,'materialName',m.material_name,'categoryName',c.category_name,
    'specificationModel',m.specification_model,'basicUnit',m.basic_unit,'imageUrls',m.image_urls,
    'quotaQuantity',i.quota_quantity,'issuanceCycle',i.issuance_cycle,'issuanceFrequency',i.issuance_frequency,
    'status',i.status,'initialIssueDate',i.initial_issue_date,'lastIssueDate',i.last_issue_date,'nextIssueDate',i.next_issue_date)
    order by c.category_name,m.material_name)
    from public.smis_tool_personal_standard ps
    join public.smis_tool_personal_standard_item i on i.personal_standard_id=ps.id
    join public.smis_tool_issuance_standard s on s.id=i.source_standard_id
    join public.smis_material m on m.id=i.material_id
    join public.smis_material_category c on c.id=m.category_id
    where ps.employee_id=p_employee_id
      and (app_private.current_read_tenant_id() is null or ps.tenant_id=app_private.current_read_tenant_id())), '[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.smis_list_tool_personal_standards_secure(p_from integer DEFAULT 0, p_to integer DEFAULT 19, p_keyword text DEFAULT NULL::text, p_organization_ids uuid[] DEFAULT NULL::uuid[], p_position_id uuid DEFAULT NULL::uuid, p_only_missing boolean DEFAULT false, p_purpose text DEFAULT 'list'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),v_from); v_keyword text:=nullif(btrim(coalesce(p_keyword,'')),'');
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看个人标准' using errcode='42501'; end if;
  if p_purpose='export' and not app_private.has_permission('SmisToolPersonalStandard:Export') then raise exception '当前账号没有导出权限' using errcode='42501'; end if;
  if p_purpose='list' and not (app_private.is_platform_super() or app_private.has_permission('SmisToolPersonalStandard:View')) then raise exception '当前账号没有查看权限' using errcode='42501'; end if;
  return (with filtered as (
    select e.id employee_id,e.employee_no,e.employee_name,e.avatar_url,e.organization_id,e.position_id,o.organization_name,p.position_name,ps.id personal_id,ps.generated_at,ps.status,
      coalesce((select count(*) from public.smis_tool_personal_standard_item i where i.personal_standard_id=ps.id),0) item_count
    from public.hr_employee e left join public.sys_organization o on o.id=e.organization_id left join public.hr_position p on p.id=e.position_id left join public.smis_tool_personal_standard ps on ps.employee_id=e.id and ps.tenant_id=e.tenant_id
    where (app_private.current_read_tenant_id() is null or e.tenant_id=app_private.current_read_tenant_id()) and e.employment_status in ('active','probation')
      and (p_organization_ids is null or e.organization_id=any(p_organization_ids)) and (p_position_id is null or e.position_id=p_position_id) and (not p_only_missing or ps.id is null)
      and (v_keyword is null or e.employee_name ilike '%'||v_keyword||'%' or e.employee_no ilike '%'||v_keyword||'%' or coalesce(p.position_name,'') ilike '%'||v_keyword||'%')
  ), rows as (select employee_id as "employeeId",employee_no as "employeeNo",employee_name as "employeeName",avatar_url as "avatarUrl",organization_id as "organizationId",organization_name as "organizationName",position_id as "positionId",position_name as "positionName",personal_id as "personalStandardId",generated_at as "generatedAt",status,item_count as "itemCount" from filtered order by organization_name,employee_name offset v_from limit v_to-v_from+1)
  select jsonb_build_object('records',coalesce((select jsonb_agg(rows) from rows),'[]'::jsonb),'total',(select count(*) from filtered),'overview',jsonb_build_object('employeeTotal',(select count(*) from filtered),'generatedTotal',(select count(*) from filtered where personal_id is not null),'missingTotal',(select count(*) from filtered where personal_id is null),'itemTotal',(select coalesce(sum(item_count),0) from filtered))));
end $function$;

CREATE OR REPLACE FUNCTION public.smis_list_tool_scope_options_secure(p_kind text, p_keyword text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_keyword text := nullif(btrim(coalesce(p_keyword,'')), '');
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisToolIssuanceStandard:View') or app_private.has_permission('SmisToolIssuanceStandard:Add') or app_private.has_permission('SmisToolIssuanceStandard:Edit') or app_private.has_permission('SmisToolPersonalStandard:View')) then raise exception '当前账号没有查看适用范围的权限' using errcode='42501'; end if;
  if p_kind = 'position' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.position_code,'name',p.position_name,'organizationId',p.organization_id,'organizationName',o.organization_name) order by p.sort,p.position_name)
      from public.hr_position p left join public.sys_organization o on o.id=p.organization_id
      where (app_private.current_read_tenant_id() is null or p.tenant_id=app_private.current_read_tenant_id()) and p.enabled
        and (v_keyword is null or p.position_name ilike '%'||v_keyword||'%' or p.position_code ilike '%'||v_keyword||'%')), '[]'::jsonb);
  elsif p_kind = 'organization' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'parentId',o.parent_id,'code',o.organization_code,'name',o.organization_name,'type',o.organization_type,'sort',o.sort) order by o.sort,o.organization_name)
      from public.sys_organization o where (app_private.current_read_tenant_id() is null or o.tenant_id=app_private.current_read_tenant_id()) and o.status='1'
        and (v_keyword is null or o.organization_name ilike '%'||v_keyword||'%' or o.organization_code ilike '%'||v_keyword||'%')), '[]'::jsonb);
  end if;
  raise exception '适用范围类型无效' using errcode='22023';
end $function$;

CREATE OR REPLACE FUNCTION public.smis_post_tool_issuance_record_secure(p_record_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisToolIssuanceRecord:Issue') then raise exception '当前账号没有发放过账权限' using errcode='42501'; end if;
  if not exists(select 1 from public.smis_tool_issuance_record where id=p_record_id and (app_private.is_platform_super() or tenant_id=app_private.auth_user_tenant_id())) then raise exception '发放记录不存在或不属于当前租户' using errcode='P0002'; end if;
  return app_private.post_tool_issuance_record(p_record_id);
end $function$;

CREATE OR REPLACE FUNCTION public.smis_push_tool_requisition_items_secure(p_items jsonb, p_warehouse_id uuid, p_issuer_employee_id uuid, p_issue_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tenant uuid; v_employee uuid; v_record_id uuid; v_no text; v_employee_row record; v_warehouse record; v_issuer record; v_item_ids uuid[];
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisToolPersonalRequisition:Push') then raise exception '当前账号没有下推发放的权限' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception '请选择待发放的领用明细' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) x where nullif(x->>'id','') is null or coalesce((x->>'issue_quantity')::numeric,0)<=0) then raise exception '领用明细或发放数量无效' using errcode='22023'; end if;
  select array_agg((x->>'id')::uuid) into v_item_ids from jsonb_array_elements(p_items) x;
  if cardinality(v_item_ids)<>jsonb_array_length(p_items) or cardinality(v_item_ids)<>(select count(distinct id) from unnest(v_item_ids) id) then raise exception '领用明细不能重复' using errcode='22023'; end if;
  select min(r.tenant_id),min(r.employee_id) into v_tenant,v_employee from public.smis_tool_personal_requisition_item i join public.smis_tool_personal_requisition r on r.id=i.requisition_id where i.id=any(v_item_ids) and i.status='pending_issue';
  if v_tenant is null or (select count(*) from public.smis_tool_personal_requisition_item where id=any(v_item_ids))<>cardinality(v_item_ids)
    or exists(select 1 from public.smis_tool_personal_requisition_item i join public.smis_tool_personal_requisition r on r.id=i.requisition_id where i.id=any(v_item_ids) and (r.tenant_id<>v_tenant or r.employee_id<>v_employee or i.status<>'pending_issue')) then raise exception '只能选择同一领用人的待发放明细' using errcode='22023'; end if;
  if not app_private.is_platform_super() and v_tenant<>app_private.auth_user_tenant_id() then raise exception '所选数据不属于当前租户' using errcode='42501'; end if;
  select e.*,o.organization_name,p.position_name into v_employee_row from public.hr_employee e left join public.sys_organization o on o.id=e.organization_id left join public.hr_position p on p.id=e.position_id where e.id=v_employee and e.tenant_id=v_tenant;
  select * into v_warehouse from public.smis_storage_location where id=p_warehouse_id and tenant_id=v_tenant and status='enabled';
  select * into v_issuer from public.hr_employee where id=p_issuer_employee_id and tenant_id=v_tenant;
  if v_employee_row.id is null or v_warehouse.id is null or v_issuer.id is null then raise exception '领用人、发放仓库或发放人无效' using errcode='P0002'; end if;
  insert into public.smis_tool_issuance_record(tenant_id,issuance_no,employee_id,employee_no_snapshot,employee_name_snapshot,position_name_snapshot,organization_id,organization_name_snapshot,warehouse_id,warehouse_name_snapshot,issuer_employee_id,issuer_name_snapshot,issue_date,status)
  values(v_tenant,app_private.next_document_number('smis.tool_issuance_record',v_tenant),v_employee_row.id,v_employee_row.employee_no,v_employee_row.employee_name,v_employee_row.position_name,v_employee_row.organization_id,v_employee_row.organization_name,v_warehouse.id,v_warehouse.location_name,v_issuer.id,v_issuer.employee_name,coalesce(p_issue_date,current_date),'draft') returning id into v_record_id;
  insert into public.smis_tool_issuance_record_item(tenant_id,issuance_record_id,requisition_item_id,material_id,material_category_snapshot,material_name_snapshot,specification_model_snapshot,unit_snapshot,issue_quantity)
  select v_tenant,v_record_id,i.id,i.material_id,i.material_category_snapshot,i.material_name_snapshot,i.specification_model_snapshot,i.unit_snapshot,(x->>'issue_quantity')::numeric
  from jsonb_array_elements(p_items) x join public.smis_tool_personal_requisition_item i on i.id=(x->>'id')::uuid;
  v_no:=app_private.post_tool_issuance_record(v_record_id);
  return jsonb_build_object('id',v_record_id,'issuanceNo',v_no);
end $function$;

CREATE OR REPLACE FUNCTION public.smis_save_tool_issuance_record_secure(p_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tenant uuid; v_id uuid; v_employee record; v_warehouse record; v_issuer record; v_item jsonb; v_material record;
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if p_id is null and not (
    app_private.has_permission('SmisToolIssuanceRecord:Add')
    or app_private.has_permission('SmisToolIssuanceRecord:Copy')
    or app_private.has_permission('SmisToolIssuanceRecord:Import')
  ) then raise exception '当前账号没有新增、复制或导入发放记录的权限' using errcode='42501'; end if;
  if p_id is not null and not app_private.has_permission('SmisToolIssuanceRecord:Edit') then raise exception '当前账号没有编辑发放记录的权限' using errcode='42501'; end if;
  v_tenant:=app_private.resolve_mutation_tenant_id((select tenant_id from public.smis_tool_issuance_record where id=p_id));
  select e.*,o.organization_name,p.position_name into v_employee from public.hr_employee e left join public.sys_organization o on o.id=e.organization_id left join public.hr_position p on p.id=e.position_id where e.id=(p_payload->>'employee_id')::uuid and e.tenant_id=v_tenant;
  select * into v_warehouse from public.smis_storage_location where id=(p_payload->>'warehouse_id')::uuid and tenant_id=v_tenant and status='enabled';
  select * into v_issuer from public.hr_employee where id=(p_payload->>'issuer_employee_id')::uuid and tenant_id=v_tenant;
  if v_employee.id is null or v_warehouse.id is null or v_issuer.id is null then raise exception '领用人、发放仓库或发放人无效' using errcode='P0002'; end if;
  if jsonb_array_length(coalesce(p_payload->'items','[]'::jsonb))=0 then raise exception '请至少添加一条发放明细' using errcode='22023'; end if;
  if p_id is null then
    insert into public.smis_tool_issuance_record(tenant_id,issuance_no,employee_id,employee_no_snapshot,employee_name_snapshot,position_name_snapshot,organization_id,organization_name_snapshot,warehouse_id,warehouse_name_snapshot,issuer_employee_id,issuer_name_snapshot,issue_date,status,remark)
    values(v_tenant,app_private.next_document_number('smis.tool_issuance_record',v_tenant),v_employee.id,v_employee.employee_no,v_employee.employee_name,v_employee.position_name,v_employee.organization_id,v_employee.organization_name,v_warehouse.id,v_warehouse.location_name,v_issuer.id,v_issuer.employee_name,coalesce((p_payload->>'issue_date')::date,current_date),'draft',nullif(btrim(coalesce(p_payload->>'remark','')),'')) returning id into v_id;
  else
    if not exists(select 1 from public.smis_tool_issuance_record where id=p_id and tenant_id=v_tenant and status='draft') then raise exception '仅草稿状态允许编辑' using errcode='P0001'; end if;
    update public.smis_tool_issuance_record set employee_id=v_employee.id,employee_no_snapshot=v_employee.employee_no,employee_name_snapshot=v_employee.employee_name,position_name_snapshot=v_employee.position_name,organization_id=v_employee.organization_id,organization_name_snapshot=v_employee.organization_name,warehouse_id=v_warehouse.id,warehouse_name_snapshot=v_warehouse.location_name,issuer_employee_id=v_issuer.id,issuer_name_snapshot=v_issuer.employee_name,issue_date=coalesce((p_payload->>'issue_date')::date,current_date),remark=nullif(btrim(coalesce(p_payload->>'remark','')),'') where id=p_id returning id into v_id;
    delete from public.smis_tool_issuance_record_item where issuance_record_id=v_id;
  end if;
  for v_item in select value from jsonb_array_elements(p_payload->'items') loop
    select m.*,c.category_name into v_material from public.smis_material m join public.smis_material_category c on c.id=m.category_id where m.id=(v_item->>'material_id')::uuid and m.tenant_id=v_tenant and m.material_type='tool';
    if v_material.id is null then raise exception '发放明细中的工器具无效' using errcode='P0002'; end if;
    insert into public.smis_tool_issuance_record_item(tenant_id,issuance_record_id,requisition_item_id,material_id,material_category_snapshot,material_name_snapshot,specification_model_snapshot,unit_snapshot,issue_quantity,remark)
    values(v_tenant,v_id,nullif(v_item->>'requisition_item_id','')::uuid,v_material.id,v_material.category_name,v_material.material_name,v_material.specification_model,v_material.basic_unit,(v_item->>'issue_quantity')::numeric,nullif(btrim(coalesce(v_item->>'remark','')),''));
  end loop;
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.smis_save_tool_issuance_standard_secure(p_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tenant uuid; v_id uuid; v_standard_no text:=nullif(btrim(coalesce(p_payload->>'standard_no','')),''); v_name text:=btrim(coalesce(p_payload->>'standard_name','')); v_positions jsonb:=coalesce(p_payload->'position_ids','[]'); v_orgs jsonb:=coalesce(p_payload->'organization_ids','[]'); v_details jsonb:=coalesce(p_payload->'details','[]'); v_detail jsonb; v_material uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护发放标准' using errcode='42501'; end if;
  if p_id is null and not app_private.has_permission('SmisToolIssuanceStandard:Add') then raise exception '当前账号没有新增权限' using errcode='42501'; end if;
  if p_id is not null and not app_private.has_permission('SmisToolIssuanceStandard:Edit') then raise exception '当前账号没有编辑权限' using errcode='42501'; end if;
  v_tenant:=app_private.resolve_mutation_tenant_id((select tenant_id from public.smis_tool_issuance_standard where id=p_id)); if v_tenant is null then raise exception '当前账号未绑定有效租户' using errcode='42501'; end if;
  if v_name='' then raise exception '请输入发放标准名称' using errcode='22023'; end if;
  if jsonb_typeof(v_positions)<>'array' or jsonb_typeof(v_orgs)<>'array' or jsonb_typeof(v_details)<>'array' then raise exception '发放标准数据格式无效' using errcode='22023'; end if;
  if jsonb_array_length(v_positions)=0 and jsonb_array_length(v_orgs)=0 then raise exception '适用岗位和适用公司/部门至少选择一项' using errcode='22023'; end if;
  if jsonb_array_length(v_details)=0 then raise exception '请至少添加一条工器具明细' using errcode='22023'; end if;
  if p_id is null and v_standard_no is null then v_standard_no:=app_private.next_document_number('smis.tool_issuance_standard',v_tenant); end if;
  if v_standard_no is null then raise exception '标准编号生成失败，请检查编号规则' using errcode='22023'; end if;
  if not app_private.is_enabled_dictionary_value('smisToolIssuanceCycle',p_payload->>'issuance_cycle') then raise exception '发放周期无效' using errcode='22023'; end if;
  if p_id is null then insert into public.smis_tool_issuance_standard(tenant_id,standard_no,standard_name,rated_quantity,issuance_cycle,issuance_frequency,status,description) values(v_tenant,v_standard_no,v_name,(p_payload->>'rated_quantity')::numeric,p_payload->>'issuance_cycle',(p_payload->>'issuance_frequency')::integer,coalesce(p_payload->>'status','enabled'),nullif(btrim(p_payload->>'description'),'')) returning id into v_id;
  else update public.smis_tool_issuance_standard set standard_name=v_name,rated_quantity=(p_payload->>'rated_quantity')::numeric,issuance_cycle=p_payload->>'issuance_cycle',issuance_frequency=(p_payload->>'issuance_frequency')::integer,status=coalesce(p_payload->>'status','enabled'),description=nullif(btrim(p_payload->>'description'),'') where id=p_id and tenant_id=v_tenant returning id into v_id; if v_id is null then raise exception '发放标准不存在或已删除' using errcode='P0002'; end if; end if;
  delete from public.smis_tool_issuance_standard_position where standard_id=v_id;
  insert into public.smis_tool_issuance_standard_position(standard_id,position_id,tenant_id) select v_id,value::uuid,v_tenant from jsonb_array_elements_text(v_positions);
  delete from public.smis_tool_issuance_standard_organization where standard_id=v_id;
  insert into public.smis_tool_issuance_standard_organization(standard_id,organization_id,tenant_id) select v_id,value::uuid,v_tenant from jsonb_array_elements_text(v_orgs);
  delete from public.smis_tool_issuance_standard_detail where standard_id=v_id;
  for v_detail in select value from jsonb_array_elements(v_details) loop
    v_material:=(v_detail->>'material_id')::uuid;
    if not exists(select 1 from public.smis_material where id=v_material and tenant_id=v_tenant and material_type='tool' and status='enabled') then raise exception '所选工器具不存在、已停用或不属于当前租户' using errcode='P0002'; end if;
    insert into public.smis_tool_issuance_standard_detail(tenant_id,standard_id,material_id,quota_quantity,issuance_cycle,issuance_frequency,status,remark,sort) values(v_tenant,v_id,v_material,(v_detail->>'quota_quantity')::numeric,v_detail->>'issuance_cycle',(v_detail->>'issuance_frequency')::integer,coalesce(v_detail->>'status','enabled'),nullif(btrim(v_detail->>'remark'),''),coalesce((v_detail->>'sort')::integer,10));
  end loop;
  return v_id;
exception when unique_violation then raise exception '标准编号或明细物料重复，请检查后重试' using errcode='23505';
end $function$;

CREATE OR REPLACE FUNCTION public.smis_save_tool_setting_secure(p_auto_confirm_days integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tenant uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if not app_private.has_permission('SmisToolPersonalRequisition:Configure') then raise exception '当前账号没有配置自动确认规则的权限' using errcode='42501'; end if;
  if p_auto_confirm_days not between 1 and 30 then raise exception '自动确认天数必须在 1 至 30 天之间' using errcode='22023'; end if;
  v_tenant := app_private.auth_user_tenant_id();
  insert into public.smis_tool_setting(tenant_id,auto_confirm_days) values(v_tenant,p_auto_confirm_days)
  on conflict(tenant_id) do update set auto_confirm_days=excluded.auto_confirm_days;
  return p_auto_confirm_days;
end $function$;

CREATE OR REPLACE FUNCTION public.smis_set_tool_personal_issue_plan_secure(p_employee_id uuid, p_items jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_item jsonb; v_count integer := 0;
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisToolPersonalStandard:Schedule') then raise exception '当前账号没有设置个人领用计划的权限' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array' then raise exception '领用计划格式无效' using errcode='22023'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    update public.smis_tool_personal_standard_item i set
      initial_issue_date=(v_item->>'initial_issue_date')::date,
      next_issue_date=(v_item->>'next_issue_date')::date,
      issuance_cycle=coalesce(v_item->>'issuance_cycle',i.issuance_cycle),
      issuance_frequency=coalesce((v_item->>'issuance_frequency')::integer,i.issuance_frequency)
    from public.smis_tool_personal_standard ps
    where i.id=(v_item->>'id')::uuid and ps.id=i.personal_standard_id
      and ps.employee_id=p_employee_id
      and (app_private.is_platform_super() or i.tenant_id=app_private.auth_user_tenant_id());
    v_count := v_count + 1;
  end loop;
  return v_count;
end $function$;

revoke all on function public.smis_confirm_tool_requisition_items_secure(p_item_ids uuid[], p_confirmed boolean, p_reason text) from public, anon;
grant execute on function public.smis_confirm_tool_requisition_items_secure(p_item_ids uuid[], p_confirmed boolean, p_reason text) to authenticated;
revoke all on function public.smis_delete_tool_issuance_records_secure(p_ids uuid[]) from public, anon;
grant execute on function public.smis_delete_tool_issuance_records_secure(p_ids uuid[]) to authenticated;
revoke all on function public.smis_delete_tool_issuance_standards_secure(p_ids uuid[]) from public, anon;
grant execute on function public.smis_delete_tool_issuance_standards_secure(p_ids uuid[]) to authenticated;
revoke all on function public.smis_generate_due_tool_requisitions_secure(p_due_date date) from public, anon;
grant execute on function public.smis_generate_due_tool_requisitions_secure(p_due_date date) to authenticated;
revoke all on function public.smis_generate_tool_personal_standards_secure(p_employee_ids uuid[]) from public, anon;
grant execute on function public.smis_generate_tool_personal_standards_secure(p_employee_ids uuid[]) to authenticated;
revoke all on function public.smis_get_tool_issuance_statistics_secure(p_date_from date, p_date_to date, p_organization_id uuid, p_employee_id uuid) from public, anon;
grant execute on function public.smis_get_tool_issuance_statistics_secure(p_date_from date, p_date_to date, p_organization_id uuid, p_employee_id uuid) to authenticated;
revoke all on function public.smis_get_tool_setting_secure() from public, anon;
grant execute on function public.smis_get_tool_setting_secure() to authenticated;
revoke all on function public.smis_list_tool_issuance_records_secure(p_from integer, p_to integer, p_date_from date, p_date_to date, p_organization_id uuid, p_employee_id uuid, p_status text, p_keyword text, p_purpose text) from public, anon;
grant execute on function public.smis_list_tool_issuance_records_secure(p_from integer, p_to integer, p_date_from date, p_date_to date, p_organization_id uuid, p_employee_id uuid, p_status text, p_keyword text, p_purpose text) to authenticated;
revoke all on function public.smis_list_tool_issuance_standards_secure(p_from integer, p_to integer, p_keyword text, p_status text, p_purpose text) from public, anon;
grant execute on function public.smis_list_tool_issuance_standards_secure(p_from integer, p_to integer, p_keyword text, p_status text, p_purpose text) to authenticated;
revoke all on function public.smis_list_tool_personal_requisitions_secure(p_from integer, p_to integer, p_date_from date, p_date_to date, p_organization_id uuid, p_employee_id uuid, p_status text, p_keyword text, p_purpose text) from public, anon;
grant execute on function public.smis_list_tool_personal_requisitions_secure(p_from integer, p_to integer, p_date_from date, p_date_to date, p_organization_id uuid, p_employee_id uuid, p_status text, p_keyword text, p_purpose text) to authenticated;
revoke all on function public.smis_list_tool_personal_standard_items_secure(p_employee_id uuid) from public, anon;
grant execute on function public.smis_list_tool_personal_standard_items_secure(p_employee_id uuid) to authenticated;
revoke all on function public.smis_list_tool_personal_standards_secure(p_from integer, p_to integer, p_keyword text, p_organization_ids uuid[], p_position_id uuid, p_only_missing boolean, p_purpose text) from public, anon;
grant execute on function public.smis_list_tool_personal_standards_secure(p_from integer, p_to integer, p_keyword text, p_organization_ids uuid[], p_position_id uuid, p_only_missing boolean, p_purpose text) to authenticated;
revoke all on function public.smis_list_tool_scope_options_secure(p_kind text, p_keyword text) from public, anon;
grant execute on function public.smis_list_tool_scope_options_secure(p_kind text, p_keyword text) to authenticated;
revoke all on function public.smis_post_tool_issuance_record_secure(p_record_id uuid) from public, anon;
grant execute on function public.smis_post_tool_issuance_record_secure(p_record_id uuid) to authenticated;
revoke all on function public.smis_push_tool_requisition_items_secure(p_items jsonb, p_warehouse_id uuid, p_issuer_employee_id uuid, p_issue_date date) from public, anon;
grant execute on function public.smis_push_tool_requisition_items_secure(p_items jsonb, p_warehouse_id uuid, p_issuer_employee_id uuid, p_issue_date date) to authenticated;
revoke all on function public.smis_save_tool_issuance_record_secure(p_id uuid, p_payload jsonb) from public, anon;
grant execute on function public.smis_save_tool_issuance_record_secure(p_id uuid, p_payload jsonb) to authenticated;
revoke all on function public.smis_save_tool_issuance_standard_secure(p_id uuid, p_payload jsonb) from public, anon;
grant execute on function public.smis_save_tool_issuance_standard_secure(p_id uuid, p_payload jsonb) to authenticated;
revoke all on function public.smis_save_tool_setting_secure(p_auto_confirm_days integer) from public, anon;
grant execute on function public.smis_save_tool_setting_secure(p_auto_confirm_days integer) to authenticated;
revoke all on function public.smis_set_tool_personal_issue_plan_secure(p_employee_id uuid, p_items jsonb) from public, anon;
grant execute on function public.smis_set_tool_personal_issue_plan_secure(p_employee_id uuid, p_items jsonb) to authenticated;

revoke insert, update, delete on table public.smis_tool_issuance_record from authenticated;
revoke insert, update, delete on table public.smis_tool_issuance_record_item from authenticated;
revoke insert, update, delete on table public.smis_tool_issuance_standard from authenticated;
revoke insert, update, delete on table public.smis_tool_issuance_standard_detail from authenticated;
revoke insert, update, delete on table public.smis_tool_issuance_standard_organization from authenticated;
revoke insert, update, delete on table public.smis_tool_issuance_standard_position from authenticated;
revoke insert, update, delete on table public.smis_tool_personal_requisition from authenticated;
revoke insert, update, delete on table public.smis_tool_personal_requisition_item from authenticated;
revoke insert, update, delete on table public.smis_tool_personal_standard from authenticated;
revoke insert, update, delete on table public.smis_tool_personal_standard_item from authenticated;
revoke insert, update, delete on table public.smis_tool_setting from authenticated;

grant select on table public.smis_tool_issuance_record to authenticated;
grant select on table public.smis_tool_issuance_record_item to authenticated;
grant select on table public.smis_tool_issuance_standard to authenticated;
grant select on table public.smis_tool_issuance_standard_detail to authenticated;
grant select on table public.smis_tool_issuance_standard_organization to authenticated;
grant select on table public.smis_tool_issuance_standard_position to authenticated;
grant select on table public.smis_tool_personal_requisition to authenticated;
grant select on table public.smis_tool_personal_requisition_item to authenticated;
grant select on table public.smis_tool_personal_standard to authenticated;
grant select on table public.smis_tool_personal_standard_item to authenticated;
grant select on table public.smis_tool_setting to authenticated;

do $cron$
begin
  if exists (select 1 from cron.job where jobname = 'smis-tool-daily-requisition-and-confirmation') then
    perform cron.unschedule('smis-tool-daily-requisition-and-confirmation');
  end if;
  perform cron.schedule(
    'smis-tool-daily-requisition-and-confirmation',
    '20 16 * * *',
    'select app_private.run_daily_tool_automation();'
  );
end
$cron$;

-- 工器具字典、编号场景和可分配按钮权限。
with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_parent as (
  select parent_id from public.sys_dict_type where code = 'smisPpeIssuanceCycle' limit 1
), definitions(name, code, sort, remark) as (
  values
    ('工器具发放周期', 'smisToolIssuanceCycle', 50, '工器具标准发放周期'),
    ('工器具领用状态', 'smisToolRequisitionStatus', 51, '工器具个人领用状态'),
    ('工器具发放状态', 'smisToolIssuanceStatus', 52, '工器具发放单状态'),
    ('工器具归还审批状态', 'smisToolReturnStatus', 53, '工器具归还审批状态')
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), d.name, d.code, '1', '624944977@qq.com', '624944977@qq.com',
       d.remark, p.id, dp.parent_id, 'dictionary', d.sort
from definitions d cross join platform_tenant p cross join dictionary_parent dp
on conflict (code) do update
set name = excluded.name, status = '1', remark = excluded.remark, update_by = excluded.update_by;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, suffix, value, label, sort, tag_type) as (
  values
    ('smisToolIssuanceCycle','day','day','天',1,'info'),
    ('smisToolIssuanceCycle','week','week','周',2,'info'),
    ('smisToolIssuanceCycle','month','month','月',3,'info'),
    ('smisToolIssuanceCycle','half_year','half_year','半年',4,'info'),
    ('smisToolIssuanceCycle','quarter','quarter','季',5,'info'),
    ('smisToolIssuanceCycle','year','year','年',6,'info'),
    ('smisToolRequisitionStatus','pending_issue','pending_issue','待发放',1,'warning'),
    ('smisToolRequisitionStatus','issued_pending_confirmation','issued_pending_confirmation','待本人确认',2,'primary'),
    ('smisToolRequisitionStatus','confirmed','confirmed','已确认',3,'success'),
    ('smisToolRequisitionStatus','denied','denied','已否认',4,'danger'),
    ('smisToolRequisitionStatus','cancelled','cancelled','已取消',5,'info'),
    ('smisToolIssuanceStatus','draft','draft','草稿',1,'warning'),
    ('smisToolIssuanceStatus','posted','posted','已过账',2,'success'),
    ('smisToolIssuanceStatus','voided','voided','已作废',3,'info'),
    ('smisToolReturnStatus','draft','draft','草稿',1,'info'),
    ('smisToolReturnStatus','pending_approval','pending_approval','审批中',2,'warning'),
    ('smisToolReturnStatus','approved','approved','已通过',3,'success'),
    ('smisToolReturnStatus','rejected','rejected','已驳回',4,'danger')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, value, label, i18n_scope,
  sort, tenant_id, tag_type
)
select gen_random_uuid(), t.id, i.type_code || '_' || i.suffix, '1',
       '624944977@qq.com', '624944977@qq.com', i.value, i.label, '1',
       i.sort, p.id, i.tag_type
from items i
join public.sys_dict_type t on t.code = i.type_code
cross join platform_tenant p
where not exists (
  select 1 from public.sys_dictionary d where d.code = i.type_code || '_' || i.suffix
);

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), scenes(rule_key, rule_name, field_label, category, menu_name, target_table, target_column,
          template, reset_cycle, remark) as (
  values
    ('smis.tool_issuance_standard','工器具发放标准编号','标准编号','master_data',
     'SmisToolIssuanceStandard','smis_tool_issuance_standard','standard_no',
     'GJBZ{YYYY}-{SEQ:3}','year','保存时自动生成 3 位流水码'),
    ('smis.tool_personal_requisition','工器具个人领用单号','个人领用单号','business_document',
     'SmisToolPersonalRequisition','smis_tool_personal_requisition','requisition_no',
     'GLY{YYYYMM}{SEQ:4}','month','系统按标准到期生成，4 位流水码每月重置'),
    ('smis.tool_issuance_record','工器具发放单号','发放单号','business_document',
     'SmisToolIssuanceRecord','smis_tool_issuance_record','issuance_no',
     'GFF{YYYYMM}{SEQ:4}','month','发放过账生成，4 位流水码每月重置'),
    ('smis.tool_return','工器具归还单号','归还单号','business_document',
     'SmisToolRequisitionReturn','smis_tool_return','return_no',
     'GH{YYYYMM}{SEQ:4}','month','归还单生成，4 位流水码每月重置')
)
insert into public.sys_document_number_scene(
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark,
  create_by, update_by, tenant_id
)
select s.rule_key, s.rule_name, s.field_label, s.category, m.id, s.target_table, s.target_column,
       s.template, s.reset_cycle, false, true, s.remark,
       '624944977@qq.com', '624944977@qq.com', p.id
from scenes s
join public.sys_menu m on m.name = s.menu_name
cross join platform_tenant p
on conflict (rule_key) do update
set rule_name = excluded.rule_name, menu_id = excluded.menu_id,
    target_table = excluded.target_table, target_column = excluded.target_column,
    default_template = excluded.default_template, default_reset_cycle = excluded.default_reset_cycle,
    enabled = true, update_by = excluded.update_by;

with definitions(rule_key, rule_name, category, target_table, target_column, template,
                 reset_cycle, remark) as (
  values
    ('smis.tool_issuance_standard','工器具发放标准编号','master_data',
     'smis_tool_issuance_standard','standard_no','GJBZ{YYYY}-{SEQ:3}','year','保存时自动生成 3 位流水码'),
    ('smis.tool_personal_requisition','工器具个人领用单号','business_document',
     'smis_tool_personal_requisition','requisition_no','GLY{YYYYMM}{SEQ:4}','month','系统按标准到期生成，4 位流水码每月重置'),
    ('smis.tool_issuance_record','工器具发放单号','business_document',
     'smis_tool_issuance_record','issuance_no','GFF{YYYYMM}{SEQ:4}','month','发放过账生成，4 位流水码每月重置'),
    ('smis.tool_return','工器具归还单号','business_document',
     'smis_tool_return','return_no','GH{YYYYMM}{SEQ:4}','month','归还单生成，4 位流水码每月重置')
)
insert into public.sys_document_number_rule(
  id, tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone, rule_version,
  manual_required, builtin, enabled, remark, create_by, update_by
)
select gen_random_uuid(), t.id, d.rule_key, d.rule_name, d.category, d.target_table, d.target_column,
       true, d.template, d.reset_cycle, 1, 'Asia/Shanghai', 1,
       false, true, true, d.remark, '624944977@qq.com', '624944977@qq.com'
from public.sys_tenant t cross join definitions d
on conflict (tenant_id, rule_key) do update
set rule_name = excluded.rule_name, target_table = excluded.target_table,
    target_column = excluded.target_column, auto_enabled = true, template = excluded.template,
    reset_cycle = excluded.reset_cycle, manual_required = false, enabled = true,
    remark = excluded.remark, update_by = excluded.update_by,
    rule_version = public.sys_document_number_rule.rule_version + 1;

with buttons(menu_name, code, title, sort) as (
  values
    ('SmisToolIssuanceStandard','SmisToolIssuanceStandard:View','查看发放标准',1),
    ('SmisToolIssuanceStandard','SmisToolIssuanceStandard:Add','新增发放标准',2),
    ('SmisToolIssuanceStandard','SmisToolIssuanceStandard:Edit','编辑发放标准',3),
    ('SmisToolIssuanceStandard','SmisToolIssuanceStandard:Delete','删除发放标准',4),
    ('SmisToolIssuanceStandard','SmisToolIssuanceStandard:Export','导出发放标准',5),
    ('SmisToolPersonalStandard','SmisToolPersonalStandard:View','查看个人标准',1),
    ('SmisToolPersonalStandard','SmisToolPersonalStandard:Generate','生成个人标准',2),
    ('SmisToolPersonalStandard','SmisToolPersonalStandard:Export','导出个人标准',3),
    ('SmisToolPersonalStandard','SmisToolPersonalStandard:Schedule','设置领用计划',4),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:View','查看发放记录',1),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:Add','新增发放记录',2),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:Copy','复制并新增',3),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:Edit','编辑发放记录',4),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:Delete','删除发放记录',5),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:Issue','发放过账',6),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:Import','导入发放记录',7),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:DownloadTemplate','下载导入模板',8),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:Export','导出发放记录',9),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:Statistics','发放统计分析',10),
    ('SmisToolIssuanceRecord','SmisToolIssuanceRecord:Print','打印工器具发放单',11),
    ('SmisToolPersonalRequisition','SmisToolPersonalRequisition:View','查看个人领用',1),
    ('SmisToolPersonalRequisition','SmisToolPersonalRequisition:Generate','生成到期领用单',2),
    ('SmisToolPersonalRequisition','SmisToolPersonalRequisition:Push','下推发放',3),
    ('SmisToolPersonalRequisition','SmisToolPersonalRequisition:Confirm','确认本人领用',4),
    ('SmisToolPersonalRequisition','SmisToolPersonalRequisition:Export','导出个人领用',5),
    ('SmisToolPersonalRequisition','SmisToolPersonalRequisition:Statistics','个人领用统计',6),
    ('SmisToolPersonalRequisition','SmisToolPersonalRequisition:Configure','配置自动确认',7),
    ('SmisToolRequisitionReturn','SmisToolRequisitionReturn:View','查看归还单',1),
    ('SmisToolRequisitionReturn','SmisToolRequisitionReturn:Add','新增归还单',2),
    ('SmisToolRequisitionReturn','SmisToolRequisitionReturn:Copy','复制并新增',3),
    ('SmisToolRequisitionReturn','SmisToolRequisitionReturn:Edit','编辑归还单',4),
    ('SmisToolRequisitionReturn','SmisToolRequisitionReturn:Delete','删除归还单',5),
    ('SmisToolRequisitionReturn','SmisToolRequisitionReturn:Return','发起归还',6),
    ('SmisToolRequisitionReturn','SmisToolRequisitionReturn:Submit','提交归还审批',7),
    ('SmisToolRequisitionReturn','SmisToolRequisitionReturn:Export','导出归还单',8)
)
insert into public.sys_menu(
  id, parent_id, name, path, component, type, meta, sort,
  create_by, update_by, app_code
)
select gen_random_uuid(), parent.id, b.code, '', '', 'button',
       jsonb_build_object('title', b.title, 'is_hide', true, 'is_enable', true, 'roles', '[]'::jsonb),
       b.sort, '624944977@qq.com', '624944977@qq.com', 'smis'
from buttons b join public.sys_menu parent on parent.name = b.menu_name
where not exists (select 1 from public.sys_menu existing where existing.name = b.code);

insert into public.sys_role_menu(role_id, menu_id, tenant_id, create_by, update_by)
select distinct parent_grant.role_id, child.id, parent_grant.tenant_id,
       '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu parent_grant
join public.sys_menu parent on parent.id = parent_grant.menu_id
join public.sys_menu child on child.parent_id = parent.id and child.type = 'button'
where parent.name in (
  'SmisToolIssuanceStandard','SmisToolPersonalStandard','SmisToolIssuanceRecord',
  'SmisToolPersonalRequisition','SmisToolRequisitionReturn'
)
on conflict (role_id, menu_id) do nothing;

create index if not exists smis_tool_return_scope_idx
  on public.smis_tool_return(tenant_id, return_date desc, status, employee_id);
create index if not exists smis_tool_return_employee_fk_idx
  on public.smis_tool_return(employee_id);
create index if not exists smis_tool_return_org_fk_idx
  on public.smis_tool_return(organization_id);
create index if not exists smis_tool_return_item_parent_idx
  on public.smis_tool_return_item(return_id);
create index if not exists smis_tool_return_item_source_idx
  on public.smis_tool_return_item(source_issuance_item_id);
create index if not exists smis_tool_return_item_material_idx
  on public.smis_tool_return_item(material_id);

alter table public.smis_tool_return enable row level security;
alter table public.smis_tool_return_item enable row level security;

drop policy if exists smis_tool_return_tenant_select on public.smis_tool_return;
create policy smis_tool_return_tenant_select on public.smis_tool_return
for select to authenticated
using (
  app_private.is_platform_super()
  or tenant_id = app_private.current_user_tenant_id()
);

drop policy if exists smis_tool_return_item_tenant_select on public.smis_tool_return_item;
create policy smis_tool_return_item_tenant_select on public.smis_tool_return_item
for select to authenticated
using (
  app_private.is_platform_super()
  or tenant_id = app_private.current_user_tenant_id()
);

drop trigger if exists smis_tool_return_create_audit on public.smis_tool_return;
create trigger smis_tool_return_create_audit
before insert on public.smis_tool_return
for each row execute function public.trg_set_create_time_and_by('true','true');

drop trigger if exists smis_tool_return_update_audit on public.smis_tool_return;
create trigger smis_tool_return_update_audit
before update on public.smis_tool_return
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists smis_tool_return_item_create_audit on public.smis_tool_return_item;
create trigger smis_tool_return_item_create_audit
before insert on public.smis_tool_return_item
for each row execute function public.trg_set_create_time_and_by('true','true');

drop trigger if exists smis_tool_return_item_update_audit on public.smis_tool_return_item;
create trigger smis_tool_return_item_update_audit
before update on public.smis_tool_return_item
for each row execute function public.trg_set_update_time_and_by();

grant select on public.smis_tool_return, public.smis_tool_return_item to authenticated;

create or replace function public.smis_list_tool_returnable_items_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_employee_id uuid default null,
  p_keyword text default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_tenant uuid := app_private.auth_user_tenant_id();
  v_result jsonb;
begin
  if auth.uid() is null or not app_private.has_permission('SmisToolRequisitionReturn:View') then
    raise exception '当前账号没有查看可归还工器具的权限' using errcode = '42501';
  end if;

  with source_rows as (
    select
      item.id,
      record.id as issuance_record_id,
      record.issuance_no,
      record.employee_id,
      record.employee_no_snapshot,
      record.employee_name_snapshot,
      record.position_name_snapshot,
      record.organization_id,
      record.organization_name_snapshot,
      record.issue_date,
      item.material_id,
      item.material_category_snapshot,
      item.material_name_snapshot,
      item.specification_model_snapshot,
      item.unit_snapshot,
      item.issue_quantity,
      greatest(
        item.issue_quantity - coalesce((
          select sum(return_item.return_quantity)
          from public.smis_tool_return_item return_item
          join public.smis_tool_return return_order on return_order.id = return_item.return_id
          where return_item.source_issuance_item_id = item.id
            and return_order.status in ('draft','pending_approval','approved')
        ), 0),
        0
      ) as returnable_quantity
    from public.smis_tool_issuance_record_item item
    join public.smis_tool_issuance_record record on record.id = item.issuance_record_id
    where record.status = 'posted'
      and (app_private.is_platform_super() or record.tenant_id = v_tenant)
      and (p_employee_id is null or record.employee_id = p_employee_id)
  ), filtered as (
    select * from source_rows s
    where s.returnable_quantity > 0
      and (
        nullif(btrim(coalesce(p_keyword,'')), '') is null
        or s.issuance_no ilike '%' || btrim(p_keyword) || '%'
        or s.employee_name_snapshot ilike '%' || btrim(p_keyword) || '%'
        or s.employee_no_snapshot ilike '%' || btrim(p_keyword) || '%'
        or s.material_name_snapshot ilike '%' || btrim(p_keyword) || '%'
      )
  ), page_rows as (
    select * from filtered
    order by issue_date desc, issuance_no desc, material_name_snapshot
    offset greatest(coalesce(p_from,0),0)
    limit case when p_purpose = 'export' then 10000
               else greatest(coalesce(p_to,19) - greatest(coalesce(p_from,0),0) + 1, 1) end
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'issuanceRecordId', p.issuance_record_id,
        'issuanceNo', p.issuance_no,
        'employeeId', p.employee_id,
        'employeeNo', p.employee_no_snapshot,
        'employeeName', p.employee_name_snapshot,
        'positionName', p.position_name_snapshot,
        'organizationId', p.organization_id,
        'organizationName', p.organization_name_snapshot,
        'issueDate', p.issue_date,
        'materialId', p.material_id,
        'materialCategory', p.material_category_snapshot,
        'materialName', p.material_name_snapshot,
        'specificationModel', p.specification_model_snapshot,
        'unit', p.unit_snapshot,
        'issuedQuantity', p.issue_quantity,
        'returnableQuantity', p.returnable_quantity
      ) order by p.issue_date desc, p.issuance_no desc, p.material_name_snapshot)
      from page_rows p
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;
  return v_result;
end
$function$;

create or replace function public.smis_list_tool_returns_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_date_from date default null,
  p_date_to date default null,
  p_employee_id uuid default null,
  p_status text default null,
  p_keyword text default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_tenant uuid := app_private.auth_user_tenant_id();
  v_result jsonb;
begin
  if auth.uid() is null or not app_private.has_permission('SmisToolRequisitionReturn:View') then
    raise exception '当前账号没有查看工器具归还单的权限' using errcode = '42501';
  end if;

  with filtered as (
    select return_order.*
    from public.smis_tool_return return_order
    where (app_private.is_platform_super() or return_order.tenant_id = v_tenant)
      and (p_date_from is null or return_order.return_date >= p_date_from)
      and (p_date_to is null or return_order.return_date <= p_date_to)
      and (p_employee_id is null or return_order.employee_id = p_employee_id)
      and (nullif(p_status,'') is null or return_order.status = p_status)
      and (
        nullif(btrim(coalesce(p_keyword,'')), '') is null
        or return_order.return_no ilike '%' || btrim(p_keyword) || '%'
        or return_order.source_document_no ilike '%' || btrim(p_keyword) || '%'
        or return_order.employee_name_snapshot ilike '%' || btrim(p_keyword) || '%'
        or return_order.employee_no_snapshot ilike '%' || btrim(p_keyword) || '%'
      )
  ), page_rows as (
    select * from filtered
    order by return_date desc, create_time desc
    offset greatest(coalesce(p_from,0),0)
    limit case when p_purpose = 'export' then 10000
               else greatest(coalesce(p_to,19) - greatest(coalesce(p_from,0),0) + 1, 1) end
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'returnNo', p.return_no,
        'employeeId', p.employee_id,
        'employeeNo', p.employee_no_snapshot,
        'employeeName', p.employee_name_snapshot,
        'positionName', p.position_name_snapshot,
        'organizationId', p.organization_id,
        'organizationName', p.organization_name_snapshot,
        'sourceDocumentNo', p.source_document_no,
        'returnDate', p.return_date,
        'status', p.status,
        'submittedAt', p.submitted_at,
        'approvedAt', p.approved_at,
        'rejectionReason', p.rejection_reason,
        'remark', p.remark,
        'createTime', p.create_time,
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', i.id,
            'sourceIssuanceRecordId', i.source_issuance_record_id,
            'sourceIssuanceItemId', i.source_issuance_item_id,
            'sourceIssuanceNo', i.source_issuance_no_snapshot,
            'materialId', i.material_id,
            'materialCategory', i.material_category_snapshot,
            'materialName', i.material_name_snapshot,
            'specificationModel', i.specification_model_snapshot,
            'unit', i.unit_snapshot,
            'issuedQuantity', i.issued_quantity,
            'returnQuantity', i.return_quantity,
            'remark', i.remark
          ) order by i.source_issuance_no_snapshot, i.material_name_snapshot)
          from public.smis_tool_return_item i where i.return_id = p.id
        ), '[]'::jsonb)
      ) order by p.return_date desc, p.create_time desc)
      from page_rows p
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'overview', jsonb_build_object(
      'total', (select count(*) from filtered),
      'draft', (select count(*) from filtered where status = 'draft'),
      'pendingApproval', (select count(*) from filtered where status = 'pending_approval'),
      'approved', (select count(*) from filtered where status = 'approved'),
      'rejected', (select count(*) from filtered where status = 'rejected')
    )
  ) into v_result;
  return v_result;
end
$function$;

create or replace function public.smis_save_tool_return_secure(
  p_id uuid,
  p_payload jsonb,
  p_action text default 'add'
) returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_tenant uuid;
  v_id uuid;
  v_item jsonb;
  v_source record;
  v_first_employee uuid;
  v_quantity numeric;
  v_reserved numeric;
  v_source_document_no text;
  v_permission text;
begin
  if auth.uid() is null then
    raise exception '请先登录' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_payload->'items','[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_payload->'items','[]'::jsonb)) = 0 then
    raise exception '请至少选择一条待归还工器具' using errcode = '22023';
  end if;

  if p_id is null then
    v_permission := case p_action
      when 'copy' then 'SmisToolRequisitionReturn:Copy'
      when 'return' then 'SmisToolRequisitionReturn:Return'
      else 'SmisToolRequisitionReturn:Add'
    end;
  else
    v_permission := 'SmisToolRequisitionReturn:Edit';
  end if;
  if not app_private.has_permission(v_permission) then
    raise exception '当前账号没有执行该归还操作的权限' using errcode = '42501';
  end if;

  v_tenant := app_private.resolve_mutation_tenant_id(
    (select tenant_id from public.smis_tool_return where id = p_id)
  );
  if v_tenant is null then
    raise exception '当前账号未绑定有效租户' using errcode = '42501';
  end if;

  if p_id is not null then
    select id into v_id
    from public.smis_tool_return
    where id = p_id and tenant_id = v_tenant and status in ('draft','rejected')
    for update;
    if v_id is null then
      raise exception '仅草稿或已驳回的归还单允许编辑' using errcode = 'P0001';
    end if;
    delete from public.smis_tool_return_item where return_id = v_id;
  end if;

  for v_item in select value from jsonb_array_elements(p_payload->'items') loop
    select
      item.id as source_item_id,
      item.issuance_record_id,
      item.material_id,
      item.material_category_snapshot,
      item.material_name_snapshot,
      item.specification_model_snapshot,
      item.unit_snapshot,
      item.issue_quantity,
      record.issuance_no,
      record.employee_id,
      record.employee_no_snapshot,
      record.employee_name_snapshot,
      record.position_name_snapshot,
      record.organization_id,
      record.organization_name_snapshot
    into v_source
    from public.smis_tool_issuance_record_item item
    join public.smis_tool_issuance_record record on record.id = item.issuance_record_id
    where item.id = (v_item->>'source_issuance_item_id')::uuid
      and record.tenant_id = v_tenant
      and record.status = 'posted'
    for update of item;

    if v_source.source_item_id is null then
      raise exception '所选发放明细不存在、未过账或不属于当前租户' using errcode = 'P0002';
    end if;
    if v_first_employee is null then
      v_first_employee := v_source.employee_id;
      if p_id is null then
        insert into public.smis_tool_return(
          tenant_id, return_no, employee_id, employee_no_snapshot, employee_name_snapshot,
          position_name_snapshot, organization_id, organization_name_snapshot,
          source_document_no, return_date, status, remark
        ) values (
          v_tenant, app_private.next_document_number('smis.tool_return', v_tenant),
          v_source.employee_id, v_source.employee_no_snapshot, v_source.employee_name_snapshot,
          v_source.position_name_snapshot, v_source.organization_id, v_source.organization_name_snapshot,
          v_source.issuance_no, coalesce((p_payload->>'return_date')::date, current_date),
          'draft', nullif(btrim(coalesce(p_payload->>'remark','')), '')
        ) returning id into v_id;
      else
        update public.smis_tool_return
        set employee_id = v_source.employee_id,
            employee_no_snapshot = v_source.employee_no_snapshot,
            employee_name_snapshot = v_source.employee_name_snapshot,
            position_name_snapshot = v_source.position_name_snapshot,
            organization_id = v_source.organization_id,
            organization_name_snapshot = v_source.organization_name_snapshot,
            return_date = coalesce((p_payload->>'return_date')::date, current_date),
            status = 'draft',
            rejection_reason = null,
            remark = nullif(btrim(coalesce(p_payload->>'remark','')), '')
        where id = v_id;
      end if;
    elsif v_source.employee_id <> v_first_employee then
      raise exception '同一张归还单只能选择同一领用人的工器具' using errcode = '22023';
    end if;

    v_quantity := (v_item->>'return_quantity')::numeric;
    if v_quantity is null or v_quantity <= 0 then
      raise exception '归还数量必须大于 0' using errcode = '22023';
    end if;
    select coalesce(sum(return_item.return_quantity),0)
    into v_reserved
    from public.smis_tool_return_item return_item
    join public.smis_tool_return return_order on return_order.id = return_item.return_id
    where return_item.source_issuance_item_id = v_source.source_item_id
      and return_order.id <> v_id
      and return_order.status in ('draft','pending_approval','approved');
    if v_quantity > v_source.issue_quantity - v_reserved then
      raise exception '工器具“%”可归还数量不足，可归还 % %',
        v_source.material_name_snapshot,
        greatest(v_source.issue_quantity - v_reserved,0),
        v_source.unit_snapshot
        using errcode = '22023';
    end if;

    insert into public.smis_tool_return_item(
      tenant_id, return_id, source_issuance_record_id, source_issuance_item_id,
      source_issuance_no_snapshot, material_id, material_category_snapshot,
      material_name_snapshot, specification_model_snapshot, unit_snapshot,
      issued_quantity, return_quantity, remark
    ) values (
      v_tenant, v_id, v_source.issuance_record_id, v_source.source_item_id,
      v_source.issuance_no, v_source.material_id, v_source.material_category_snapshot,
      v_source.material_name_snapshot, v_source.specification_model_snapshot, v_source.unit_snapshot,
      v_source.issue_quantity, v_quantity, nullif(btrim(coalesce(v_item->>'remark','')), '')
    );
  end loop;

  select string_agg(distinct source_issuance_no_snapshot, ', ' order by source_issuance_no_snapshot)
  into v_source_document_no
  from public.smis_tool_return_item where return_id = v_id;
  update public.smis_tool_return
  set source_document_no = v_source_document_no
  where id = v_id;
  return v_id;
end
$function$;

create or replace function public.smis_delete_tool_returns_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_tenant uuid := app_private.auth_user_tenant_id();
  v_count integer;
begin
  if auth.uid() is null or not app_private.has_permission('SmisToolRequisitionReturn:Delete') then
    raise exception '当前账号没有删除归还单的权限' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.smis_tool_return
    where id = any(p_ids)
      and not (app_private.is_platform_super() or tenant_id = v_tenant)
  ) then
    raise exception '不能删除其他租户的归还单' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.smis_tool_return
    where id = any(p_ids) and status not in ('draft','rejected')
  ) then
    raise exception '仅草稿或已驳回的归还单允许删除' using errcode = 'P0001';
  end if;
  delete from public.smis_tool_return
  where id = any(p_ids) and (app_private.is_platform_super() or tenant_id = v_tenant);
  get diagnostics v_count = row_count;
  return v_count;
end
$function$;

revoke all on function public.smis_list_tool_returnable_items_secure(integer,integer,uuid,text,text)
  from public, anon;
grant execute on function public.smis_list_tool_returnable_items_secure(integer,integer,uuid,text,text)
  to authenticated;
revoke all on function public.smis_list_tool_returns_secure(integer,integer,date,date,uuid,text,text,text)
  from public, anon;
grant execute on function public.smis_list_tool_returns_secure(integer,integer,date,date,uuid,text,text,text)
  to authenticated;
revoke all on function public.smis_save_tool_return_secure(uuid,jsonb,text)
  from public, anon;
grant execute on function public.smis_save_tool_return_secure(uuid,jsonb,text)
  to authenticated;
revoke all on function public.smis_delete_tool_returns_secure(uuid[])
  from public, anon;
grant execute on function public.smis_delete_tool_returns_secure(uuid[])
  to authenticated;
revoke all on function public.smis_submit_tool_return_secure(uuid)
  from public, anon;
grant execute on function public.smis_submit_tool_return_secure(uuid)
  to authenticated;

;
