SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;
CREATE SCHEMA IF NOT EXISTS "app_private";
ALTER SCHEMA "app_private" OWNER TO "postgres";
COMMENT ON SCHEMA "public" IS 'standard public schema';
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
CREATE OR REPLACE FUNCTION "app_private"."current_app_user_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select id
  from public.sys_user
  where auth_user_id = auth.uid()
  limit 1;
$$;
ALTER FUNCTION "app_private"."current_app_user_id"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."current_user_tenant_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$select tenant_id from public.sys_user where auth_user_id = auth.uid() limit 1$$;
ALTER FUNCTION "app_private"."current_user_tenant_id"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."default_register_tenant_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$select id from public.sys_tenant where tenant_code = 'public-register' limit 1$$;
ALTER FUNCTION "app_private"."default_register_tenant_id"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."enforce_platform_super_role"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
  is_platform_tenant boolean;
begin
  select exists (
    select 1
    from public.sys_tenant t
    where t.id = new.tenant_id
      and lower(t.tenant_code) = 'platform'
  ) into is_platform_tenant;

  if upper(new.role_code) = 'R_SUPER' and not is_platform_tenant then
    raise exception 'R_SUPER role can only exist in platform tenant';
  end if;

  return new;
end;
$$;
ALTER FUNCTION "app_private"."enforce_platform_super_role"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."enforce_platform_super_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
  platform_tenant_id uuid;
  is_platform_tenant boolean;
  has_super_role boolean;
begin
  select id
    into platform_tenant_id
  from public.sys_tenant
  where lower(tenant_code) = 'platform'
  limit 1;

  if platform_tenant_id is null then
    raise exception 'Platform tenant with tenant_code=platform is required';
  end if;

  is_platform_tenant := new.tenant_id = platform_tenant_id;
  has_super_role := 'R_SUPER' = any(coalesce(new.user_roles, array[]::text[]));

  if is_platform_tenant and lower(new.user_email) <> '869123771@qq.com' then
    raise exception 'Only 869123771@qq.com can be assigned to platform tenant';
  end if;

  if has_super_role and (not is_platform_tenant or lower(new.user_email) <> '869123771@qq.com') then
    raise exception 'R_SUPER can only be assigned to 869123771@qq.com in platform tenant';
  end if;

  return new;
end;
$$;
ALTER FUNCTION "app_private"."enforce_platform_super_user"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."enforce_sys_user_tenant_rules"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
  v_user_email text;
  v_tenant_code text;
  v_invalid_role_codes text[];
begin
  select lower(u.user_email)
    into v_user_email
  from public.sys_user u
  where u.id = new.user_id;

  if v_user_email is null then
    raise exception 'User not found';
  end if;

  select lower(t.tenant_code)
    into v_tenant_code
  from public.sys_tenant t
  where t.id = new.tenant_id;

  if v_tenant_code is null then
    raise exception 'Tenant not found';
  end if;

  if v_tenant_code = 'platform' and v_user_email <> '869123771@qq.com' then
    raise exception 'Only 869123771@qq.com can be assigned to platform tenant';
  end if;

  if 'R_SUPER' = any(coalesce(new.role_codes, array[]::text[]))
     and (v_tenant_code <> 'platform' or v_user_email <> '869123771@qq.com') then
    raise exception 'R_SUPER can only be assigned to 869123771@qq.com in platform tenant';
  end if;

  select array_agg(role_code)
    into v_invalid_role_codes
  from unnest(coalesce(new.role_codes, array[]::text[])) as selected(role_code)
  where not exists (
    select 1
    from public.sys_role r
    where r.tenant_id = new.tenant_id
      and r.role_code = selected.role_code
      and r.enabled = true
  );

  if coalesce(array_length(v_invalid_role_codes, 1), 0) > 0 then
    raise exception 'Invalid role codes for tenant: %', array_to_string(v_invalid_role_codes, ',');
  end if;

  return new;
end;
$$;
ALTER FUNCTION "app_private"."enforce_sys_user_tenant_rules"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."enforce_system_role_rules"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
  v_tenant_code text;
  v_old_tenant_code text;
  v_new_tenant_code text;
begin
  if tg_op = 'DELETE' then
    select lower(t.tenant_code)
      into v_tenant_code
    from public.sys_tenant t
    where t.id = old.tenant_id;

    if upper(old.role_code) = 'R_SUPER' then
      raise exception 'Super admin role cannot be deleted';
    end if;

    if v_tenant_code = 'public-register' and upper(old.role_code) = 'R_REGISTER' then
      raise exception 'Default register role cannot be deleted';
    end if;

    return old;
  end if;

  select lower(t.tenant_code)
    into v_new_tenant_code
  from public.sys_tenant t
  where t.id = new.tenant_id;

  if upper(new.role_code) = 'R_SUPER' then
    if v_new_tenant_code <> 'platform' then
      raise exception 'R_SUPER role can only exist in platform tenant';
    end if;

    if new.enabled is false then
      raise exception 'Super admin role cannot be disabled';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    select lower(t.tenant_code)
      into v_old_tenant_code
    from public.sys_tenant t
    where t.id = old.tenant_id;

    if upper(old.role_code) = 'R_SUPER' then
      if new.tenant_id is distinct from old.tenant_id then
        raise exception 'Super admin role tenant cannot be changed';
      end if;

      if upper(new.role_code) <> 'R_SUPER' then
        raise exception 'Super admin role code cannot be changed';
      end if;

      if new.enabled is false then
        raise exception 'Super admin role cannot be disabled';
      end if;
    end if;

    if v_old_tenant_code = 'public-register' and upper(old.role_code) = 'R_REGISTER' then
      if new.tenant_id is distinct from old.tenant_id then
        raise exception 'Default register role tenant cannot be changed';
      end if;

      if upper(new.role_code) <> 'R_REGISTER' then
        raise exception 'Default register role code cannot be changed';
      end if;

      if new.enabled is false then
        raise exception 'Default register role cannot be disabled';
      end if;
    end if;
  end if;

  if tg_op = 'INSERT' then
    if v_new_tenant_code = 'public-register' and upper(new.role_code) = 'R_REGISTER' and new.enabled is false then
      raise exception 'Default register role cannot be disabled';
    end if;
  end if;

  return new;
end;
$$;
ALTER FUNCTION "app_private"."enforce_system_role_rules"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."is_platform_super"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
  select exists (
    select 1
    from public.sys_user u
    join public.sys_tenant t on t.id = u.tenant_id
    where u.auth_user_id = auth.uid()
      and lower(u.user_email) = '869123771@qq.com'
      and lower(t.tenant_code) = 'platform'
      and 'R_SUPER' = any(coalesce(u.user_roles, array[]::text[]))
      and u.status = '1'
  );
$$;
ALTER FUNCTION "app_private"."is_platform_super"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."is_tenant_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$select exists (
  select 1
  from public.sys_user
  where auth_user_id = auth.uid()
    and 'R_ADMIN' = any(coalesce(user_roles, array[]::text[]))
)$$;
ALTER FUNCTION "app_private"."is_tenant_admin"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."platform_tenant_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select id
  from public.sys_tenant
  where lower(tenant_code) = 'platform'
  limit 1
$$;
ALTER FUNCTION "app_private"."platform_tenant_id"() OWNER TO "postgres";
COMMENT ON FUNCTION "app_private"."platform_tenant_id"() IS '返回平台运营租户 ID，供全局共享数据设置外键默认值';
CREATE OR REPLACE FUNCTION "app_private"."trg_apply_current_tenant_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
  current_tenant_id uuid;
begin
  current_tenant_id := app_private.current_user_tenant_id();

  if current_tenant_id is null then
    return new;
  end if;

  if app_private.is_platform_super() then
    new.tenant_id := coalesce(new.tenant_id, current_tenant_id);
  else
    new.tenant_id := current_tenant_id;
  end if;

  return new;
end$$;
ALTER FUNCTION "app_private"."trg_apply_current_tenant_id"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."validate_dict_type_hierarchy"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  parent_row public.sys_dict_type%rowtype;
  has_cycle boolean;
begin
  if tg_op = 'UPDATE' and old.node_type is distinct from new.node_type then
    if exists (
      select 1
      from public.sys_dict_type
      where parent_id = new.id
    ) then
      raise exception '存在下级节点时不能修改节点类型';
    end if;

    if exists (
      select 1
      from public.sys_dictionary
      where type_id = new.id
    ) then
      raise exception '存在字典项时不能修改节点类型';
    end if;
  end if;

  if new.parent_id is null then
    return new;
  end if;

  if new.id is not null and new.parent_id = new.id then
    raise exception '字典目录不能选择自身作为上级';
  end if;

  select *
  into parent_row
  from public.sys_dict_type
  where id = new.parent_id;

  if not found then
    raise exception '上级字典目录不存在';
  end if;

  if parent_row.tenant_id is distinct from new.tenant_id then
    raise exception '不能挂载到其他租户的字典目录';
  end if;

  if parent_row.node_type <> 'directory' then
    raise exception '字典类型不能作为其他节点的上级';
  end if;

  if new.id is not null then
    with recursive descendants as (
      select id
      from public.sys_dict_type
      where parent_id = new.id
      union all
      select child.id
      from public.sys_dict_type child
      join descendants parent on child.parent_id = parent.id
    )
    select exists (
      select 1
      from descendants
      where id = new.parent_id
    )
    into has_cycle;

    if has_cycle then
      raise exception '不能将字典目录移动到自己的下级';
    end if;
  end if;

  return new;
end
$$;
ALTER FUNCTION "app_private"."validate_dict_type_hierarchy"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "app_private"."validate_dictionary_hierarchy"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  type_row public.sys_dict_type%rowtype;
  parent_row public.sys_dictionary%rowtype;
  has_cycle boolean;
begin
  select *
  into type_row
  from public.sys_dict_type
  where id = new.type_id;

  if not found or type_row.node_type <> 'dictionary' then
    raise exception '字典项必须归属于有效的字典类型';
  end if;

  if type_row.tenant_id is distinct from new.tenant_id then
    raise exception '不能使用其他租户的字典类型';
  end if;

  if new.parent_id is null then
    return new;
  end if;

  if new.id is not null and new.parent_id = new.id then
    raise exception '字典项不能选择自身作为上级';
  end if;

  select *
  into parent_row
  from public.sys_dictionary
  where id = new.parent_id;

  if not found then
    raise exception '上级字典项不存在';
  end if;

  if parent_row.tenant_id is distinct from new.tenant_id
    or parent_row.type_id is distinct from new.type_id then
    raise exception '上级字典项必须属于同一租户和同一字典类型';
  end if;

  if new.id is not null then
    with recursive descendants as (
      select id
      from public.sys_dictionary
      where parent_id = new.id
      union all
      select child.id
      from public.sys_dictionary child
      join descendants parent on child.parent_id = parent.id
    )
    select exists (
      select 1
      from descendants
      where id = new.parent_id
    )
    into has_cycle;

    if has_cycle then
      raise exception '不能将字典项移动到自己的下级';
    end if;
  end if;

  return new;
end
$$;
ALTER FUNCTION "app_private"."validate_dictionary_hierarchy"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."clean_role_menus_on_role_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  delete from public.sys_role_menu where role_id = old.id;
  return old;
end;
$$;
ALTER FUNCTION "public"."clean_role_menus_on_role_delete"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."current_is_super"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
  select app_private.is_platform_super();
$$;
ALTER FUNCTION "public"."current_is_super"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."execute_sql_query"("sql_query" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
DECLARE
  v_result jsonb;
  v_rows jsonb;
  v_columns jsonb;
  v_command_tag text;
  v_row_count integer := 0;
  v_start_time timestamp with time zone;
  v_end_time timestamp with time zone;
  v_duration_ms numeric;
  v_notices text[] := ARRAY[]::text[];
  v_warnings text[] := ARRAY[]::text[];
  v_query_upper text;
  v_error_message text;
  v_sql_state text;
  v_sql_err_msg text;
  v_detail text;
  v_sql_lines text[];
  v_line_num integer;
  v_found_line boolean := false;
  v_line_content text;
  v_identifier text;
  v_col_rec record;
  v_col_info jsonb;
  v_col_name text;
  v_col_value jsonb;
  v_col_type text;
BEGIN
  -- 记录开始时间
  v_start_time := clock_timestamp();
  v_query_upper := upper(trim(sql_query));
  
  -- 将 SQL 查询按行分割，用于后续的 LINE 信息提取
  v_sql_lines := string_to_array(sql_query, E'\n');

  -- 检查是否为 SELECT 查询
  IF v_query_upper LIKE 'SELECT%' OR v_query_upper LIKE 'WITH%' THEN
    -- 对于 SELECT 查询，使用动态 SQL 转换为 JSON
    BEGIN
      -- 执行查询获取结果
      EXECUTE format('SELECT jsonb_agg(row_to_json(t)) FROM (%s) t', sql_query) INTO v_rows;
      
      -- 如果结果为 NULL（没有行），设置为空数组
      IF v_rows IS NULL THEN
        v_rows := '[]'::jsonb;
      END IF;
      
      v_row_count := jsonb_array_length(v_rows);
      v_command_tag := format('SELECT %s', v_row_count);
      
      -- 获取列信息
      v_columns := '[]'::jsonb;
      
      -- 如果有数据行，从第一行获取列名和类型信息
      IF v_row_count > 0 THEN
        DECLARE
          v_first_row jsonb;
          v_col_info_item jsonb;
        BEGIN
          v_first_row := v_rows->0;
          
          -- 遍历第一行的所有键（列名）
          FOR v_col_name, v_col_value IN SELECT * FROM jsonb_each(v_first_row)
          LOOP
            -- 根据值的类型推断 PostgreSQL 类型
            v_col_type := CASE
              WHEN jsonb_typeof(v_col_value) = 'null' THEN 'unknown'
              WHEN jsonb_typeof(v_col_value) = 'boolean' THEN 'boolean'
              WHEN jsonb_typeof(v_col_value) = 'number' THEN 
                CASE 
                  WHEN v_col_value::text ~ '^-?[0-9]+$' THEN 'integer'
                  ELSE 'numeric'
                END
              WHEN jsonb_typeof(v_col_value) = 'string' THEN
                CASE
                  WHEN v_col_value::text ~ '^\d{4}-\d{2}-\d{2}' THEN 'date'
                  WHEN v_col_value::text ~ '^\d{4}-\d{2}-\d{2}.*\d{2}:\d{2}:\d{2}' THEN 'timestamp'
                  ELSE 'text'
                END
              WHEN jsonb_typeof(v_col_value) = 'object' THEN 'jsonb'
              WHEN jsonb_typeof(v_col_value) = 'array' THEN 'array'
              ELSE 'text'
            END;
            
            -- 构建列信息对象
            v_col_info_item := jsonb_build_object(
              'name', v_col_name,
              'type', v_col_type,
              'nullable', true,  -- 默认值
              'jsType', CASE 
                WHEN v_col_type IN ('integer', 'numeric', 'bigint', 'smallint', 'real', 'double precision') THEN 'number'
                WHEN v_col_type = 'boolean' THEN 'boolean'
                WHEN v_col_type IN ('date', 'timestamp', 'timestamptz', 'time', 'timetz') THEN 'date'
                WHEN v_col_type IN ('json', 'jsonb') THEN 'json'
                ELSE 'string'
              END,
              'description', NULL
            );
            
            v_columns := v_columns || jsonb_build_array(v_col_info_item);
          END LOOP;
        END;
      END IF;
      
      -- 尝试从查询结果中获取更详细的列信息
      -- 使用 pg_catalog 查询列的描述信息
      -- 注意：这需要知道表名，对于复杂查询可能不适用
      DECLARE
        v_table_schema text;
        v_table_name text;
        v_table_match text[];
        v_col_descriptions jsonb;
      BEGIN
        -- 尝试从 SQL 中提取表名（简单匹配 FROM 子句）
        -- 匹配: FROM schema.table 或 FROM table
        v_table_match := regexp_match(sql_query, E'(?i)\\s+FROM\\s+(?:([a-z_][a-z0-9_]*)\\.)?([a-z_][a-z0-9_]*)', 'i');
        
        IF v_table_match IS NOT NULL THEN
          v_table_schema := COALESCE(NULLIF(v_table_match[1], ''), 'public');
          v_table_name := v_table_match[2];
          
          -- 查询列的描述信息
          FOR v_col_rec IN
            SELECT 
              a.attname as column_name,
              pg_catalog.format_type(a.atttypid, a.atttypmod) as data_type,
              a.attnotnull as is_not_null,
              COALESCE(d.description, '') as column_comment
            FROM pg_catalog.pg_attribute a
            JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            LEFT JOIN pg_catalog.pg_description d ON d.objoid = c.oid AND d.objsubid = a.attnum
            WHERE n.nspname = v_table_schema
              AND c.relname = v_table_name
              AND a.attnum > 0
              AND NOT a.attisdropped
            ORDER BY a.attnum
          LOOP
            -- 更新对应列的信息
            v_columns := (
              SELECT jsonb_agg(
                CASE 
                  WHEN col->>'name' = v_col_rec.column_name THEN
                    jsonb_build_object(
                      'name', v_col_rec.column_name,
                      'type', split_part(v_col_rec.data_type, '(', 1),  -- 移除长度信息
                      'fullType', v_col_rec.data_type,
                      'nullable', NOT v_col_rec.is_not_null,
                      'jsType', CASE 
                        WHEN v_col_rec.data_type LIKE '%int%' OR v_col_rec.data_type LIKE '%numeric%' OR v_col_rec.data_type LIKE '%float%' OR v_col_rec.data_type LIKE '%double%' THEN 'number'
                        WHEN v_col_rec.data_type LIKE '%bool%' THEN 'boolean'
                        WHEN v_col_rec.data_type LIKE '%date%' OR v_col_rec.data_type LIKE '%time%' THEN 'date'
                        WHEN v_col_rec.data_type LIKE '%json%' THEN 'json'
                        ELSE 'string'
                      END,
                      'description', NULLIF(v_col_rec.column_comment, '')
                    )
                  ELSE col
                END
              )
              FROM jsonb_array_elements(v_columns) AS col
            );
          END LOOP;
        END IF;
      END;
      
    EXCEPTION
      WHEN OTHERS THEN
        -- 获取详细的错误信息
        GET STACKED DIAGNOSTICS
          v_sql_state = RETURNED_SQLSTATE,
          v_sql_err_msg = MESSAGE_TEXT,
          v_detail = PG_EXCEPTION_DETAIL;
        
        -- 构建错误消息，格式与 Supabase 一致
        v_error_message := format('ERROR: %s: %s', v_sql_state, v_sql_err_msg);
        
        -- 尝试从错误消息中提取引用的标识符（表名、列名等）
        v_identifier := (regexp_match(v_sql_err_msg, E'"([^"]+)"'))[1];
        
        -- 如果找到了标识符，在 SQL 查询中查找包含该标识符的行
        IF v_identifier IS NOT NULL THEN
          FOR v_line_num IN 1..array_length(v_sql_lines, 1) LOOP
            v_line_content := v_sql_lines[v_line_num];
            
            IF v_line_content LIKE '%' || v_identifier || '%' THEN
              v_error_message := v_error_message || E'\n' || 
                format('LINE %s: %s', v_line_num, trim(v_line_content)) || E'\n' ||
                repeat(' ', greatest(5 + length(v_line_num::text) + 2, 0)) || '^';
              v_found_line := true;
              EXIT;
            END IF;
          END LOOP;
        END IF;
        
        IF NOT v_found_line THEN
          IF v_detail IS NOT NULL AND v_detail != '' THEN
            v_error_message := v_error_message || E'\n' || v_detail;
          END IF;
        END IF;
        
        RETURN jsonb_build_object(
          'error', true,
          'error_message', v_error_message,
          'sql_state', v_sql_state,
          'duration_ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000::numeric, 2)
        );
    END;
    
  ELSIF v_query_upper LIKE 'INSERT%' THEN
    BEGIN
      EXECUTE sql_query;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      v_command_tag := format('INSERT 0 %s', v_row_count);
      v_rows := '[]'::jsonb;
      v_columns := '[]'::jsonb;
    EXCEPTION
      WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
          v_sql_state = RETURNED_SQLSTATE,
          v_sql_err_msg = MESSAGE_TEXT,
          v_detail = PG_EXCEPTION_DETAIL;
        v_error_message := format('ERROR: %s: %s', v_sql_state, v_sql_err_msg);
        IF v_detail IS NOT NULL AND v_detail != '' THEN
          v_error_message := v_error_message || E'\n' || v_detail;
        END IF;
        RETURN jsonb_build_object(
          'error', true,
          'error_message', v_error_message,
          'sql_state', v_sql_state,
          'duration_ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000::numeric, 2)
        );
    END;
    
  ELSIF v_query_upper LIKE 'UPDATE%' THEN
    BEGIN
      EXECUTE sql_query;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      v_command_tag := format('UPDATE %s', v_row_count);
      v_rows := '[]'::jsonb;
      v_columns := '[]'::jsonb;
    EXCEPTION
      WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
          v_sql_state = RETURNED_SQLSTATE,
          v_sql_err_msg = MESSAGE_TEXT,
          v_detail = PG_EXCEPTION_DETAIL;
        v_error_message := format('ERROR: %s: %s', v_sql_state, v_sql_err_msg);
        IF v_detail IS NOT NULL AND v_detail != '' THEN
          v_error_message := v_error_message || E'\n' || v_detail;
        END IF;
        RETURN jsonb_build_object(
          'error', true,
          'error_message', v_error_message,
          'sql_state', v_sql_state,
          'duration_ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000::numeric, 2)
        );
    END;
    
  ELSIF v_query_upper LIKE 'DELETE%' THEN
    BEGIN
      EXECUTE sql_query;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      v_command_tag := format('DELETE %s', v_row_count);
      v_rows := '[]'::jsonb;
      v_columns := '[]'::jsonb;
    EXCEPTION
      WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
          v_sql_state = RETURNED_SQLSTATE,
          v_sql_err_msg = MESSAGE_TEXT,
          v_detail = PG_EXCEPTION_DETAIL;
        v_error_message := format('ERROR: %s: %s', v_sql_state, v_sql_err_msg);
        IF v_detail IS NOT NULL AND v_detail != '' THEN
          v_error_message := v_error_message || E'\n' || v_detail;
        END IF;
        RETURN jsonb_build_object(
          'error', true,
          'error_message', v_error_message,
          'sql_state', v_sql_state,
          'duration_ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000::numeric, 2)
        );
    END;
    
  ELSE
    BEGIN
      EXECUTE sql_query;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      v_command_tag := upper(split_part(trim(sql_query), ' ', 1));
      v_rows := '[]'::jsonb;
      v_columns := '[]'::jsonb;
    EXCEPTION
      WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
          v_sql_state = RETURNED_SQLSTATE,
          v_sql_err_msg = MESSAGE_TEXT,
          v_detail = PG_EXCEPTION_DETAIL;
        v_error_message := format('ERROR: %s: %s', v_sql_state, v_sql_err_msg);
        IF v_detail IS NOT NULL AND v_detail != '' THEN
          v_error_message := v_error_message || E'\n' || v_detail;
        END IF;
        RETURN jsonb_build_object(
          'error', true,
          'error_message', v_error_message,
          'sql_state', v_sql_state,
          'duration_ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000::numeric, 2)
        );
    END;
  END IF;
  
  -- 记录结束时间
  v_end_time := clock_timestamp();
  v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
  
  -- 构建返回结果
  v_result := jsonb_build_object(
    'rows', COALESCE(v_rows, '[]'::jsonb),
    'columns', COALESCE(v_columns, '[]'::jsonb),
    'command_tag', v_command_tag,
    'row_count', v_row_count,
    'duration_ms', round(v_duration_ms::numeric, 2),
    'notices', v_notices,
    'warnings', v_warnings
  );
  
  RETURN v_result;
  
EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_sql_state = RETURNED_SQLSTATE,
      v_sql_err_msg = MESSAGE_TEXT,
      v_detail = PG_EXCEPTION_DETAIL;
    
    v_error_message := format('ERROR: %s: %s', v_sql_state, v_sql_err_msg);
    
    IF v_detail IS NOT NULL AND v_detail != '' THEN
      v_error_message := v_error_message || E'\n' || v_detail;
    END IF;
    
    RETURN jsonb_build_object(
      'error', true,
      'error_message', v_error_message,
      'sql_state', v_sql_state,
      'duration_ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000::numeric, 2)
    );
END;
$_$;
ALTER FUNCTION "public"."execute_sql_query"("sql_query" "text") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."get_app_user_display_name"() RETURNS "text"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  select current_setting('myapp.current_user_display', true)
  where current_setting('myapp.current_user_display', true) is not null
  union all
  select coalesce(nullif(user_email, ''), nullif(user_name, ''), nullif(nick_name, ''))
  from public.sys_user
  where auth_user_id = (select auth.uid())
  limit 1;
$$;
ALTER FUNCTION "public"."get_app_user_display_name"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."get_database_metadata_all"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_result jsonb;
  v_schemas jsonb;
  v_tables jsonb;
  v_columns jsonb;
  v_functions jsonb;
BEGIN
  -- 获取所有 schemas
  SELECT jsonb_agg(schema_name ORDER BY schema_name)
  INTO v_schemas
  FROM information_schema.schemata
  WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast', 'pg_temp_1', 'pg_toast_temp_1');

  -- 获取所有表信息
  SELECT jsonb_agg(
    jsonb_build_object(
      'tableSchema', table_schema,
      'tableName', table_name
    )
    ORDER BY table_schema, table_name
  )
  INTO v_tables
  FROM information_schema.tables
  WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    AND table_type = 'BASE TABLE';

  -- 获取所有列信息
  SELECT jsonb_agg(
    jsonb_build_object(
      'tableSchema', table_schema,
      'tableName', table_name,
      'columnName', column_name,
      'dataType', data_type,
      'isNullable', is_nullable,
      'ordinalPosition', ordinal_position
    )
    ORDER BY table_schema, table_name, ordinal_position
  )
  INTO v_columns
  FROM information_schema.columns
  WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast');

  -- 获取所有函数信息
  SELECT jsonb_agg(
    jsonb_build_object(
      'routineSchema', routine_schema,
      'routineName', routine_name,
      'returnType', data_type
    )
    ORDER BY routine_schema, routine_name
  )
  INTO v_functions
  FROM information_schema.routines
  WHERE routine_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    AND routine_type = 'FUNCTION';

  -- 构建返回结果
  v_result := jsonb_build_object(
    'schemas', COALESCE(v_schemas, '[]'::jsonb),
    'tables', COALESCE(v_tables, '[]'::jsonb),
    'columns', COALESCE(v_columns, '[]'::jsonb),
    'functions', COALESCE(v_functions, '[]'::jsonb)
  );

  RETURN v_result;
END;
$$;
ALTER FUNCTION "public"."get_database_metadata_all"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."get_menus_for_current_user"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
  v_cur_uid uuid := (select auth.uid());
  v_role_ids uuid[] := '{}';
  v_menu_ids uuid[] := '{}';
  v_rec record;
  v_depth_rec record;
  v_node_map jsonb := '{}'::jsonb;
  v_roots jsonb := '[]'::jsonb;
  v_flat jsonb := '[]'::jsonb;
  v_parent_id text;
  v_children jsonb;
begin
  if v_cur_uid is null then
    return jsonb_build_object('flat', v_flat, 'tree', v_roots);
  end if;

  if app_private.is_platform_super() then
    select array_remove(array_agg(m.id order by m.sort nulls last, m.id), null)
      into v_menu_ids
    from public.sys_menu m;
  else
    select array_remove(array_agg(distinct r.id), null) into v_role_ids
    from public.sys_user au
    join public.sys_role r
      on r.role_code = any(au.user_roles)
     and (
       r.tenant_id = au.tenant_id
       or r.tenant_id is null
     )
    where au.auth_user_id = v_cur_uid;

    if v_role_ids is null or array_length(v_role_ids, 1) is null then
      return jsonb_build_object('flat', v_flat, 'tree', v_roots);
    end if;

    select array_remove(array_agg(distinct rm.menu_id), null) into v_menu_ids
    from public.sys_role_menu rm
    where rm.role_id = any(v_role_ids);
  end if;

  if v_menu_ids is null or array_length(v_menu_ids, 1) is null then
    return jsonb_build_object('flat', v_flat, 'tree', v_roots);
  end if;

  for v_rec in
    select m.id, m.parent_id, m.name, m.path, m.component, m.meta, m.sort, m.type
    from public.sys_menu m
    where m.id = any(v_menu_ids)
    order by m.sort nulls last, m.id
  loop
    v_flat := v_flat || jsonb_build_object(
      'id', v_rec.id,
      'parentId', v_rec.parent_id,
      'name', v_rec.name,
      'path', v_rec.path,
      'component', v_rec.component,
      'meta', v_rec.meta,
      'sort', v_rec.sort,
      'type', v_rec.type
    );

    v_node_map := v_node_map || jsonb_build_object(v_rec.id::text, jsonb_build_object(
      'id', v_rec.id,
      'parentId', v_rec.parent_id,
      'name', v_rec.name,
      'path', v_rec.path,
      'component', v_rec.component,
      'meta', v_rec.meta,
      'sort', v_rec.sort,
      'type', v_rec.type,
      'children', '[]'::jsonb
    ));
  end loop;

  for v_depth_rec in
    with recursive ancestor_depth as (
      select m.id as node_id, m.parent_id, 0 as depth
      from public.sys_menu m
      where m.id = any(v_menu_ids)

      union all

      select ad.node_id, parent.parent_id, ad.depth + 1
      from ancestor_depth ad
      join public.sys_menu parent on parent.id = ad.parent_id
      where parent.id = any(v_menu_ids)
    ), node_depth as (
      select node_id, max(depth) as depth
      from ancestor_depth
      group by node_id
    )
    select m.id, m.parent_id, m.sort, nd.depth
    from public.sys_menu m
    join node_depth nd on nd.node_id = m.id
    where m.id = any(v_menu_ids)
    order by nd.depth desc, m.sort nulls last, m.id
  loop
    v_parent_id := v_depth_rec.parent_id::text;

    if v_parent_id is not null and v_node_map ? v_parent_id then
      v_children := (v_node_map -> v_parent_id) -> 'children';
      v_children := v_children || (v_node_map -> v_depth_rec.id::text);
      v_node_map := jsonb_set(
        v_node_map,
        array[v_parent_id],
        (v_node_map -> v_parent_id) - 'children' || jsonb_build_object('children', v_children)
      );
    end if;
  end loop;

  for v_rec in
    select m.id, m.parent_id
    from public.sys_menu m
    where m.id = any(v_menu_ids)
      and (m.parent_id is null or not v_node_map ? m.parent_id::text)
    order by m.sort nulls last, m.id
  loop
    v_roots := v_roots || (v_node_map -> v_rec.id::text);
  end loop;

  return jsonb_build_object('flat', v_flat, 'tree', v_roots);
end;
$$;
ALTER FUNCTION "public"."get_menus_for_current_user"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."prevent_platform_tenant_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  protected_codes text[] := array['platform', 'public-register'];
  old_code text;
  new_code text;
begin
  if tg_op = 'DELETE' then
    old_code := lower(old.tenant_code);

    if old_code = any(protected_codes) then
      raise exception 'System tenant % cannot be deleted', old.tenant_code;
    end if;

    return old;
  end if;

  if tg_op = 'UPDATE' then
    old_code := lower(old.tenant_code);
    new_code := lower(new.tenant_code);

    if old_code = any(protected_codes) and new_code <> old_code then
      raise exception 'System tenant code % cannot be changed', old.tenant_code;
    end if;

    if old_code <> new_code and new_code = any(protected_codes) then
      raise exception 'System tenant code % is reserved', new.tenant_code;
    end if;

    return new;
  end if;

  return new;
end;
$$;
ALTER FUNCTION "public"."prevent_platform_tenant_change"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;
ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."save_dict_type_tree_order"("p_updates" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  item jsonb;
  affected_rows integer;
begin
  if not app_private.is_platform_super() then
    raise exception '仅平台超级管理员可以调整字典目录';
  end if;

  if jsonb_typeof(p_updates) <> 'array' then
    raise exception '字典目录排序参数必须是数组';
  end if;

  for item in
    select value
    from jsonb_array_elements(p_updates)
  loop
    update public.sys_dict_type
    set
      parent_id = nullif(item->>'parentId', '')::uuid,
      sort = greatest(coalesce((item->>'sort')::integer, 0), 0)
    where id = (item->>'id')::uuid;

    get diagnostics affected_rows = row_count;
    if affected_rows <> 1 then
      raise exception '字典目录节点不存在或无权修改: %', item->>'id';
    end if;
  end loop;
end
$$;
ALTER FUNCTION "public"."save_dict_type_tree_order"("p_updates" "jsonb") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."save_dict_type_tree_order"("p_updates" "jsonb") IS '平台超级管理员原子保存字典目录树的父级和同级排序';
CREATE OR REPLACE FUNCTION "public"."set_role_menus"("p_role_id" "uuid", "p_menu_ids" "uuid"[]) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'app_private'
    AS $$
declare
  v_tenant_id uuid;
  v_role_code text;
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
begin
  select role.tenant_id, upper(role.role_code)
    into v_tenant_id, v_role_code
  from public.sys_role as role
  where role.id = p_role_id;

  if not found then
    raise exception 'Role not found or access denied';
  end if;

  if v_tenant_id is null then
    raise exception 'Role tenant is missing';
  end if;

  if v_role_code = 'R_SUPER' then
    raise exception 'Super admin role has all permissions and does not support menu allocation';
  end if;

  if v_role_code = 'R_REGISTER' and not v_is_platform_super then
    raise exception 'Default register role menus can only be assigned by platform super administrator';
  end if;

  if not v_is_platform_super and v_tenant_id is distinct from v_current_tenant_id then
    raise exception 'Cannot assign menus to a role outside the current tenant';
  end if;

  delete from public.sys_role_menu
  where role_id = p_role_id;

  if coalesce(cardinality(p_menu_ids), 0) > 0 then
    insert into public.sys_role_menu (role_id, menu_id, tenant_id)
    select p_role_id, menu_id, v_tenant_id
    from (
      select distinct unnest(p_menu_ids) as menu_id
    ) selected
    where menu_id is not null
    on conflict (role_id, menu_id) do nothing;
  end if;
end;
$$;
ALTER FUNCTION "public"."set_role_menus"("p_role_id" "uuid", "p_menu_ids" "uuid"[]) OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."set_vehicle_parts_category_level"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  parent_level integer;
begin
  if new.parent_id is null then
    new.category_level := 1;
  else
    select category_level into parent_level
    from public.vehicle_parts_category
    where id = new.parent_id;

    if parent_level is null then
      raise exception 'Parent category % does not exist', new.parent_id;
    end if;

    new.category_level := parent_level + 1;
  end if;

  return new;
end;
$$;
ALTER FUNCTION "public"."set_vehicle_parts_category_level"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."sync_delete_app_user_on_auth_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  delete from public.sys_user
  where auth_user_id = old.id;

  return old;
end;
$$;
ALTER FUNCTION "public"."sync_delete_app_user_on_auth_delete"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."tms_cancel_order_with_waybill"("p_order_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_order public.tms_order%rowtype;
begin
  select *
  into v_order
  from public.tms_order
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order does not exist or cannot be accessed';
  end if;

  if v_order.order_status in ('signed', 'completed', 'cancelled') then
    raise exception 'Signed, completed, or cancelled orders cannot be cancelled';
  end if;

  update public.tms_order
  set order_status = 'cancelled',
      dispatch_status = 'cancelled'
  where id = v_order.id;

  update public.tms_waybill
  set status = 'cancelled',
      cancelled_at = coalesce(cancelled_at, now())
  where order_id = v_order.id
     or (
       tenant_id = v_order.tenant_id
       and waybill_no = v_order.order_no
     );
end;
$$;
ALTER FUNCTION "public"."tms_cancel_order_with_waybill"("p_order_id" "uuid") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."tms_cancel_orders_with_waybills"("p_order_ids" "uuid"[]) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_order_id uuid;
begin
  foreach v_order_id in array p_order_ids loop
    perform public.tms_cancel_order_with_waybill(v_order_id);
  end loop;
end;
$$;
ALTER FUNCTION "public"."tms_cancel_orders_with_waybills"("p_order_ids" "uuid"[]) OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."tms_complete_order_with_waybill"("p_order_id" "uuid", "p_signed_cod_amount" numeric DEFAULT 0, "p_receipt_image_urls" "jsonb" DEFAULT '[]'::"jsonb", "p_signed_at" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_order public.tms_order%rowtype;
  v_waybill public.tms_waybill%rowtype;
  v_completed_at timestamptz;
begin
  select *
  into v_order
  from public.tms_order
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order does not exist or cannot be accessed';
  end if;

  if v_order.order_status not in ('signed', 'completed') then
    raise exception 'Only a pending-signature order can be signed';
  end if;

  select *
  into v_waybill
  from public.tms_waybill
  where order_id = v_order.id
     or (
       order_id is null
       and tenant_id = v_order.tenant_id
       and waybill_no = v_order.order_no
     )
  for update;

  if not found then
    raise exception 'No linked waybill was found';
  end if;

  if v_waybill.status not in ('signed', 'completed') then
    raise exception 'Only a pending-signature waybill can be completed';
  end if;

  v_completed_at := coalesce(p_signed_at, v_waybill.completed_at, now());

  if v_waybill.status = 'signed' then
    update public.tms_waybill
    set status = 'completed',
        completed_at = v_completed_at
    where id = v_waybill.id;

    insert into public.tms_waybill_event (
      tenant_id,
      waybill_id,
      event_type,
      event_time,
      operator_name,
      location_text,
      payload
    )
    values (
      v_waybill.tenant_id,
      v_waybill.id,
      'completed',
      v_completed_at,
      'Web端签收',
      concat_ws(' - ', v_waybill.origin_city, v_waybill.destination_city),
      jsonb_build_object('action', 'web_sign', 'source', 'web')
    );
  end if;

  update public.tms_order
  set order_status = 'completed',
      signed_cod_amount = coalesce(p_signed_cod_amount, 0),
      receipt_image_urls = coalesce(p_receipt_image_urls, receipt_image_urls, '[]'::jsonb),
      signed_at = v_completed_at
  where id = v_order.id;
end;
$$;
ALTER FUNCTION "public"."tms_complete_order_with_waybill"("p_order_id" "uuid", "p_signed_cod_amount" numeric, "p_receipt_image_urls" "jsonb", "p_signed_at" timestamp with time zone) OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."tms_confirm_waybill_departure"("p_order_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_order public.tms_order%rowtype;
  v_waybill public.tms_waybill%rowtype;
  v_departed_at timestamptz;
begin
  select *
  into v_order
  from public.tms_order
  where id = p_order_id;

  if not found then
    raise exception 'Order does not exist or cannot be accessed';
  end if;

  select *
  into v_waybill
  from public.tms_waybill
  where order_id = v_order.id
     or (
       order_id is null
       and tenant_id = v_order.tenant_id
       and waybill_no = v_order.order_no
     )
  for update;

  if not found then
    raise exception 'No linked waybill was found';
  end if;

  if v_waybill.status <> 'loading' then
    raise exception 'Only a waiting-departure waybill can be confirmed as departed';
  end if;

  v_departed_at := coalesce(v_waybill.departed_at, now());

  update public.tms_waybill
  set status = 'transporting',
      departed_at = v_departed_at
  where id = v_waybill.id;

  insert into public.tms_waybill_event (
    tenant_id,
    waybill_id,
    event_type,
    event_time,
    operator_name,
    location_text,
    payload
  )
  values (
    v_waybill.tenant_id,
    v_waybill.id,
    'departed',
    v_departed_at,
    'Web端确认发车',
    concat_ws(' - ', v_waybill.origin_city, v_waybill.destination_city),
    jsonb_build_object('action', 'confirm_departure', 'source', 'web')
  );
end;
$$;
ALTER FUNCTION "public"."tms_confirm_waybill_departure"("p_order_id" "uuid") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."tms_delete_order_with_waybill"("p_order_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_order public.tms_order%rowtype;
begin
  select *
  into v_order
  from public.tms_order
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order does not exist or cannot be accessed';
  end if;

  delete from public.tms_waybill
  where order_id = v_order.id
     or (
       tenant_id = v_order.tenant_id
       and waybill_no = v_order.order_no
     );

  delete from public.tms_order
  where id = v_order.id;
end;
$$;
ALTER FUNCTION "public"."tms_delete_order_with_waybill"("p_order_id" "uuid") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."tms_delete_orders_with_waybills"("p_order_ids" "uuid"[]) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_order_id uuid;
begin
  foreach v_order_id in array p_order_ids loop
    perform public.tms_delete_order_with_waybill(v_order_id);
  end loop;
end;
$$;
ALTER FUNCTION "public"."tms_delete_orders_with_waybills"("p_order_ids" "uuid"[]) OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."trg_set_create_time_and_by"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- set create_time if column exists and is null
  IF TG_ARGV[0] = 'true' THEN
    BEGIN
      IF NEW.create_time IS NULL THEN
        NEW.create_time := now();
      END IF;
    EXCEPTION WHEN undefined_column THEN
      NULL;
    END;
  END IF;

  -- set create_by if column exists and is null
  -- Use auth.jwt() ->> 'email' as the source of truth
  IF TG_ARGV[1] = 'true' THEN
    BEGIN
      IF NEW.create_by IS NULL OR NEW.create_by = '' THEN
        -- prefer JWT email; fallback to 'unknown' if not present
        NEW.create_by := COALESCE((auth.jwt() ->> 'email'), 'unknown');
      END IF;
    EXCEPTION WHEN undefined_column THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;
ALTER FUNCTION "public"."trg_set_create_time_and_by"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."trg_set_update_time_and_by"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  begin
    new.update_time := now();
  exception when undefined_column then
    null;
  end;

  begin
    new.update_by := coalesce(
      nullif(public.get_app_user_display_name(), ''),
      nullif(auth.jwt() ->> 'email', ''),
      nullif(old.update_by, ''),
      'unknown'
    );
  exception when undefined_column then
    null;
  end;

  return new;
end
$$;
ALTER FUNCTION "public"."trg_set_update_time_and_by"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."trg_set_waybill_child_tenant"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_tenant_id uuid;
begin
  select tenant_id
  into v_tenant_id
  from public.tms_waybill
  where id = new.waybill_id;

  if v_tenant_id is null then
    raise exception 'A waybill event or proof requires a valid parent waybill tenant';
  end if;

  new.tenant_id := v_tenant_id;
  return new;
end;
$$;
ALTER FUNCTION "public"."trg_set_waybill_child_tenant"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."trg_sync_completed_waybill_from_order"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  if new.order_status is not distinct from old.order_status
     or new.order_status <> 'completed' then
    return new;
  end if;

  update public.tms_waybill
  set status = 'completed',
      completed_at = coalesce(completed_at, new.signed_at, now())
  where (
    order_id = new.id
    or (
      order_id is null
      and tenant_id = new.tenant_id
      and waybill_no = new.order_no
    )
  )
    and status = 'signed';

  return new;
end;
$$;
ALTER FUNCTION "public"."trg_sync_completed_waybill_from_order"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."trg_sync_order_terminal_status_from_waybill"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_order_status text;
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  v_order_status := case new.status
    when 'pending' then 'pending_order'
    when 'accepted' then 'pending_pickup'
    when 'loading' then 'pending_pickup'
    when 'transporting' then 'transporting'
    when 'unloading' then 'transporting'
    when 'signed' then 'signed'
    when 'completed' then 'completed'
    when 'cancelled' then 'cancelled'
  end;

  if v_order_status is null then
    return new;
  end if;

  update public.tms_order
  set order_status = v_order_status
  where (new.order_id is not null and id = new.order_id)
     or (
       new.order_id is null
       and tenant_id = new.tenant_id
       and order_no = new.waybill_no
     );

  return new;
end;
$$;
ALTER FUNCTION "public"."trg_sync_order_terminal_status_from_waybill"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."trg_sync_tms_order_status_from_waybill"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  next_order_status text;
begin
  next_order_status :=
    case lower(coalesce(new.status, ''))
      when 'completed' then 'completed'
      when 'signed' then 'completed'
      when 'accepted' then 'transporting'
      when 'loading' then 'transporting'
      when 'loaded' then 'transporting'
      when 'transporting' then 'transporting'
      when 'unloading' then 'transporting'
      when 'pending_pickup' then 'transporting'
      when 'picked' then 'transporting'
      when 'in_transit' then 'transporting'
      when 'running' then 'transporting'
      when 'processing' then 'transporting'
      when 'in_progress' then 'transporting'
      when 'ongoing' then 'transporting'
      when 'pickup' then 'transporting'
      when 'started' then 'transporting'
      when 'active' then 'transporting'
      when 'cancelled' then 'cancelled'
      when 'canceled' then 'cancelled'
      when 'closed' then 'cancelled'
      else null
    end;

  if next_order_status is null then
    return new;
  end if;

  update public.tms_order o
  set
    order_status = next_order_status,
    signed_at = case
      when next_order_status = 'completed' then coalesce(o.signed_at, new.unloaded_at, new.update_time, now())
      else o.signed_at
    end,
    update_time = now(),
    update_by = coalesce(new.update_by, o.update_by)
  where o.tenant_id = new.tenant_id
    and o.order_no = new.waybill_no
    and o.order_status <> 'cancelled'
    and (
      o.order_status is distinct from next_order_status
      or (next_order_status = 'completed' and o.signed_at is null)
    );

  return new;
end;
$$;
ALTER FUNCTION "public"."trg_sync_tms_order_status_from_waybill"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."trg_sync_tms_waybill_cancel_from_order"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if lower(coalesce(new.order_status, '')) not in ('cancelled', 'canceled', 'closed') then
    return new;
  end if;

  update public.tms_waybill w
  set
    status = 'cancelled',
    cancelled_at = coalesce(w.cancelled_at, now()),
    update_time = now(),
    update_by = coalesce(new.update_by, w.update_by)
  where w.tenant_id = new.tenant_id
    and w.waybill_no = new.order_no
    and lower(coalesce(w.status, '')) not in ('cancelled', 'canceled', 'closed');

  return new;
end;
$$;
ALTER FUNCTION "public"."trg_sync_tms_waybill_cancel_from_order"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."trg_validate_tms_waybill_status_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  if new.status = old.status then
    return new;
  end if;

  if (old.status = 'pending' and new.status in ('accepted', 'cancelled'))
     or (old.status = 'accepted' and new.status in ('loading', 'cancelled'))
     or (old.status = 'loading' and new.status in ('transporting', 'cancelled'))
     or (old.status = 'transporting' and new.status in ('unloading', 'cancelled'))
     or (old.status = 'unloading' and new.status in ('signed', 'cancelled'))
     or (old.status = 'signed' and new.status in ('completed', 'cancelled')) then
    return new;
  end if;

  raise exception '运单状态不允许从 % 直接变更为 %', old.status, new.status;
end;
$$;
ALTER FUNCTION "public"."trg_validate_tms_waybill_status_transition"() OWNER TO "postgres";
SET default_tablespace = '';
SET default_table_access_method = "heap";
CREATE TABLE IF NOT EXISTS "public"."sys_attachment" (
    "storage_mode" "text" NOT NULL,
    "origin_name" "text",
    "object_name" "text",
    "hash" "text",
    "mime_type" "text",
    "storage_path" "text",
    "suffix" "text",
    "size_byte" bigint,
    "size_info" character varying(50),
    "url" "text",
    "create_by" "text" NOT NULL,
    "update_by" "text" NOT NULL,
    "create_time" timestamp without time zone DEFAULT "now"() NOT NULL,
    "update_time" timestamp without time zone DEFAULT "now"() NOT NULL,
    "remark" "text" NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT '00000000-0000-0000-0000-000000000001'::"uuid" NOT NULL
);
ALTER TABLE "public"."sys_attachment" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_attachment" IS '数据中心/附件管理';
COMMENT ON COLUMN "public"."sys_attachment"."tenant_id" IS 'Tenant ID';
CREATE TABLE IF NOT EXISTS "public"."sys_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "auth_user_id" "uuid",
    "auth_email" "text",
    "ip" "inet",
    "forwarded_for" "text",
    "user_agent" "text",
    "query_text" "text" NOT NULL,
    "is_write" boolean DEFAULT false NOT NULL,
    "status" "text" NOT NULL,
    "error_message" "text",
    "command_tag" "text",
    "row_count" integer,
    "duration_ms" numeric,
    "tenant_id" "uuid" DEFAULT '00000000-0000-0000-0000-000000000001'::"uuid" NOT NULL,
    "create_by" "text",
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sys_audit_log_status_check" CHECK (("status" = ANY (ARRAY['ok'::"text", 'error'::"text"])))
);
ALTER TABLE "public"."sys_audit_log" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_audit_log" IS 'SQL 控制台审计：记录每次 SQL 执行的调用者/来源/耗时/结果等';
COMMENT ON COLUMN "public"."sys_audit_log"."tenant_id" IS 'Tenant ID';
CREATE TABLE IF NOT EXISTS "public"."sys_dict_type" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying,
    "code" character varying,
    "status" character varying DEFAULT '1'::character varying,
    "create_by" "text" NOT NULL,
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "remark" "text",
    "tenant_id" "uuid" DEFAULT "app_private"."platform_tenant_id"() NOT NULL,
    "parent_id" "uuid",
    "node_type" "text" DEFAULT 'dictionary'::"text" NOT NULL,
    "sort" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "sys_dict_type_node_type_check" CHECK (("node_type" = ANY (ARRAY['directory'::"text", 'dictionary'::"text"])))
);
ALTER TABLE "public"."sys_dict_type" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_dict_type" IS '数据中心/字典类型';
COMMENT ON COLUMN "public"."sys_dict_type"."status" IS '状态:1=正常,2=停用';
COMMENT ON COLUMN "public"."sys_dict_type"."tenant_id" IS 'Tenant ID';
COMMENT ON COLUMN "public"."sys_dict_type"."parent_id" IS '上级字典目录，支持多级目录';
COMMENT ON COLUMN "public"."sys_dict_type"."node_type" IS '节点类型：directory 目录，dictionary 字典类型';
COMMENT ON COLUMN "public"."sys_dict_type"."sort" IS '同级节点排序，值越小越靠前';
CREATE TABLE IF NOT EXISTS "public"."sys_dictionary" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "type_id" "uuid" DEFAULT "gen_random_uuid"(),
    "code" character varying,
    "status" character varying DEFAULT '1'::character varying,
    "create_by" "text" NOT NULL,
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "remark" "text",
    "value" "text",
    "label" "text",
    "i18n" "text",
    "i18n_scope" "text" DEFAULT '1'::"text",
    "color" "text",
    "sort" bigint,
    "tenant_id" "uuid" DEFAULT "app_private"."platform_tenant_id"() NOT NULL,
    "tag_type" "text",
    "parent_id" "uuid",
    CONSTRAINT "sys_dictionary_tag_type_check" CHECK ((("tag_type" IS NULL) OR ("tag_type" = ''::"text") OR ("tag_type" = ANY (ARRAY['primary'::"text", 'success'::"text", 'info'::"text", 'warning'::"text", 'danger'::"text"]))))
);
ALTER TABLE "public"."sys_dictionary" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_dictionary" IS '数据中心/字典';
COMMENT ON COLUMN "public"."sys_dictionary"."status" IS '状态:1=正常,2=停用';
COMMENT ON COLUMN "public"."sys_dictionary"."tenant_id" IS 'Tenant ID';
COMMENT ON COLUMN "public"."sys_dictionary"."tag_type" IS 'Element Plus Tag preset type';
COMMENT ON COLUMN "public"."sys_dictionary"."parent_id" IS '上级字典项，支持省市区等多级字典值';
CREATE TABLE IF NOT EXISTS "public"."sys_menu" (
    "name" "text",
    "path" "text",
    "component" "text",
    "meta" "jsonb" DEFAULT '{}'::"jsonb",
    "sort" integer DEFAULT 0,
    "create_by" "text" NOT NULL,
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "parent_id" "uuid" DEFAULT "gen_random_uuid"(),
    "type" "text"
);
ALTER TABLE "public"."sys_menu" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_menu" IS '系统管理/菜单管理';
COMMENT ON COLUMN "public"."sys_menu"."sort" IS '排序';
COMMENT ON COLUMN "public"."sys_menu"."type" IS '菜单类型  folder | menu | button';
CREATE TABLE IF NOT EXISTS "public"."sys_param" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "param_name" "text" NOT NULL,
    "param_key" "text" NOT NULL,
    "group_code" "text" NOT NULL,
    "group_name" "text" NOT NULL,
    "param_type" "text" NOT NULL,
    "default_value" "text",
    "param_value" "text" DEFAULT ''::"text" NOT NULL,
    "extend_config" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "builtin" boolean DEFAULT false NOT NULL,
    "sort" integer DEFAULT 1 NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    CONSTRAINT "sys_param_extend_config_object_check" CHECK (("jsonb_typeof"("extend_config") = 'object'::"text")),
    CONSTRAINT "sys_param_group_code_format_check" CHECK (("group_code" ~ '^[a-z][a-z0-9_]*$'::"text")),
    CONSTRAINT "sys_param_key_format_check" CHECK (("param_key" ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'::"text")),
    CONSTRAINT "sys_param_sort_check" CHECK (("sort" >= 0)),
    CONSTRAINT "sys_param_type_check" CHECK (("param_type" = ANY (ARRAY['single_text'::"text", 'multi_text'::"text", 'number'::"text", 'boolean'::"text", 'json'::"text"])))
);
ALTER TABLE "public"."sys_param" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."sys_role" (
    "role_name" "text" NOT NULL,
    "role_code" "text" NOT NULL,
    "description" "text",
    "enabled" boolean DEFAULT true NOT NULL,
    "create_by" "text" NOT NULL,
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."sys_role" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_role" IS '系统管理/角色管理';
COMMENT ON COLUMN "public"."sys_role"."tenant_id" IS 'Tenant ID';
CREATE TABLE IF NOT EXISTS "public"."sys_role_menu" (
    "permission" "jsonb" DEFAULT '{}'::"jsonb",
    "create_by" "text" NOT NULL,
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "role_id" "uuid",
    "menu_id" "uuid",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."sys_role_menu" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_role_menu" IS '角色菜单表';
COMMENT ON COLUMN "public"."sys_role_menu"."tenant_id" IS 'Tenant ID';
CREATE TABLE IF NOT EXISTS "public"."sys_tenant" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_code" "text" NOT NULL,
    "tenant_name" "text" NOT NULL,
    "status" "text" DEFAULT '1'::"text" NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."sys_tenant" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_tenant" IS 'Tenant';
COMMENT ON COLUMN "public"."sys_tenant"."tenant_code" IS 'Tenant code';
COMMENT ON COLUMN "public"."sys_tenant"."tenant_name" IS 'Tenant name';
COMMENT ON COLUMN "public"."sys_tenant"."status" IS 'Status: 1 enabled, 2 disabled';
CREATE TABLE IF NOT EXISTS "public"."sys_user" (
    "user_name" "text",
    "nick_name" "text",
    "user_gender" "text",
    "user_phone" "text",
    "user_email" "text" NOT NULL,
    "status" "text" DEFAULT '1'::"text",
    "create_by" "text" NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "extra" "jsonb" DEFAULT '{}'::"jsonb",
    "user_roles" "text"[],
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "auth_user_id" "uuid",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_type" character varying,
    "remark" "text",
    "avatar" "text",
    "tenant_id" "uuid" DEFAULT "app_private"."default_register_tenant_id"() NOT NULL
);
ALTER TABLE "public"."sys_user" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_user" IS '系统管理/用户管理';
COMMENT ON COLUMN "public"."sys_user"."user_type" IS '用户类型 1 系统用户 2 普通用户';
COMMENT ON COLUMN "public"."sys_user"."tenant_id" IS 'Tenant ID';
CREATE TABLE IF NOT EXISTS "public"."sys_user_tenant" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "role_codes" "text"[] DEFAULT ARRAY[]::"text"[] NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "status" "text" DEFAULT '1'::"text" NOT NULL,
    "remark" "text",
    "create_by" "text" NOT NULL,
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE ONLY "public"."sys_user_tenant" FORCE ROW LEVEL SECURITY;
ALTER TABLE "public"."sys_user_tenant" OWNER TO "postgres";
COMMENT ON TABLE "public"."sys_user_tenant" IS '用户租户成员关系表';
COMMENT ON COLUMN "public"."sys_user_tenant"."user_id" IS '用户ID';
COMMENT ON COLUMN "public"."sys_user_tenant"."tenant_id" IS '租户ID';
COMMENT ON COLUMN "public"."sys_user_tenant"."role_codes" IS '当前租户下的角色编码列表';
COMMENT ON COLUMN "public"."sys_user_tenant"."is_default" IS '是否默认租户';
COMMENT ON COLUMN "public"."sys_user_tenant"."status" IS '状态：1启用，0禁用';
CREATE SEQUENCE IF NOT EXISTS "public"."tms_cargo_code_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "public"."tms_cargo_code_seq" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."tms_cargo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cargo_code" "text" DEFAULT ('CG'::"text" || "lpad"(("nextval"('"public"."tms_cargo_code_seq"'::"regclass"))::"text", 8, '0'::"text")) NOT NULL,
    "cargo_name" "text" NOT NULL,
    "unit" "text" NOT NULL,
    "length_m" numeric(10,2),
    "width_m" numeric(10,2),
    "height_m" numeric(10,2),
    "volume_m3" numeric(12,3),
    "weight_kg" numeric(12,2),
    "value_amount" numeric(14,2),
    "enabled" boolean DEFAULT true NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    CONSTRAINT "tms_cargo_height_nonnegative" CHECK ((("height_m" IS NULL) OR ("height_m" >= (0)::numeric))),
    CONSTRAINT "tms_cargo_length_nonnegative" CHECK ((("length_m" IS NULL) OR ("length_m" >= (0)::numeric))),
    CONSTRAINT "tms_cargo_unit_check" CHECK (("unit" = ANY (ARRAY['piece'::"text", 'box'::"text", 'bottle'::"text", 'item'::"text", 'set'::"text"]))),
    CONSTRAINT "tms_cargo_value_nonnegative" CHECK ((("value_amount" IS NULL) OR ("value_amount" >= (0)::numeric))),
    CONSTRAINT "tms_cargo_volume_nonnegative" CHECK ((("volume_m3" IS NULL) OR ("volume_m3" >= (0)::numeric))),
    CONSTRAINT "tms_cargo_weight_nonnegative" CHECK ((("weight_kg" IS NULL) OR ("weight_kg" >= (0)::numeric))),
    CONSTRAINT "tms_cargo_width_nonnegative" CHECK ((("width_m" IS NULL) OR ("width_m" >= (0)::numeric)))
);
ALTER TABLE "public"."tms_cargo" OWNER TO "postgres";
CREATE SEQUENCE IF NOT EXISTS "public"."tms_carrier_code_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "public"."tms_carrier_code_seq" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."tms_carrier" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "carrier_code" "text" DEFAULT ('CR'::"text" || "lpad"(("nextval"('"public"."tms_carrier_code_seq"'::"regclass"))::"text", 8, '0'::"text")) NOT NULL,
    "company_name" "text" NOT NULL,
    "carrier_type" "text" NOT NULL,
    "business_license_no" "text",
    "tax_registration_no" "text",
    "legal_representative" "text",
    "region" "text",
    "address_detail" "text",
    "postal_code" "text",
    "enabled" boolean DEFAULT true NOT NULL,
    "business_license_url" "text",
    "driver_count" integer DEFAULT 0 NOT NULL,
    "vehicle_count" integer DEFAULT 0 NOT NULL,
    "contact_name" "text",
    "contact_phone" "text",
    "contact_department" "text",
    "contact_position" "text",
    "contact_email" "text",
    "contact_qq" "text",
    "invoice_title" "text",
    "tax_no" "text",
    "bank_name" "text",
    "bank_account_name" "text",
    "bank_account" "text",
    "signed_contract" boolean DEFAULT false NOT NULL,
    "contract_attachment_url" "text",
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    CONSTRAINT "tms_carrier_driver_count_check" CHECK (("driver_count" >= 0)),
    CONSTRAINT "tms_carrier_vehicle_count_check" CHECK (("vehicle_count" >= 0))
);
ALTER TABLE "public"."tms_carrier" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."tms_carrier_price" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "carrier_id" "uuid" NOT NULL,
    "driver_id" "uuid",
    "vehicle_id" "uuid",
    "origin_region" "text" NOT NULL,
    "destination_region" "text" NOT NULL,
    "transport_mode" "text" NOT NULL,
    "contact_name" "text",
    "contact_phone" "text",
    "driver_name" "text",
    "driver_phone" "text",
    "plate_no" "text",
    "vehicle_type" "text",
    "vehicle_length" "text",
    "cargo_items" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "cargo_quantity_total" numeric DEFAULT 0 NOT NULL,
    "cargo_volume_total" numeric DEFAULT 0 NOT NULL,
    "cargo_weight_total" numeric DEFAULT 0 NOT NULL,
    "billing_method" "text" NOT NULL,
    "transport_cost" numeric DEFAULT 0 NOT NULL,
    "split_transport_fee" numeric DEFAULT 0 NOT NULL,
    "loading_fee" numeric DEFAULT 0 NOT NULL,
    "package_fee" numeric DEFAULT 0 NOT NULL,
    "other_fee" numeric DEFAULT 0 NOT NULL,
    "total_fee" numeric DEFAULT 0 NOT NULL,
    "cash_amount" numeric DEFAULT 0 NOT NULL,
    "prepaid_amount" numeric DEFAULT 0 NOT NULL,
    "collect_amount" numeric DEFAULT 0 NOT NULL,
    "periodic_amount" numeric DEFAULT 0 NOT NULL,
    "payment_total" numeric DEFAULT 0 NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    CONSTRAINT "tms_carrier_price_amounts_nonnegative" CHECK ((("cargo_quantity_total" >= (0)::numeric) AND ("cargo_volume_total" >= (0)::numeric) AND ("cargo_weight_total" >= (0)::numeric) AND ("transport_cost" >= (0)::numeric) AND ("split_transport_fee" >= (0)::numeric) AND ("loading_fee" >= (0)::numeric) AND ("package_fee" >= (0)::numeric) AND ("other_fee" >= (0)::numeric) AND ("total_fee" >= (0)::numeric) AND ("cash_amount" >= (0)::numeric) AND ("prepaid_amount" >= (0)::numeric) AND ("collect_amount" >= (0)::numeric) AND ("periodic_amount" >= (0)::numeric) AND ("payment_total" >= (0)::numeric))),
    CONSTRAINT "tms_carrier_price_billing_method_not_blank" CHECK (("btrim"("billing_method") <> ''::"text")),
    CONSTRAINT "tms_carrier_price_cargo_items_array_check" CHECK (("jsonb_typeof"("cargo_items") = 'array'::"text")),
    CONSTRAINT "tms_carrier_price_destination_not_blank" CHECK (("btrim"("destination_region") <> ''::"text")),
    CONSTRAINT "tms_carrier_price_origin_not_blank" CHECK (("btrim"("origin_region") <> ''::"text")),
    CONSTRAINT "tms_carrier_price_transport_mode_not_blank" CHECK (("btrim"("transport_mode") <> ''::"text"))
);
ALTER TABLE "public"."tms_carrier_price" OWNER TO "postgres";
CREATE SEQUENCE IF NOT EXISTS "public"."tms_contract_no_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "public"."tms_contract_no_seq" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."tms_contract" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contract_no" "text" DEFAULT (('HT'::"text" || "to_char"("now"(), 'YYYYMM'::"text")) || "lpad"(("nextval"('"public"."tms_contract_no_seq"'::"regclass"))::"text", 4, '0'::"text")) NOT NULL,
    "contract_name" "text" NOT NULL,
    "contract_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "carrier_id" "uuid" NOT NULL,
    "contact_name" "text",
    "waybill_no" "text",
    "billing_method" "text" NOT NULL,
    "contract_amount" numeric(14,2),
    "sign_time" timestamp with time zone NOT NULL,
    "handler" "text" NOT NULL,
    "contract_description" "text",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    CONSTRAINT "tms_contract_amount_nonnegative" CHECK ((("contract_amount" IS NULL) OR ("contract_amount" >= (0)::numeric))),
    CONSTRAINT "tms_contract_attachments_array_check" CHECK (("jsonb_typeof"("attachments") = 'array'::"text")),
    CONSTRAINT "tms_contract_billing_method_check" CHECK (("billing_method" = ANY (ARRAY['by_vehicle'::"text", 'by_weight'::"text", 'by_volume'::"text"]))),
    CONSTRAINT "tms_contract_status_check" CHECK (("contract_status" = ANY (ARRAY['draft'::"text", 'pending'::"text", 'approved'::"text", 'rejected'::"text", 'terminated'::"text"])))
);
ALTER TABLE "public"."tms_contract" OWNER TO "postgres";
CREATE SEQUENCE IF NOT EXISTS "public"."tms_customer_code_seq"
    START WITH 1001
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE "public"."tms_customer_code_seq" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."tms_customer" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_code" "text" DEFAULT ('C'::"text" || "lpad"(("nextval"('"public"."tms_customer_code_seq"'::"regclass"))::"text", 8, '0'::"text")) NOT NULL,
    "customer_name" "text" NOT NULL,
    "industry" "text",
    "customer_level" "text",
    "tags" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "region" "text",
    "address_detail" "text",
    "postal_code" "text",
    "enabled" boolean DEFAULT true NOT NULL,
    "contact_name" "text",
    "contact_phone" "text",
    "contact_department" "text",
    "contact_position" "text",
    "contact_email" "text",
    "contact_qq" "text",
    "invoice_title" "text",
    "tax_no" "text",
    "bank_name" "text",
    "bank_account" "text",
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "region_adcode" "text",
    "longitude" numeric(10,6),
    "latitude" numeric(10,6),
    "coordinate_system" "text",
    "coordinate_source" "text",
    "coordinate_status" "text",
    "geocode_provider" "text",
    "geocoded_at" timestamp with time zone,
    CONSTRAINT "tms_customer_name_not_blank" CHECK (("btrim"("customer_name") <> ''::"text"))
);
ALTER TABLE "public"."tms_customer" OWNER TO "postgres";
COMMENT ON TABLE "public"."tms_customer" IS 'TMS运输管理系统/基础资料/客户管理';
COMMENT ON COLUMN "public"."tms_customer"."customer_code" IS '客户编号';
COMMENT ON COLUMN "public"."tms_customer"."tags" IS '客户标签字典值数组';
COMMENT ON COLUMN "public"."tms_customer"."region_adcode" IS 'Customer address region adcode';
COMMENT ON COLUMN "public"."tms_customer"."longitude" IS 'Customer address longitude';
COMMENT ON COLUMN "public"."tms_customer"."latitude" IS 'Customer address latitude';
COMMENT ON COLUMN "public"."tms_customer"."coordinate_system" IS 'Customer address coordinate system';
COMMENT ON COLUMN "public"."tms_customer"."coordinate_source" IS 'Customer address coordinate source';
COMMENT ON COLUMN "public"."tms_customer"."coordinate_status" IS 'Customer address coordinate status';
COMMENT ON COLUMN "public"."tms_customer"."geocode_provider" IS 'Customer address geocode provider';
COMMENT ON COLUMN "public"."tms_customer"."geocoded_at" IS 'Customer address geocoded timestamp';
CREATE TABLE IF NOT EXISTS "public"."tms_customer_address" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "address_type" "text" NOT NULL,
    "contact_name" "text" NOT NULL,
    "contact_phone" "text" NOT NULL,
    "region" "text" NOT NULL,
    "address_detail" "text" NOT NULL,
    "postal_code" "text",
    "is_default" boolean DEFAULT false NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "region_adcode" "text",
    "longitude" numeric(11,7),
    "latitude" numeric(10,7),
    "coordinate_system" "text" DEFAULT 'gcj02'::"text" NOT NULL,
    "coordinate_source" "text",
    "coordinate_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "geocode_provider" "text",
    "geocoded_at" timestamp with time zone,
    CONSTRAINT "tms_customer_address_contact_not_blank" CHECK (("btrim"("contact_name") <> ''::"text")),
    CONSTRAINT "tms_customer_address_detail_not_blank" CHECK (("btrim"("address_detail") <> ''::"text")),
    CONSTRAINT "tms_customer_address_latitude_check" CHECK ((("latitude" IS NULL) OR (("latitude" >= ('-90'::integer)::numeric) AND ("latitude" <= (90)::numeric)))),
    CONSTRAINT "tms_customer_address_longitude_check" CHECK ((("longitude" IS NULL) OR (("longitude" >= ('-180'::integer)::numeric) AND ("longitude" <= (180)::numeric)))),
    CONSTRAINT "tms_customer_address_type_check" CHECK (("address_type" = ANY (ARRAY['shipping'::"text", 'receiving'::"text"])))
);
ALTER TABLE "public"."tms_customer_address" OWNER TO "postgres";
COMMENT ON TABLE "public"."tms_customer_address" IS 'TMS运输管理系统/基础资料/客户地址';
COMMENT ON COLUMN "public"."tms_customer_address"."region_adcode" IS 'Administrative region code, preferably AMap adcode.';
COMMENT ON COLUMN "public"."tms_customer_address"."longitude" IS 'Address longitude in coordinate_system.';
COMMENT ON COLUMN "public"."tms_customer_address"."latitude" IS 'Address latitude in coordinate_system.';
COMMENT ON COLUMN "public"."tms_customer_address"."coordinate_system" IS 'Coordinate system: gcj02, wgs84, bd09, etc.';
COMMENT ON COLUMN "public"."tms_customer_address"."coordinate_source" IS 'Coordinate source: geocode, map_pick, import, etc.';
COMMENT ON COLUMN "public"."tms_customer_address"."coordinate_status" IS 'Coordinate status: pending, located, failed, unconfirmed.';
COMMENT ON COLUMN "public"."tms_customer_address"."geocode_provider" IS 'Geocoding provider, such as amap.';
COMMENT ON COLUMN "public"."tms_customer_address"."geocoded_at" IS 'Time when address was last geocoded.';
CREATE TABLE IF NOT EXISTS "public"."tms_customer_price" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "origin_region" "text" NOT NULL,
    "destination_region" "text" NOT NULL,
    "transport_type" "text" NOT NULL,
    "cargo_type" "text",
    "shipping_contact_name" "text" NOT NULL,
    "shipping_contact_phone" "text" NOT NULL,
    "shipping_address_detail" "text" NOT NULL,
    "receiving_contact_name" "text" NOT NULL,
    "receiving_contact_phone" "text" NOT NULL,
    "receiving_address_detail" "text" NOT NULL,
    "cargo_items" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "cargo_quantity_total" numeric(14,2) DEFAULT 0 NOT NULL,
    "cargo_volume_total" numeric(14,3) DEFAULT 0 NOT NULL,
    "cargo_weight_total" numeric(14,2) DEFAULT 0 NOT NULL,
    "vehicle_type" "text",
    "vehicle_length" "text",
    "vehicle_count" integer,
    "billing_method" "text" NOT NULL,
    "transport_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "insurance_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "package_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "loading_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "transfer_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "fuel_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "service_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "other_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "total_fee" numeric(14,2) DEFAULT 0 NOT NULL,
    "cash_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "prepaid_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "collect_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "periodic_amount" numeric(14,2) DEFAULT 0 NOT NULL,
    "payment_total" numeric(14,2) DEFAULT 0 NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "shipping_address_id" "uuid",
    "receiving_address_id" "uuid",
    "shipping_longitude" numeric,
    "shipping_latitude" numeric,
    "receiving_longitude" numeric,
    "receiving_latitude" numeric,
    CONSTRAINT "tms_customer_price_amounts_nonnegative" CHECK ((("cargo_quantity_total" >= (0)::numeric) AND ("cargo_volume_total" >= (0)::numeric) AND ("cargo_weight_total" >= (0)::numeric) AND ("transport_fee" >= (0)::numeric) AND ("insurance_fee" >= (0)::numeric) AND ("package_fee" >= (0)::numeric) AND ("loading_fee" >= (0)::numeric) AND ("transfer_fee" >= (0)::numeric) AND ("fuel_fee" >= (0)::numeric) AND ("service_fee" >= (0)::numeric) AND ("other_fee" >= (0)::numeric) AND ("total_fee" >= (0)::numeric) AND ("cash_amount" >= (0)::numeric) AND ("prepaid_amount" >= (0)::numeric) AND ("collect_amount" >= (0)::numeric) AND ("periodic_amount" >= (0)::numeric) AND ("payment_total" >= (0)::numeric))),
    CONSTRAINT "tms_customer_price_billing_method_not_blank" CHECK (("btrim"("billing_method") <> ''::"text")),
    CONSTRAINT "tms_customer_price_cargo_items_array_check" CHECK (("jsonb_typeof"("cargo_items") = 'array'::"text")),
    CONSTRAINT "tms_customer_price_destination_not_blank" CHECK (("btrim"("destination_region") <> ''::"text")),
    CONSTRAINT "tms_customer_price_origin_not_blank" CHECK (("btrim"("origin_region") <> ''::"text")),
    CONSTRAINT "tms_customer_price_receiving_address_not_blank" CHECK (("btrim"("receiving_address_detail") <> ''::"text")),
    CONSTRAINT "tms_customer_price_receiving_contact_not_blank" CHECK (("btrim"("receiving_contact_name") <> ''::"text")),
    CONSTRAINT "tms_customer_price_receiving_phone_not_blank" CHECK (("btrim"("receiving_contact_phone") <> ''::"text")),
    CONSTRAINT "tms_customer_price_shipping_address_not_blank" CHECK (("btrim"("shipping_address_detail") <> ''::"text")),
    CONSTRAINT "tms_customer_price_shipping_contact_not_blank" CHECK (("btrim"("shipping_contact_name") <> ''::"text")),
    CONSTRAINT "tms_customer_price_shipping_phone_not_blank" CHECK (("btrim"("shipping_contact_phone") <> ''::"text")),
    CONSTRAINT "tms_customer_price_transport_type_not_blank" CHECK (("btrim"("transport_type") <> ''::"text")),
    CONSTRAINT "tms_customer_price_vehicle_count_nonnegative" CHECK ((("vehicle_count" IS NULL) OR ("vehicle_count" >= 0)))
);
ALTER TABLE "public"."tms_customer_price" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."tms_driver" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "carrier_id" "uuid" NOT NULL,
    "driver_name" character varying(50) NOT NULL,
    "phone" character varying(20) NOT NULL,
    "gender" character varying(20) NOT NULL,
    "id_card_no" character varying(30) NOT NULL,
    "license_type" character varying(20) NOT NULL,
    "license_expire_date" "date",
    "home_address" character varying(255),
    "emergency_contact_name" character varying(50),
    "emergency_contact_phone" character varying(20),
    "enabled" boolean DEFAULT true NOT NULL,
    "id_card_front_url" "text",
    "id_card_back_url" "text",
    "driver_license_front_url" "text",
    "driver_license_back_url" "text",
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "driver_type" character varying(20) DEFAULT 'primary'::character varying NOT NULL,
    CONSTRAINT "tms_driver_driver_type_check" CHECK ((("driver_type")::"text" = ANY ((ARRAY['primary'::character varying, 'secondary'::character varying])::"text"[])))
);
ALTER TABLE "public"."tms_driver" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."tms_order" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_no" "text" NOT NULL,
    "cargo_no" "text",
    "order_status" "text" DEFAULT 'created'::"text" NOT NULL,
    "origin_station" "text" NOT NULL,
    "destination_station" "text" NOT NULL,
    "transfer_station" "text",
    "delivery_method" "text" NOT NULL,
    "shipping_customer_id" "uuid",
    "receiving_customer_id" "uuid",
    "shipping_contact_name" "text" NOT NULL,
    "shipping_contact_phone" "text" NOT NULL,
    "shipping_address_detail" "text" NOT NULL,
    "receiving_contact_name" "text" NOT NULL,
    "receiving_contact_phone" "text" NOT NULL,
    "receiving_address_detail" "text" NOT NULL,
    "cargo_items" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "cargo_quantity_total" numeric DEFAULT 0 NOT NULL,
    "cargo_weight_total" numeric DEFAULT 0 NOT NULL,
    "cargo_volume_total" numeric DEFAULT 0 NOT NULL,
    "transport_fee" numeric DEFAULT 0 NOT NULL,
    "delivery_fee" numeric DEFAULT 0 NOT NULL,
    "unloading_fee" numeric DEFAULT 0 NOT NULL,
    "collect_payment_fee" numeric DEFAULT 0 NOT NULL,
    "transfer_fee" numeric DEFAULT 0 NOT NULL,
    "declared_value" numeric DEFAULT 0 NOT NULL,
    "insurance_fee" numeric DEFAULT 0 NOT NULL,
    "package_fee" numeric DEFAULT 0 NOT NULL,
    "other_fee" numeric DEFAULT 0 NOT NULL,
    "total_fee" numeric DEFAULT 0 NOT NULL,
    "payment_method" "text" NOT NULL,
    "cash_amount" numeric DEFAULT 0 NOT NULL,
    "collect_amount" numeric DEFAULT 0 NOT NULL,
    "monthly_amount" numeric DEFAULT 0 NOT NULL,
    "cod_amount" numeric DEFAULT 0 NOT NULL,
    "handling_fee" numeric DEFAULT 0 NOT NULL,
    "payment_total" numeric DEFAULT 0 NOT NULL,
    "transport_mode" "text",
    "order_remark" "text",
    "image_urls" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "origin_station_id" "uuid",
    "destination_station_id" "uuid",
    "transfer_station_id" "uuid",
    "dispatch_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "dispatch_vehicle_id" "uuid",
    "dispatch_driver_id" "uuid",
    "dispatch_plate_no" "text",
    "dispatch_vehicle_type" "text",
    "dispatch_vehicle_length" "text",
    "dispatch_driver_name" "text",
    "dispatch_driver_phone" "text",
    "planned_departure_time" timestamp with time zone,
    "planned_arrival_time" timestamp with time zone,
    "dispatch_remark" "text",
    "dispatched_at" timestamp with time zone,
    "dispatch_by" "text",
    "signed_cod_amount" numeric DEFAULT 0 NOT NULL,
    "receipt_image_urls" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "signed_at" timestamp with time zone,
    "shipping_address_id" "uuid",
    "receiving_address_id" "uuid",
    "shipping_longitude" numeric,
    "shipping_latitude" numeric,
    "receiving_longitude" numeric,
    "receiving_latitude" numeric,
    CONSTRAINT "tms_order_amounts_nonnegative" CHECK ((("cargo_quantity_total" >= (0)::numeric) AND ("cargo_weight_total" >= (0)::numeric) AND ("cargo_volume_total" >= (0)::numeric) AND ("transport_fee" >= (0)::numeric) AND ("delivery_fee" >= (0)::numeric) AND ("unloading_fee" >= (0)::numeric) AND ("collect_payment_fee" >= (0)::numeric) AND ("transfer_fee" >= (0)::numeric) AND ("declared_value" >= (0)::numeric) AND ("insurance_fee" >= (0)::numeric) AND ("package_fee" >= (0)::numeric) AND ("other_fee" >= (0)::numeric) AND ("total_fee" >= (0)::numeric) AND ("cash_amount" >= (0)::numeric) AND ("collect_amount" >= (0)::numeric) AND ("monthly_amount" >= (0)::numeric) AND ("cod_amount" >= (0)::numeric) AND ("handling_fee" >= (0)::numeric) AND ("payment_total" >= (0)::numeric))),
    CONSTRAINT "tms_order_cargo_items_array_check" CHECK (("jsonb_typeof"("cargo_items") = 'array'::"text")),
    CONSTRAINT "tms_order_delivery_method_not_blank" CHECK (("btrim"("delivery_method") <> ''::"text")),
    CONSTRAINT "tms_order_destination_station_not_blank" CHECK (("btrim"("destination_station") <> ''::"text")),
    CONSTRAINT "tms_order_dispatch_status_check" CHECK (("dispatch_status" = ANY (ARRAY['pending'::"text", 'loaded'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "tms_order_image_urls_array_check" CHECK (("jsonb_typeof"("image_urls") = 'array'::"text")),
    CONSTRAINT "tms_order_order_no_not_blank" CHECK (("btrim"("order_no") <> ''::"text")),
    CONSTRAINT "tms_order_origin_station_not_blank" CHECK (("btrim"("origin_station") <> ''::"text")),
    CONSTRAINT "tms_order_payment_method_not_blank" CHECK (("btrim"("payment_method") <> ''::"text")),
    CONSTRAINT "tms_order_receipt_image_urls_is_array_check" CHECK (("jsonb_typeof"("receipt_image_urls") = 'array'::"text")),
    CONSTRAINT "tms_order_receiving_address_not_blank" CHECK (("btrim"("receiving_address_detail") <> ''::"text")),
    CONSTRAINT "tms_order_receiving_contact_not_blank" CHECK (("btrim"("receiving_contact_name") <> ''::"text")),
    CONSTRAINT "tms_order_receiving_phone_not_blank" CHECK (("btrim"("receiving_contact_phone") <> ''::"text")),
    CONSTRAINT "tms_order_shipping_address_not_blank" CHECK (("btrim"("shipping_address_detail") <> ''::"text")),
    CONSTRAINT "tms_order_shipping_contact_not_blank" CHECK (("btrim"("shipping_contact_name") <> ''::"text")),
    CONSTRAINT "tms_order_shipping_phone_not_blank" CHECK (("btrim"("shipping_contact_phone") <> ''::"text"))
);
ALTER TABLE "public"."tms_order" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."tms_station" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "station_code" "text" NOT NULL,
    "station_name" "text" NOT NULL,
    "station_type" "text" NOT NULL,
    "region_code" "text",
    "manager_name" "text",
    "contact_phone" "text",
    "enabled" boolean DEFAULT true NOT NULL,
    "sort" integer DEFAULT 0 NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    CONSTRAINT "tms_station_code_not_blank" CHECK (("btrim"("station_code") <> ''::"text")),
    CONSTRAINT "tms_station_name_not_blank" CHECK (("btrim"("station_name") <> ''::"text")),
    CONSTRAINT "tms_station_type_not_blank" CHECK (("btrim"("station_type") <> ''::"text"))
);
ALTER TABLE "public"."tms_station" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."tms_waybill" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "waybill_no" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "carrier_id" "uuid",
    "driver_id" "uuid",
    "vehicle_id" "uuid",
    "cargo_id" "uuid",
    "shipper_address_id" "uuid",
    "receiver_address_id" "uuid",
    "origin_city" "text" NOT NULL,
    "destination_city" "text" NOT NULL,
    "shipper_name" "text",
    "shipper_phone" "text",
    "shipper_address" "text" NOT NULL,
    "receiver_name" "text",
    "receiver_phone" "text",
    "receiver_address" "text" NOT NULL,
    "planned_load_time" timestamp with time zone,
    "planned_unload_time" timestamp with time zone,
    "accepted_at" timestamp with time zone,
    "loaded_at" timestamp with time zone,
    "departed_at" timestamp with time zone,
    "arrived_at" timestamp with time zone,
    "unloaded_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "cancelled_at" timestamp with time zone,
    "cargo_name" "text" NOT NULL,
    "cargo_type" "text",
    "cargo_weight_ton" numeric(12,2),
    "cargo_volume_m3" numeric(12,2),
    "cargo_quantity" "text",
    "freight_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "estimated_duration_min" integer,
    "remaining_distance_km" numeric(12,2),
    "route_points" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "pickup_photos" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "delivery_photos" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "receipt_attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "shipper_longitude" numeric,
    "shipper_latitude" numeric,
    "receiver_longitude" numeric,
    "receiver_latitude" numeric,
    "order_id" "uuid",
    CONSTRAINT "tms_waybill_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'loading'::"text", 'transporting'::"text", 'unloading'::"text", 'signed'::"text", 'completed'::"text", 'cancelled'::"text"])))
);
ALTER TABLE "public"."tms_waybill" OWNER TO "postgres";
COMMENT ON TABLE "public"."tms_waybill" IS 'TMS mobile driver waybill task. References existing master data and snapshots historical transport facts.';
CREATE TABLE IF NOT EXISTS "public"."tms_waybill_event" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "waybill_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "event_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "operator_name" "text",
    "location_text" "text",
    "longitude" numeric(12,8),
    "latitude" numeric(12,8),
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tms_waybill_event_event_type_check" CHECK (("event_type" = ANY (ARRAY['created'::"text", 'accepted'::"text", 'loaded'::"text", 'departed'::"text", 'arrived'::"text", 'unloaded'::"text", 'completed'::"text", 'cancelled'::"text", 'photo_uploaded'::"text", 'status_changed'::"text"])))
);
ALTER TABLE "public"."tms_waybill_event" OWNER TO "postgres";
COMMENT ON TABLE "public"."tms_waybill_event" IS 'TMS waybill status/event timeline for driver mobile operations.';
CREATE TABLE IF NOT EXISTS "public"."tms_waybill_proof" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "waybill_id" "uuid" NOT NULL,
    "proof_type" "text" NOT NULL,
    "attachment_id" "uuid",
    "file_url" "text" NOT NULL,
    "file_name" "text",
    "mime_type" "text",
    "file_size" bigint,
    "uploaded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "uploader_name" "text",
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tms_waybill_proof_proof_type_check" CHECK (("proof_type" = ANY (ARRAY['pickup_photo'::"text", 'delivery_photo'::"text", 'receipt'::"text", 'other'::"text"])))
);
ALTER TABLE "public"."tms_waybill_proof" OWNER TO "postgres";
COMMENT ON TABLE "public"."tms_waybill_proof" IS 'TMS waybill pickup/delivery/receipt proof files uploaded by drivers.';
CREATE TABLE IF NOT EXISTS "public"."vehicle_accident_record" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid",
    "plate_no" "text" NOT NULL,
    "company_name" "text",
    "driver_name" "text",
    "accident_time" timestamp with time zone NOT NULL,
    "accident_location" "text",
    "accident_summary" "text" NOT NULL,
    "damage_level" "text",
    "responsibility_type" "text",
    "responsibility_percent" numeric(5,2),
    "company_bear_amount" numeric(12,2),
    "economic_loss" numeric(12,2),
    "reported" boolean DEFAULT false NOT NULL,
    "insurance_reported" boolean DEFAULT false NOT NULL,
    "processed" boolean DEFAULT false NOT NULL,
    "data_source" "text" DEFAULT 'self'::"text" NOT NULL,
    "remark" "text",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."vehicle_accident_record" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."vehicle_archive" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "plate_no" character varying(30) NOT NULL,
    "company_name" character varying(120),
    "self_no" character varying(60),
    "vehicle_type" character varying(80) NOT NULL,
    "origin_type" character varying(20),
    "vin" character varying(80) NOT NULL,
    "manufacturer" character varying(120),
    "brand_model" character varying(120),
    "operation_cert_no" character varying(80),
    "purchase_cert_no" character varying(80),
    "registration_cert_no" character varying(80),
    "vehicle_color" character varying(40),
    "chassis_no" character varying(80),
    "ac_code" character varying(80),
    "gearbox_serial_no" character varying(80),
    "register_date" "date",
    "issue_date" "date",
    "invoice_date" "date",
    "start_use_date" "date",
    "service_years" integer,
    "approved_passenger_count" integer,
    "seat_count" integer,
    "business_type" character varying(80),
    "is_air_conditioned" boolean DEFAULT false NOT NULL,
    "operation_status" character varying(40) DEFAULT 'operating'::character varying NOT NULL,
    "operation_status_change_date" "date",
    "purchase_status" character varying(40),
    "purchase_status_change_date" "date",
    "inspection_start_date" "date",
    "vehicle_level" character varying(80),
    "is_new_energy" boolean DEFAULT false NOT NULL,
    "three_guarantee_mileage" numeric(12,2),
    "three_guarantee_duration" integer,
    "warranty_mileage" numeric(12,2),
    "warranty_duration" integer,
    "remark" character varying(1000),
    "gross_mass" numeric(12,2),
    "curb_weight" numeric(12,2),
    "approved_load_mass" numeric(12,2),
    "overall_length" numeric(12,2),
    "overall_width" numeric(12,2),
    "overall_height" numeric(12,2),
    "platform" character varying(80),
    "front_track" numeric(12,2),
    "rear_track" numeric(12,2),
    "wheelbase" numeric(12,2),
    "axle_count" integer,
    "tire_count" integer,
    "leaf_spring_count" integer,
    "is_double_deck" boolean DEFAULT false NOT NULL,
    "engine_no" character varying(80),
    "engine_model" character varying(120),
    "fuel_type" character varying(40),
    "displacement" numeric(12,2),
    "emission_standard" character varying(80),
    "engine_power" numeric(12,2),
    "rated_torque_speed" numeric(12,2),
    "engine_torque" numeric(12,2),
    "plate_color" character varying(40),
    "transport_industry" character varying(80),
    "operation_type" character varying(80),
    "owner_id" character varying(80),
    "owner_name" character varying(120),
    "owner_phone" character varying(40),
    "terminal_phone" character varying(40),
    "owner_gender" character varying(20),
    "id_card_no" character varying(80),
    "mailing_address" character varying(300),
    "tonnage_or_seat" character varying(80),
    "driver_one_name" character varying(120),
    "driver_one_phone" character varying(40),
    "driver_two_name" character varying(120),
    "driver_two_phone" character varying(40),
    "operation_route" character varying(300),
    "license_plate_code" character varying(80),
    "service_start_time" "date",
    "service_end_time" "date",
    "support_photo" boolean DEFAULT false NOT NULL,
    "vehicle_photo_url" "text",
    "driving_license_front_url" "text",
    "driving_license_back_url" "text",
    "operation_license_url" "text",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "audit_status" character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    "audit_remark" character varying(1000),
    "audit_by" "text",
    "audit_time" timestamp with time zone,
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "carrier_id" "uuid",
    "primary_driver_id" "uuid",
    "secondary_driver_id" "uuid",
    CONSTRAINT "vehicle_archive_distinct_driver_ids_check" CHECK ((("primary_driver_id" IS NULL) OR ("secondary_driver_id" IS NULL) OR ("primary_driver_id" <> "secondary_driver_id")))
);
ALTER TABLE "public"."vehicle_archive" OWNER TO "postgres";
COMMENT ON TABLE "public"."vehicle_archive" IS '车辆档案';
COMMENT ON COLUMN "public"."vehicle_archive"."tenant_id" IS '租户ID';
COMMENT ON COLUMN "public"."vehicle_archive"."plate_no" IS '车牌号';
COMMENT ON COLUMN "public"."vehicle_archive"."audit_status" IS '审核状态：pending/approved/rejected';
CREATE TABLE IF NOT EXISTS "public"."vehicle_inspection" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid",
    "plate_no" "text" NOT NULL,
    "company_name" "text",
    "inspection_no" "text" NOT NULL,
    "inspection_date" "date",
    "inspection_amount" numeric(12,2),
    "vehicle_office" "text",
    "expire_date" "date",
    "compulsory_policy_no" "text" NOT NULL,
    "compulsory_company_id" "uuid",
    "compulsory_company_name" "text",
    "compulsory_insure_date" "date",
    "compulsory_premium" numeric(12,2),
    "compulsory_expire_date" "date",
    "remark" "text",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."vehicle_inspection" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."vehicle_insurance" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid",
    "plate_no" "text" NOT NULL,
    "company_name" "text",
    "commercial_policy_no" "text" NOT NULL,
    "commercial_company_id" "uuid",
    "commercial_company_name" "text",
    "commercial_insure_date" "date",
    "commercial_premium" numeric(12,2),
    "commercial_expire_date" "date",
    "compulsory_policy_no" "text" NOT NULL,
    "compulsory_company_id" "uuid",
    "compulsory_company_name" "text",
    "compulsory_insure_date" "date",
    "compulsory_premium" numeric(12,2),
    "compulsory_expire_date" "date",
    "remark" "text",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."vehicle_insurance" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."vehicle_insurance_company" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_name" "text" NOT NULL,
    "contact_person" "text",
    "contact_phone" "text",
    "region" "text",
    "address_detail" "text",
    "remark" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "create_by" "text",
    "update_by" "text",
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."vehicle_insurance_company" OWNER TO "postgres";
COMMENT ON TABLE "public"."vehicle_insurance_company" IS '车辆管理系统/基础信息/保险公司';
COMMENT ON COLUMN "public"."vehicle_insurance_company"."tenant_id" IS 'Tenant ID';
CREATE TABLE IF NOT EXISTS "public"."vehicle_maintenance_record" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid",
    "plate_no" "text" NOT NULL,
    "company_name" "text",
    "maintenance_no" "text" NOT NULL,
    "maintenance_type" "text" DEFAULT 'repair'::"text" NOT NULL,
    "initiator" "text",
    "start_time" timestamp with time zone NOT NULL,
    "end_time" timestamp with time zone,
    "cost_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "workshop" "text",
    "external_repair" boolean DEFAULT false NOT NULL,
    "remark" "text",
    "items" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."vehicle_maintenance_record" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."vehicle_mileage_record" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid",
    "plate_no" "text" NOT NULL,
    "company_name" "text",
    "start_mileage" numeric,
    "end_mileage" numeric,
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "start_time" timestamp with time zone,
    "end_time" timestamp with time zone,
    "running_mileage" numeric
);
ALTER TABLE "public"."vehicle_mileage_record" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."vehicle_part_usage" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid",
    "plate_no" "text" NOT NULL,
    "company_name" "text",
    "part_id" "uuid",
    "part_type" "text" DEFAULT 'original'::"text" NOT NULL,
    "part_name" "text" NOT NULL,
    "part_code" "text" NOT NULL,
    "category_id" "uuid",
    "category_name" "text",
    "brand" "text",
    "model" "text",
    "unit" "text",
    "quality_category" "text",
    "manufacturer" "text",
    "supplier_id" "uuid",
    "supplier_name" "text",
    "supplier_contact" "text",
    "is_consumable" boolean DEFAULT false NOT NULL,
    "rfid_enabled" boolean DEFAULT false NOT NULL,
    "rfid_tag" "text",
    "enable_mode" "text" DEFAULT 'vehicle'::"text" NOT NULL,
    "enable_date" "date",
    "warranty_mode" "text" DEFAULT 'vehicle'::"text" NOT NULL,
    "warranty_mileage" numeric(12,2),
    "warranty_duration" integer,
    "service_mileage_enabled" boolean DEFAULT false NOT NULL,
    "service_mileage" numeric(12,2),
    "service_years_enabled" boolean DEFAULT false NOT NULL,
    "service_years" integer,
    "used_mileage" numeric(12,2) DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'normal'::"text" NOT NULL,
    "scrap_reason" "text",
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    CONSTRAINT "vehicle_part_usage_enable_date_check" CHECK ((("enable_mode" <> 'date'::"text") OR ("enable_date" IS NOT NULL))),
    CONSTRAINT "vehicle_part_usage_rfid_tag_check" CHECK (((NOT "rfid_enabled") OR (NULLIF(TRIM(BOTH FROM "rfid_tag"), ''::"text") IS NOT NULL))),
    CONSTRAINT "vehicle_part_usage_scrap_reason_check" CHECK ((("status" <> 'scrapped'::"text") OR (NULLIF(TRIM(BOTH FROM "scrap_reason"), ''::"text") IS NOT NULL))),
    CONSTRAINT "vehicle_part_usage_service_life_check" CHECK (("service_mileage_enabled" OR "service_years_enabled")),
    CONSTRAINT "vehicle_part_usage_warranty_check" CHECK ((("warranty_mode" <> 'self'::"text") OR ("warranty_mileage" IS NOT NULL) OR ("warranty_duration" IS NOT NULL)))
);
ALTER TABLE "public"."vehicle_part_usage" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."vehicle_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    "part_name" character varying(100) NOT NULL,
    "part_code" character varying(60) NOT NULL,
    "category_id" "uuid",
    "brand" character varying(80),
    "model" character varying(80),
    "unit" character varying(20) NOT NULL,
    "supplier_id" "uuid",
    "manufacturer" character varying(100),
    "supplier_contact" character varying(100),
    "is_consumable" boolean DEFAULT false NOT NULL,
    "warranty_mileage" numeric(12,2),
    "warranty_duration" integer,
    "service_life" integer,
    "service_mileage" numeric(12,2),
    "status" character varying(1) DEFAULT '1'::character varying NOT NULL,
    "remark" character varying(500),
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "vehicle_parts_service_life_check" CHECK ((("service_life" IS NULL) OR ("service_life" >= 0))),
    CONSTRAINT "vehicle_parts_service_mileage_check" CHECK ((("service_mileage" IS NULL) OR ("service_mileage" >= (0)::numeric))),
    CONSTRAINT "vehicle_parts_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['1'::character varying, '2'::character varying])::"text"[]))),
    CONSTRAINT "vehicle_parts_warranty_duration_check" CHECK ((("warranty_duration" IS NULL) OR ("warranty_duration" >= 0))),
    CONSTRAINT "vehicle_parts_warranty_mileage_check" CHECK ((("warranty_mileage" IS NULL) OR ("warranty_mileage" >= (0)::numeric)))
);
ALTER TABLE "public"."vehicle_parts" OWNER TO "postgres";
COMMENT ON TABLE "public"."vehicle_parts" IS '车辆管理系统/基础信息/零部件';
COMMENT ON COLUMN "public"."vehicle_parts"."tenant_id" IS 'Tenant ID';
COMMENT ON COLUMN "public"."vehicle_parts"."part_name" IS '零部件名称';
COMMENT ON COLUMN "public"."vehicle_parts"."part_code" IS '零部件编码';
COMMENT ON COLUMN "public"."vehicle_parts"."category_id" IS '零部件类别ID';
COMMENT ON COLUMN "public"."vehicle_parts"."brand" IS '品牌';
COMMENT ON COLUMN "public"."vehicle_parts"."model" IS '型号';
COMMENT ON COLUMN "public"."vehicle_parts"."unit" IS '单位';
COMMENT ON COLUMN "public"."vehicle_parts"."supplier_id" IS '供应厂商ID';
COMMENT ON COLUMN "public"."vehicle_parts"."manufacturer" IS '生产厂商';
COMMENT ON COLUMN "public"."vehicle_parts"."supplier_contact" IS '供应商联系人';
COMMENT ON COLUMN "public"."vehicle_parts"."is_consumable" IS '是否易损/耗件';
COMMENT ON COLUMN "public"."vehicle_parts"."warranty_mileage" IS '质保里程，单位：公里';
COMMENT ON COLUMN "public"."vehicle_parts"."warranty_duration" IS '质保时长，单位：个月';
COMMENT ON COLUMN "public"."vehicle_parts"."service_life" IS '使用年限，单位：年';
COMMENT ON COLUMN "public"."vehicle_parts"."service_mileage" IS '使用里程，单位：公里';
COMMENT ON COLUMN "public"."vehicle_parts"."status" IS '状态：1 启用，2 停用';
COMMENT ON COLUMN "public"."vehicle_parts"."remark" IS '备注';
COMMENT ON COLUMN "public"."vehicle_parts"."create_by" IS '创建人';
COMMENT ON COLUMN "public"."vehicle_parts"."create_time" IS '创建时间';
COMMENT ON COLUMN "public"."vehicle_parts"."update_by" IS '更新人';
COMMENT ON COLUMN "public"."vehicle_parts"."update_time" IS '更新时间';
CREATE TABLE IF NOT EXISTS "public"."vehicle_parts_category" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "parent_id" "uuid",
    "category_name" character varying(80) NOT NULL,
    "category_code" character varying(50) NOT NULL,
    "category_level" integer DEFAULT 1 NOT NULL,
    "sort" integer DEFAULT 1 NOT NULL,
    "status" character varying(1) DEFAULT '1'::character varying NOT NULL,
    "remark" character varying(500),
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL,
    CONSTRAINT "vehicle_parts_category_no_self_parent" CHECK ((("parent_id" IS NULL) OR ("parent_id" <> "id"))),
    CONSTRAINT "vehicle_parts_category_sort_check" CHECK ((("sort" >= 0) AND ("sort" <= 9999))),
    CONSTRAINT "vehicle_parts_category_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['1'::character varying, '2'::character varying])::"text"[])))
);
ALTER TABLE "public"."vehicle_parts_category" OWNER TO "postgres";
COMMENT ON TABLE "public"."vehicle_parts_category" IS '车辆零部件类别';
COMMENT ON COLUMN "public"."vehicle_parts_category"."parent_id" IS '上级类别ID';
COMMENT ON COLUMN "public"."vehicle_parts_category"."category_name" IS '类别名称';
COMMENT ON COLUMN "public"."vehicle_parts_category"."category_code" IS '类别编码';
COMMENT ON COLUMN "public"."vehicle_parts_category"."category_level" IS '类别层级';
COMMENT ON COLUMN "public"."vehicle_parts_category"."sort" IS '排序';
COMMENT ON COLUMN "public"."vehicle_parts_category"."status" IS '状态：1 启用，2 停用';
COMMENT ON COLUMN "public"."vehicle_parts_category"."remark" IS '备注';
COMMENT ON COLUMN "public"."vehicle_parts_category"."create_by" IS '创建人';
COMMENT ON COLUMN "public"."vehicle_parts_category"."create_time" IS '创建时间';
COMMENT ON COLUMN "public"."vehicle_parts_category"."update_by" IS '更新人';
COMMENT ON COLUMN "public"."vehicle_parts_category"."update_time" IS '更新时间';
COMMENT ON COLUMN "public"."vehicle_parts_category"."tenant_id" IS 'Tenant ID';
CREATE OR REPLACE VIEW "public"."vehicle_reminder_inspection_expiry" WITH ("security_invoker"='true') AS
 SELECT COALESCE(("id")::"text", (("plate_no" || '-'::"text") || ("expire_date")::"text")) AS "id",
    "id" AS "source_id",
    "vehicle_id",
    "company_name",
    "plate_no",
    "expire_date",
    ("expire_date" - CURRENT_DATE) AS "remaining_days",
    ("expire_date" < CURRENT_DATE) AS "expired"
   FROM "public"."vehicle_inspection"
  WHERE ("expire_date" IS NOT NULL);
ALTER VIEW "public"."vehicle_reminder_inspection_expiry" OWNER TO "postgres";
COMMENT ON VIEW "public"."vehicle_reminder_inspection_expiry" IS 'Vehicle inspection expiry reminder rows generated from real inspection records.';
CREATE OR REPLACE VIEW "public"."vehicle_reminder_insurance_expiry" WITH ("security_invoker"='true') AS
 SELECT (("vehicle_insurance"."id")::"text" || '-commercial'::"text") AS "id",
    "vehicle_insurance"."id" AS "source_id",
    "vehicle_insurance"."vehicle_id",
    "vehicle_insurance"."company_name",
    "vehicle_insurance"."plate_no",
    'commercial'::"text" AS "insurance_type",
    '商业险'::"text" AS "insurance_type_name",
    "vehicle_insurance"."commercial_expire_date" AS "expire_date",
    ("vehicle_insurance"."commercial_expire_date" - CURRENT_DATE) AS "remaining_days",
    ("vehicle_insurance"."commercial_expire_date" < CURRENT_DATE) AS "expired"
   FROM "public"."vehicle_insurance"
  WHERE ("vehicle_insurance"."commercial_expire_date" IS NOT NULL)
UNION ALL
 SELECT (("vehicle_insurance"."id")::"text" || '-compulsory'::"text") AS "id",
    "vehicle_insurance"."id" AS "source_id",
    "vehicle_insurance"."vehicle_id",
    "vehicle_insurance"."company_name",
    "vehicle_insurance"."plate_no",
    'compulsory'::"text" AS "insurance_type",
    '交强险'::"text" AS "insurance_type_name",
    "vehicle_insurance"."compulsory_expire_date" AS "expire_date",
    ("vehicle_insurance"."compulsory_expire_date" - CURRENT_DATE) AS "remaining_days",
    ("vehicle_insurance"."compulsory_expire_date" < CURRENT_DATE) AS "expired"
   FROM "public"."vehicle_insurance"
  WHERE ("vehicle_insurance"."compulsory_expire_date" IS NOT NULL);
ALTER VIEW "public"."vehicle_reminder_insurance_expiry" OWNER TO "postgres";
COMMENT ON VIEW "public"."vehicle_reminder_insurance_expiry" IS 'Vehicle insurance expiry reminder rows generated from real insurance records.';
CREATE OR REPLACE VIEW "public"."vehicle_reminder_maintenance_expiry" WITH ("security_invoker"='true') AS
 WITH "latest_maintenance" AS (
         SELECT "ranked"."id",
            "ranked"."vehicle_id",
            "ranked"."plate_no",
            "ranked"."company_name",
            "ranked"."maintenance_no",
            "ranked"."maintenance_type",
            "ranked"."initiator",
            "ranked"."start_time",
            "ranked"."end_time",
            "ranked"."cost_amount",
            "ranked"."workshop",
            "ranked"."external_repair",
            "ranked"."remark",
            "ranked"."items",
            "ranked"."attachments",
            "ranked"."create_by",
            "ranked"."create_time",
            "ranked"."update_by",
            "ranked"."update_time",
            "ranked"."tenant_id",
            "ranked"."row_no"
           FROM ( SELECT "record"."id",
                    "record"."vehicle_id",
                    "record"."plate_no",
                    "record"."company_name",
                    "record"."maintenance_no",
                    "record"."maintenance_type",
                    "record"."initiator",
                    "record"."start_time",
                    "record"."end_time",
                    "record"."cost_amount",
                    "record"."workshop",
                    "record"."external_repair",
                    "record"."remark",
                    "record"."items",
                    "record"."attachments",
                    "record"."create_by",
                    "record"."create_time",
                    "record"."update_by",
                    "record"."update_time",
                    "record"."tenant_id",
                    "row_number"() OVER (PARTITION BY COALESCE(("record"."vehicle_id")::"text", "record"."plate_no") ORDER BY "record"."start_time" DESC, "record"."create_time" DESC) AS "row_no"
                   FROM "public"."vehicle_maintenance_record" "record"
                  WHERE ("record"."maintenance_type" = 'maintenance'::"text")) "ranked"
          WHERE ("ranked"."row_no" = 1)
        )
 SELECT COALESCE(("maintenance"."id")::"text", (("maintenance"."plate_no" || '-'::"text") || ("maintenance"."start_time")::"text")) AS "id",
    "maintenance"."id" AS "source_id",
    "maintenance"."vehicle_id",
    "maintenance"."company_name",
    "maintenance"."plate_no",
    ("maintenance"."start_time")::"date" AS "current_maintenance_date",
    "latest_mileage"."current_mileage",
    ("maintenance_mileage"."maintenance_mileage" + (5000)::numeric) AS "next_maintenance_mileage",
    (("maintenance"."start_time" + '6 mons'::interval))::"date" AS "next_maintenance_date",
    (("maintenance"."start_time" + '6 mons'::interval))::"date" AS "expire_date",
    ((("maintenance"."start_time" + '6 mons'::interval))::"date" - CURRENT_DATE) AS "remaining_days",
    (((("maintenance"."start_time" + '6 mons'::interval))::"date" < CURRENT_DATE) OR (("latest_mileage"."current_mileage" IS NOT NULL) AND ("maintenance_mileage"."maintenance_mileage" IS NOT NULL) AND ("latest_mileage"."current_mileage" >= ("maintenance_mileage"."maintenance_mileage" + (5000)::numeric)))) AS "expired"
   FROM (("latest_maintenance" "maintenance"
     LEFT JOIN LATERAL ( SELECT COALESCE("mileage"."end_mileage", "mileage"."running_mileage", "mileage"."start_mileage") AS "current_mileage"
           FROM "public"."vehicle_mileage_record" "mileage"
          WHERE (("mileage"."vehicle_id" = "maintenance"."vehicle_id") OR (("maintenance"."vehicle_id" IS NULL) AND ("mileage"."plate_no" = "maintenance"."plate_no")))
          ORDER BY COALESCE("mileage"."end_time", "mileage"."start_time", "mileage"."create_time") DESC
         LIMIT 1) "latest_mileage" ON (true))
     LEFT JOIN LATERAL ( SELECT COALESCE("mileage"."end_mileage", "mileage"."running_mileage", "mileage"."start_mileage") AS "maintenance_mileage"
           FROM "public"."vehicle_mileage_record" "mileage"
          WHERE ((("mileage"."vehicle_id" = "maintenance"."vehicle_id") OR (("maintenance"."vehicle_id" IS NULL) AND ("mileage"."plate_no" = "maintenance"."plate_no"))) AND (COALESCE("mileage"."end_time", "mileage"."start_time", "mileage"."create_time") <= "maintenance"."start_time"))
          ORDER BY COALESCE("mileage"."end_time", "mileage"."start_time", "mileage"."create_time") DESC
         LIMIT 1) "maintenance_mileage" ON (true));
ALTER VIEW "public"."vehicle_reminder_maintenance_expiry" OWNER TO "postgres";
COMMENT ON VIEW "public"."vehicle_reminder_maintenance_expiry" IS 'Vehicle maintenance expiry reminder rows generated from latest real maintenance and mileage records.';
CREATE OR REPLACE VIEW "public"."vehicle_reminder_part_service_life" WITH ("security_invoker"='true') AS
 SELECT COALESCE(("id")::"text", (("plate_no" || '-'::"text") || "part_name")) AS "id",
    "id" AS "source_id",
    "vehicle_id",
    "company_name",
    "plate_no",
    "part_type",
    "part_name",
    "category_name",
    "brand",
    "model",
    "rfid_tag",
    "used_mileage",
    "service_mileage",
    "enable_date" AS "start_use_date",
    "service_years",
    (("enable_date" + "make_interval"("years" => "service_years")))::"date" AS "expire_date",
    ((("enable_date" + "make_interval"("years" => "service_years")))::"date" - CURRENT_DATE) AS "remaining_days",
    (((("enable_date" + "make_interval"("years" => "service_years")))::"date" < CURRENT_DATE) OR ("service_mileage_enabled" AND ("used_mileage" IS NOT NULL) AND ("service_mileage" IS NOT NULL) AND ("used_mileage" >= "service_mileage"))) AS "expired"
   FROM "public"."vehicle_part_usage"
  WHERE ("service_years_enabled" AND ("enable_date" IS NOT NULL) AND ("service_years" IS NOT NULL));
ALTER VIEW "public"."vehicle_reminder_part_service_life" OWNER TO "postgres";
COMMENT ON VIEW "public"."vehicle_reminder_part_service_life" IS 'Vehicle part service-life reminder rows generated from real part usage records.';
CREATE OR REPLACE VIEW "public"."vehicle_reminder_vehicle_service_life" WITH ("security_invoker"='true') AS
 SELECT COALESCE(("id")::"text", ("plate_no")::"text") AS "id",
    "id" AS "source_id",
    "id" AS "vehicle_id",
    "company_name",
    "plate_no",
    "start_use_date",
    "service_years",
    (("start_use_date" + "make_interval"("years" => "service_years")))::"date" AS "expire_date",
    ((("start_use_date" + "make_interval"("years" => "service_years")))::"date" - CURRENT_DATE) AS "remaining_days",
    ((("start_use_date" + "make_interval"("years" => "service_years")))::"date" < CURRENT_DATE) AS "expired"
   FROM "public"."vehicle_archive"
  WHERE ((("audit_status")::"text" = 'approved'::"text") AND ("start_use_date" IS NOT NULL) AND ("service_years" IS NOT NULL));
ALTER VIEW "public"."vehicle_reminder_vehicle_service_life" OWNER TO "postgres";
COMMENT ON VIEW "public"."vehicle_reminder_vehicle_service_life" IS 'Vehicle service-life reminder rows generated from approved vehicle archive records.';
CREATE TABLE IF NOT EXISTS "public"."vehicle_routine_inspection_record" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid",
    "plate_no" "text" NOT NULL,
    "company_name" "text",
    "routine_inspection_no" "text" NOT NULL,
    "inspection_type" "text" DEFAULT 'daily'::"text" NOT NULL,
    "inspection_time" timestamp with time zone NOT NULL,
    "inspector" "text",
    "driver_name" "text",
    "check_condition" "text",
    "check_result" "text" DEFAULT 'qualified'::"text" NOT NULL,
    "handling_method" "text",
    "remark" "text",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."vehicle_routine_inspection_record" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."vehicle_supplier" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "supplier_name" character varying(100) NOT NULL,
    "contact_person" character varying(50),
    "contact_phone" character varying(20),
    "region" character varying(100),
    "address_detail" character varying(200),
    "remark" character varying(500),
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."vehicle_supplier" OWNER TO "postgres";
COMMENT ON TABLE "public"."vehicle_supplier" IS '供应厂商';
COMMENT ON COLUMN "public"."vehicle_supplier"."id" IS '主键 ID';
COMMENT ON COLUMN "public"."vehicle_supplier"."supplier_name" IS '供应厂商名称';
COMMENT ON COLUMN "public"."vehicle_supplier"."contact_person" IS '联系人';
COMMENT ON COLUMN "public"."vehicle_supplier"."contact_phone" IS '联系电话';
COMMENT ON COLUMN "public"."vehicle_supplier"."region" IS '所在地区';
COMMENT ON COLUMN "public"."vehicle_supplier"."address_detail" IS '详细地址';
COMMENT ON COLUMN "public"."vehicle_supplier"."remark" IS '备注';
COMMENT ON COLUMN "public"."vehicle_supplier"."create_by" IS '创建人';
COMMENT ON COLUMN "public"."vehicle_supplier"."create_time" IS '创建时间';
COMMENT ON COLUMN "public"."vehicle_supplier"."update_by" IS '更新人';
COMMENT ON COLUMN "public"."vehicle_supplier"."update_time" IS '更新时间';
COMMENT ON COLUMN "public"."vehicle_supplier"."tenant_id" IS 'Tenant ID';
CREATE TABLE IF NOT EXISTS "public"."vehicle_violation_record" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid",
    "plate_no" "text" NOT NULL,
    "company_name" "text",
    "driver_name" "text",
    "violation_behavior" "text" NOT NULL,
    "violation_time" timestamp with time zone NOT NULL,
    "violation_location" "text",
    "penalty_points" integer DEFAULT 0 NOT NULL,
    "fine_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "processed" boolean DEFAULT false NOT NULL,
    "remark" "text",
    "create_by" "text",
    "create_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "update_by" "text",
    "update_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tenant_id" "uuid" DEFAULT "app_private"."current_user_tenant_id"() NOT NULL
);
ALTER TABLE "public"."vehicle_violation_record" OWNER TO "postgres";
ALTER TABLE ONLY "public"."vehicle_insurance_company"
    ADD CONSTRAINT "insurance_company_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_attachment"
    ADD CONSTRAINT "sys_attachment_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_audit_log"
    ADD CONSTRAINT "sys_audit_log_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_dict_type"
    ADD CONSTRAINT "sys_dict_type_code_key" UNIQUE ("code");
ALTER TABLE ONLY "public"."sys_dict_type"
    ADD CONSTRAINT "sys_dict_type_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_dictionary"
    ADD CONSTRAINT "sys_dictionary_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_menu"
    ADD CONSTRAINT "sys_menu_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_param"
    ADD CONSTRAINT "sys_param_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_role_menu"
    ADD CONSTRAINT "sys_role_menu_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_role_menu"
    ADD CONSTRAINT "sys_role_menu_role_id_menu_id_key" UNIQUE ("role_id", "menu_id");
ALTER TABLE ONLY "public"."sys_role"
    ADD CONSTRAINT "sys_role_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_tenant"
    ADD CONSTRAINT "sys_tenant_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_tenant"
    ADD CONSTRAINT "sys_tenant_tenant_code_key" UNIQUE ("tenant_code");
ALTER TABLE ONLY "public"."sys_user"
    ADD CONSTRAINT "sys_user_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_user_tenant"
    ADD CONSTRAINT "sys_user_tenant_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."sys_user_tenant"
    ADD CONSTRAINT "sys_user_tenant_user_tenant_key" UNIQUE ("user_id", "tenant_id");
ALTER TABLE ONLY "public"."sys_user"
    ADD CONSTRAINT "sys_user_user_email_key" UNIQUE ("user_email");
ALTER TABLE ONLY "public"."tms_cargo"
    ADD CONSTRAINT "tms_cargo_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_cargo"
    ADD CONSTRAINT "tms_cargo_tenant_cargo_name_key" UNIQUE ("tenant_id", "cargo_name");
ALTER TABLE ONLY "public"."tms_carrier"
    ADD CONSTRAINT "tms_carrier_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_carrier_price"
    ADD CONSTRAINT "tms_carrier_price_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_carrier"
    ADD CONSTRAINT "tms_carrier_tenant_code_key" UNIQUE ("tenant_id", "carrier_code");
ALTER TABLE ONLY "public"."tms_contract"
    ADD CONSTRAINT "tms_contract_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_contract"
    ADD CONSTRAINT "tms_contract_tenant_contract_no_key" UNIQUE ("tenant_id", "contract_no");
ALTER TABLE ONLY "public"."tms_customer_address"
    ADD CONSTRAINT "tms_customer_address_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_customer"
    ADD CONSTRAINT "tms_customer_code_tenant_unique" UNIQUE ("tenant_id", "customer_code");
ALTER TABLE ONLY "public"."tms_customer"
    ADD CONSTRAINT "tms_customer_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_customer_price"
    ADD CONSTRAINT "tms_customer_price_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_driver"
    ADD CONSTRAINT "tms_driver_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_tenant_order_no_key" UNIQUE ("tenant_id", "order_no");
ALTER TABLE ONLY "public"."tms_station"
    ADD CONSTRAINT "tms_station_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_station"
    ADD CONSTRAINT "tms_station_tenant_code_key" UNIQUE ("tenant_id", "station_code");
ALTER TABLE ONLY "public"."tms_station"
    ADD CONSTRAINT "tms_station_tenant_name_key" UNIQUE ("tenant_id", "station_name");
ALTER TABLE ONLY "public"."tms_waybill_event"
    ADD CONSTRAINT "tms_waybill_event_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_waybill"
    ADD CONSTRAINT "tms_waybill_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_waybill_proof"
    ADD CONSTRAINT "tms_waybill_proof_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."tms_waybill"
    ADD CONSTRAINT "tms_waybill_tenant_no_uk" UNIQUE ("tenant_id", "waybill_no");
ALTER TABLE ONLY "public"."vehicle_archive"
    ADD CONSTRAINT "uq_vehicle_archive_tenant_plate_no" UNIQUE ("tenant_id", "plate_no");
ALTER TABLE ONLY "public"."vehicle_accident_record"
    ADD CONSTRAINT "vehicle_accident_record_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_archive"
    ADD CONSTRAINT "vehicle_archive_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_inspection"
    ADD CONSTRAINT "vehicle_inspection_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_insurance"
    ADD CONSTRAINT "vehicle_insurance_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_maintenance_record"
    ADD CONSTRAINT "vehicle_maintenance_record_no_tenant_key" UNIQUE ("tenant_id", "maintenance_no");
ALTER TABLE ONLY "public"."vehicle_maintenance_record"
    ADD CONSTRAINT "vehicle_maintenance_record_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_mileage_record"
    ADD CONSTRAINT "vehicle_mileage_record_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_part_usage"
    ADD CONSTRAINT "vehicle_part_usage_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_parts_category"
    ADD CONSTRAINT "vehicle_parts_category_code_unique" UNIQUE ("category_code");
ALTER TABLE ONLY "public"."vehicle_parts_category"
    ADD CONSTRAINT "vehicle_parts_category_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_parts"
    ADD CONSTRAINT "vehicle_parts_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_routine_inspection_record"
    ADD CONSTRAINT "vehicle_routine_inspection_record_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_supplier"
    ADD CONSTRAINT "vehicle_supplier_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."vehicle_violation_record"
    ADD CONSTRAINT "vehicle_violation_record_pkey" PRIMARY KEY ("id");
CREATE INDEX "idx_sys_attachment_tenant_id" ON "public"."sys_attachment" USING "btree" ("tenant_id");
CREATE INDEX "idx_sys_audit_log_tenant_id" ON "public"."sys_audit_log" USING "btree" ("tenant_id");
CREATE INDEX "idx_sys_dict_type_parent_id" ON "public"."sys_dict_type" USING "btree" ("parent_id");
CREATE INDEX "idx_sys_dict_type_tenant_code" ON "public"."sys_dict_type" USING "btree" ("tenant_id", "code");
CREATE INDEX "idx_sys_dict_type_tenant_id" ON "public"."sys_dict_type" USING "btree" ("tenant_id");
CREATE INDEX "idx_sys_dict_type_tenant_node_sort" ON "public"."sys_dict_type" USING "btree" ("tenant_id", "node_type", "sort", "name");
CREATE INDEX "idx_sys_dict_type_tenant_parent" ON "public"."sys_dict_type" USING "btree" ("tenant_id", "parent_id");
CREATE INDEX "idx_sys_dictionary_parent_id" ON "public"."sys_dictionary" USING "btree" ("parent_id");
CREATE INDEX "idx_sys_dictionary_tenant_id" ON "public"."sys_dictionary" USING "btree" ("tenant_id");
CREATE INDEX "idx_sys_dictionary_tenant_type_code" ON "public"."sys_dictionary" USING "btree" ("tenant_id", "type_id", "code");
CREATE INDEX "idx_sys_dictionary_tenant_type_parent" ON "public"."sys_dictionary" USING "btree" ("tenant_id", "type_id", "parent_id");
CREATE INDEX "idx_sys_dictionary_type_id" ON "public"."sys_dictionary" USING "btree" ("type_id");
CREATE INDEX "idx_sys_menu_path" ON "public"."sys_menu" USING "btree" ("path");
CREATE INDEX "idx_sys_role_menu_tenant_id" ON "public"."sys_role_menu" USING "btree" ("tenant_id");
CREATE INDEX "idx_sys_role_role_code" ON "public"."sys_role" USING "btree" ("role_code");
CREATE INDEX "idx_sys_role_tenant_id" ON "public"."sys_role" USING "btree" ("tenant_id");
CREATE UNIQUE INDEX "idx_sys_role_tenant_role_code_unique" ON "public"."sys_role" USING "btree" ("tenant_id", "role_code");
CREATE UNIQUE INDEX "idx_sys_user_auth_user_id" ON "public"."sys_user" USING "btree" ("auth_user_id");
CREATE UNIQUE INDEX "idx_sys_user_auth_user_id_unique" ON "public"."sys_user" USING "btree" ("auth_user_id");
CREATE INDEX "idx_sys_user_tenant_id" ON "public"."sys_user" USING "btree" ("tenant_id");
CREATE INDEX "idx_sys_user_tenant_role_codes" ON "public"."sys_user_tenant" USING "gin" ("role_codes");
CREATE INDEX "idx_sys_user_tenant_tenant_id" ON "public"."sys_user_tenant" USING "btree" ("tenant_id");
CREATE INDEX "idx_sys_user_tenant_user_id" ON "public"."sys_user_tenant" USING "btree" ("user_id");
CREATE INDEX "idx_sys_user_user_email" ON "public"."sys_user" USING "btree" ("user_email");
CREATE INDEX "idx_tms_cargo_tenant_create_time" ON "public"."tms_cargo" USING "btree" ("tenant_id", "create_time" DESC);
CREATE INDEX "idx_tms_cargo_tenant_enabled" ON "public"."tms_cargo" USING "btree" ("tenant_id", "enabled");
CREATE INDEX "idx_tms_cargo_tenant_unit" ON "public"."tms_cargo" USING "btree" ("tenant_id", "unit");
CREATE INDEX "idx_tms_carrier_carrier_type" ON "public"."tms_carrier" USING "btree" ("carrier_type");
CREATE INDEX "idx_tms_carrier_company_name" ON "public"."tms_carrier" USING "btree" ("company_name");
CREATE INDEX "idx_tms_carrier_create_time" ON "public"."tms_carrier" USING "btree" ("create_time" DESC);
CREATE INDEX "idx_tms_carrier_enabled" ON "public"."tms_carrier" USING "btree" ("enabled");
CREATE INDEX "idx_tms_carrier_price_carrier_id" ON "public"."tms_carrier_price" USING "btree" ("carrier_id");
CREATE INDEX "idx_tms_carrier_price_driver_id" ON "public"."tms_carrier_price" USING "btree" ("driver_id");
CREATE INDEX "idx_tms_carrier_price_route" ON "public"."tms_carrier_price" USING "btree" ("tenant_id", "origin_region", "destination_region");
CREATE INDEX "idx_tms_carrier_price_tenant_create_time" ON "public"."tms_carrier_price" USING "btree" ("tenant_id", "create_time" DESC);
CREATE INDEX "idx_tms_carrier_price_vehicle_id" ON "public"."tms_carrier_price" USING "btree" ("vehicle_id");
CREATE INDEX "idx_tms_carrier_signed_contract" ON "public"."tms_carrier" USING "btree" ("signed_contract");
CREATE INDEX "idx_tms_carrier_tenant_id" ON "public"."tms_carrier" USING "btree" ("tenant_id");
CREATE INDEX "idx_tms_contract_tenant_carrier" ON "public"."tms_contract" USING "btree" ("tenant_id", "carrier_id");
CREATE INDEX "idx_tms_contract_tenant_create_time" ON "public"."tms_contract" USING "btree" ("tenant_id", "create_time" DESC);
CREATE INDEX "idx_tms_contract_tenant_sign_time" ON "public"."tms_contract" USING "btree" ("tenant_id", "sign_time" DESC);
CREATE INDEX "idx_tms_contract_tenant_status" ON "public"."tms_contract" USING "btree" ("tenant_id", "contract_status");
CREATE INDEX "idx_tms_customer_price_customer_id" ON "public"."tms_customer_price" USING "btree" ("customer_id");
CREATE INDEX "idx_tms_customer_price_receiving_address_id" ON "public"."tms_customer_price" USING "btree" ("receiving_address_id");
CREATE INDEX "idx_tms_customer_price_shipping_address_id" ON "public"."tms_customer_price" USING "btree" ("shipping_address_id");
CREATE INDEX "idx_tms_customer_price_tenant_billing" ON "public"."tms_customer_price" USING "btree" ("tenant_id", "billing_method");
CREATE INDEX "idx_tms_customer_price_tenant_cargo_type" ON "public"."tms_customer_price" USING "btree" ("tenant_id", "cargo_type");
CREATE INDEX "idx_tms_customer_price_tenant_create_time" ON "public"."tms_customer_price" USING "btree" ("tenant_id", "create_time" DESC);
CREATE INDEX "idx_tms_customer_price_tenant_customer" ON "public"."tms_customer_price" USING "btree" ("tenant_id", "customer_id");
CREATE INDEX "idx_tms_customer_price_tenant_route" ON "public"."tms_customer_price" USING "btree" ("tenant_id", "origin_region", "destination_region");
CREATE INDEX "idx_tms_customer_price_tenant_transport" ON "public"."tms_customer_price" USING "btree" ("tenant_id", "transport_type");
CREATE INDEX "idx_tms_driver_carrier_id" ON "public"."tms_driver" USING "btree" ("carrier_id");
CREATE INDEX "idx_tms_driver_create_time" ON "public"."tms_driver" USING "btree" ("create_time" DESC);
CREATE INDEX "idx_tms_driver_driver_type" ON "public"."tms_driver" USING "btree" ("tenant_id", "carrier_id", "driver_type");
CREATE INDEX "idx_tms_driver_enabled" ON "public"."tms_driver" USING "btree" ("enabled");
CREATE INDEX "idx_tms_driver_phone" ON "public"."tms_driver" USING "btree" ("phone");
CREATE INDEX "idx_tms_order_destination_station_id" ON "public"."tms_order" USING "btree" ("destination_station_id");
CREATE INDEX "idx_tms_order_dispatch_driver_id" ON "public"."tms_order" USING "btree" ("dispatch_driver_id");
CREATE INDEX "idx_tms_order_dispatch_status" ON "public"."tms_order" USING "btree" ("dispatch_status");
CREATE INDEX "idx_tms_order_dispatch_vehicle_id" ON "public"."tms_order" USING "btree" ("dispatch_vehicle_id");
CREATE INDEX "idx_tms_order_order_status" ON "public"."tms_order" USING "btree" ("order_status");
CREATE INDEX "idx_tms_order_origin_station_id" ON "public"."tms_order" USING "btree" ("origin_station_id");
CREATE INDEX "idx_tms_order_planned_departure_time" ON "public"."tms_order" USING "btree" ("planned_departure_time");
CREATE INDEX "idx_tms_order_receiving_address_id" ON "public"."tms_order" USING "btree" ("receiving_address_id");
CREATE INDEX "idx_tms_order_receiving_customer_id" ON "public"."tms_order" USING "btree" ("receiving_customer_id");
CREATE INDEX "idx_tms_order_shipping_address_id" ON "public"."tms_order" USING "btree" ("shipping_address_id");
CREATE INDEX "idx_tms_order_shipping_customer_id" ON "public"."tms_order" USING "btree" ("shipping_customer_id");
CREATE INDEX "idx_tms_order_signed_at" ON "public"."tms_order" USING "btree" ("signed_at");
CREATE INDEX "idx_tms_order_tenant_create_time" ON "public"."tms_order" USING "btree" ("tenant_id", "create_time" DESC);
CREATE INDEX "idx_tms_order_transfer_station_id" ON "public"."tms_order" USING "btree" ("transfer_station_id");
CREATE INDEX "idx_tms_station_tenant_enabled" ON "public"."tms_station" USING "btree" ("tenant_id", "enabled");
CREATE INDEX "idx_tms_station_tenant_sort" ON "public"."tms_station" USING "btree" ("tenant_id", "sort", "station_code");
CREATE INDEX "idx_tms_station_tenant_type" ON "public"."tms_station" USING "btree" ("tenant_id", "station_type");
CREATE INDEX "idx_tms_waybill_carrier" ON "public"."tms_waybill" USING "btree" ("carrier_id");
CREATE INDEX "idx_tms_waybill_driver_status" ON "public"."tms_waybill" USING "btree" ("driver_id", "status", "create_time" DESC);
CREATE INDEX "idx_tms_waybill_event_waybill_time" ON "public"."tms_waybill_event" USING "btree" ("waybill_id", "event_time" DESC);
CREATE INDEX "idx_tms_waybill_order_id_status" ON "public"."tms_waybill" USING "btree" ("order_id", "status", "update_time" DESC) WHERE ("order_id" IS NOT NULL);
CREATE INDEX "idx_tms_waybill_proof_waybill_type" ON "public"."tms_waybill_proof" USING "btree" ("waybill_id", "proof_type", "uploaded_at" DESC);
CREATE INDEX "idx_tms_waybill_receiver_address_id" ON "public"."tms_waybill" USING "btree" ("receiver_address_id");
CREATE INDEX "idx_tms_waybill_shipper_address_id" ON "public"."tms_waybill" USING "btree" ("shipper_address_id");
CREATE INDEX "idx_tms_waybill_tenant_status" ON "public"."tms_waybill" USING "btree" ("tenant_id", "status", "create_time" DESC);
CREATE INDEX "idx_tms_waybill_vehicle" ON "public"."tms_waybill" USING "btree" ("vehicle_id");
CREATE INDEX "idx_vehicle_accident_record_tenant_time" ON "public"."vehicle_accident_record" USING "btree" ("tenant_id", "accident_time" DESC);
CREATE INDEX "idx_vehicle_accident_record_vehicle_id" ON "public"."vehicle_accident_record" USING "btree" ("vehicle_id");
CREATE INDEX "idx_vehicle_archive_audit_status" ON "public"."vehicle_archive" USING "btree" ("audit_status");
CREATE INDEX "idx_vehicle_archive_carrier_id" ON "public"."vehicle_archive" USING "btree" ("carrier_id");
CREATE INDEX "idx_vehicle_archive_create_time" ON "public"."vehicle_archive" USING "btree" ("create_time" DESC);
CREATE INDEX "idx_vehicle_archive_plate_no" ON "public"."vehicle_archive" USING "btree" ("plate_no");
CREATE INDEX "idx_vehicle_archive_primary_driver_id" ON "public"."vehicle_archive" USING "btree" ("primary_driver_id");
CREATE INDEX "idx_vehicle_archive_secondary_driver" ON "public"."vehicle_archive" USING "btree" ("secondary_driver_id") WHERE ("secondary_driver_id" IS NOT NULL);
CREATE INDEX "idx_vehicle_archive_tenant_id" ON "public"."vehicle_archive" USING "btree" ("tenant_id");
CREATE INDEX "idx_vehicle_inspection_compulsory_company" ON "public"."vehicle_inspection" USING "btree" ("compulsory_company_id");
CREATE INDEX "idx_vehicle_inspection_expire" ON "public"."vehicle_inspection" USING "btree" ("expire_date");
CREATE INDEX "idx_vehicle_inspection_plate_no" ON "public"."vehicle_inspection" USING "btree" ("plate_no");
CREATE INDEX "idx_vehicle_inspection_tenant" ON "public"."vehicle_inspection" USING "btree" ("tenant_id");
CREATE INDEX "idx_vehicle_inspection_vehicle" ON "public"."vehicle_inspection" USING "btree" ("vehicle_id");
CREATE INDEX "idx_vehicle_insurance_commercial_company" ON "public"."vehicle_insurance" USING "btree" ("commercial_company_id");
CREATE INDEX "idx_vehicle_insurance_commercial_expire" ON "public"."vehicle_insurance" USING "btree" ("commercial_expire_date");
CREATE INDEX "idx_vehicle_insurance_company_tenant_id" ON "public"."vehicle_insurance_company" USING "btree" ("tenant_id");
CREATE INDEX "idx_vehicle_insurance_company_tenant_name" ON "public"."vehicle_insurance_company" USING "btree" ("tenant_id", "company_name");
CREATE INDEX "idx_vehicle_insurance_compulsory_company" ON "public"."vehicle_insurance" USING "btree" ("compulsory_company_id");
CREATE INDEX "idx_vehicle_insurance_compulsory_expire" ON "public"."vehicle_insurance" USING "btree" ("compulsory_expire_date");
CREATE INDEX "idx_vehicle_insurance_plate_no" ON "public"."vehicle_insurance" USING "btree" ("plate_no");
CREATE INDEX "idx_vehicle_insurance_tenant" ON "public"."vehicle_insurance" USING "btree" ("tenant_id");
CREATE INDEX "idx_vehicle_insurance_vehicle" ON "public"."vehicle_insurance" USING "btree" ("vehicle_id");
CREATE INDEX "idx_vehicle_maintenance_record_tenant_time" ON "public"."vehicle_maintenance_record" USING "btree" ("tenant_id", "start_time" DESC);
CREATE INDEX "idx_vehicle_maintenance_record_vehicle_id" ON "public"."vehicle_maintenance_record" USING "btree" ("vehicle_id");
CREATE INDEX "idx_vehicle_part_usage_category" ON "public"."vehicle_part_usage" USING "btree" ("category_id");
CREATE INDEX "idx_vehicle_part_usage_part" ON "public"."vehicle_part_usage" USING "btree" ("part_id");
CREATE INDEX "idx_vehicle_part_usage_part_name" ON "public"."vehicle_part_usage" USING "btree" ("part_name");
CREATE INDEX "idx_vehicle_part_usage_plate" ON "public"."vehicle_part_usage" USING "btree" ("plate_no");
CREATE UNIQUE INDEX "idx_vehicle_part_usage_rfid_unique" ON "public"."vehicle_part_usage" USING "btree" ("tenant_id", "rfid_tag") WHERE ("rfid_enabled" AND (NULLIF(TRIM(BOTH FROM "rfid_tag"), ''::"text") IS NOT NULL));
CREATE INDEX "idx_vehicle_part_usage_status" ON "public"."vehicle_part_usage" USING "btree" ("status");
CREATE INDEX "idx_vehicle_part_usage_supplier" ON "public"."vehicle_part_usage" USING "btree" ("supplier_id");
CREATE INDEX "idx_vehicle_part_usage_tenant" ON "public"."vehicle_part_usage" USING "btree" ("tenant_id");
CREATE INDEX "idx_vehicle_part_usage_vehicle" ON "public"."vehicle_part_usage" USING "btree" ("vehicle_id");
CREATE INDEX "idx_vehicle_parts_category_id" ON "public"."vehicle_parts" USING "btree" ("category_id");
CREATE INDEX "idx_vehicle_parts_category_parent_id" ON "public"."vehicle_parts_category" USING "btree" ("parent_id");
CREATE INDEX "idx_vehicle_parts_category_sort" ON "public"."vehicle_parts_category" USING "btree" ("parent_id", "sort", "create_time" DESC);
CREATE INDEX "idx_vehicle_parts_category_status" ON "public"."vehicle_parts_category" USING "btree" ("status");
CREATE INDEX "idx_vehicle_parts_category_tenant_code" ON "public"."vehicle_parts_category" USING "btree" ("tenant_id", "category_code");
CREATE INDEX "idx_vehicle_parts_category_tenant_id" ON "public"."vehicle_parts_category" USING "btree" ("tenant_id");
CREATE INDEX "idx_vehicle_parts_supplier_id" ON "public"."vehicle_parts" USING "btree" ("supplier_id");
CREATE INDEX "idx_vehicle_parts_tenant_category" ON "public"."vehicle_parts" USING "btree" ("tenant_id", "category_id");
CREATE INDEX "idx_vehicle_parts_tenant_create_time" ON "public"."vehicle_parts" USING "btree" ("tenant_id", "create_time" DESC);
CREATE INDEX "idx_vehicle_parts_tenant_supplier" ON "public"."vehicle_parts" USING "btree" ("tenant_id", "supplier_id");
CREATE INDEX "idx_vehicle_supplier_tenant_id" ON "public"."vehicle_supplier" USING "btree" ("tenant_id");
CREATE INDEX "idx_vehicle_supplier_tenant_name" ON "public"."vehicle_supplier" USING "btree" ("tenant_id", "supplier_name");
CREATE INDEX "idx_vehicle_violation_record_tenant_time" ON "public"."vehicle_violation_record" USING "btree" ("tenant_id", "violation_time" DESC);
CREATE INDEX "idx_vehicle_violation_record_vehicle_id" ON "public"."vehicle_violation_record" USING "btree" ("vehicle_id");
CREATE UNIQUE INDEX "insurance_company_company_name_key" ON "public"."vehicle_insurance_company" USING "btree" ("company_name");
CREATE INDEX "insurance_company_create_time_idx" ON "public"."vehicle_insurance_company" USING "btree" ("create_time" DESC);
CREATE UNIQUE INDEX "sys_attachment_hash_unique" ON "public"."sys_attachment" USING "btree" ("hash");
CREATE INDEX "sys_attachment_storage_path_idx" ON "public"."sys_attachment" USING "btree" ("storage_path");
CREATE INDEX "sys_audit_log_auth_user_id_idx" ON "public"."sys_audit_log" USING "btree" ("auth_user_id");
CREATE INDEX "sys_audit_log_create_time_idx" ON "public"."sys_audit_log" USING "btree" ("create_time" DESC);
CREATE INDEX "sys_param_tenant_enabled_idx" ON "public"."sys_param" USING "btree" ("tenant_id", "enabled");
CREATE INDEX "sys_param_tenant_group_idx" ON "public"."sys_param" USING "btree" ("tenant_id", "group_code");
CREATE UNIQUE INDEX "sys_param_tenant_key_uidx" ON "public"."sys_param" USING "btree" ("tenant_id", "param_key");
CREATE UNIQUE INDEX "sys_user_tenant_one_default_per_user" ON "public"."sys_user_tenant" USING "btree" ("user_id") WHERE "is_default";
CREATE INDEX "tms_customer_address_customer_idx" ON "public"."tms_customer_address" USING "btree" ("customer_id", "create_time" DESC);
CREATE INDEX "tms_customer_address_type_idx" ON "public"."tms_customer_address" USING "btree" ("tenant_id", "address_type");
CREATE INDEX "tms_customer_create_time_idx" ON "public"."tms_customer" USING "btree" ("tenant_id", "create_time" DESC);
CREATE INDEX "tms_customer_level_idx" ON "public"."tms_customer" USING "btree" ("tenant_id", "customer_level");
CREATE INDEX "tms_customer_name_idx" ON "public"."tms_customer" USING "btree" ("tenant_id", "customer_name");
CREATE UNIQUE INDEX "tms_waybill_order_id_key" ON "public"."tms_waybill" USING "btree" ("order_id") WHERE ("order_id" IS NOT NULL);
CREATE UNIQUE INDEX "uq_vehicle_parts_tenant_part_code" ON "public"."vehicle_parts" USING "btree" ("tenant_id", "part_code");
CREATE INDEX "vehicle_mileage_record_plate_idx" ON "public"."vehicle_mileage_record" USING "btree" ("tenant_id", "plate_no");
CREATE INDEX "vehicle_mileage_record_vehicle_idx" ON "public"."vehicle_mileage_record" USING "btree" ("vehicle_id");
CREATE INDEX "vehicle_routine_inspection_record_plate_idx" ON "public"."vehicle_routine_inspection_record" USING "btree" ("tenant_id", "plate_no");
CREATE INDEX "vehicle_routine_inspection_record_tenant_time_idx" ON "public"."vehicle_routine_inspection_record" USING "btree" ("tenant_id", "inspection_time" DESC);
CREATE INDEX "vehicle_routine_inspection_record_vehicle_idx" ON "public"."vehicle_routine_inspection_record" USING "btree" ("vehicle_id");
CREATE INDEX "vehicle_supplier_create_by_idx" ON "public"."vehicle_supplier" USING "btree" ("create_by");
CREATE UNIQUE INDEX "vehicle_supplier_create_by_supplier_name_uq" ON "public"."vehicle_supplier" USING "btree" ("create_by", "supplier_name");
CREATE INDEX "vehicle_supplier_create_time_idx" ON "public"."vehicle_supplier" USING "btree" ("create_time" DESC);
CREATE OR REPLACE TRIGGER "sys_dict_type_validate_hierarchy" BEFORE INSERT OR UPDATE OF "parent_id", "node_type", "tenant_id" ON "public"."sys_dict_type" FOR EACH ROW EXECUTE FUNCTION "app_private"."validate_dict_type_hierarchy"();
CREATE OR REPLACE TRIGGER "sys_dictionary_validate_hierarchy" BEFORE INSERT OR UPDATE OF "parent_id", "type_id", "tenant_id" ON "public"."sys_dictionary" FOR EACH ROW EXECUTE FUNCTION "app_private"."validate_dictionary_hierarchy"();
CREATE OR REPLACE TRIGGER "sys_param_create_audit" BEFORE INSERT ON "public"."sys_param" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "sys_param_update_audit" BEFORE UPDATE ON "public"."sys_param" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "sys_tenant_create_audit" BEFORE INSERT ON "public"."sys_tenant" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "sys_tenant_update_audit" BEFORE UPDATE ON "public"."sys_tenant" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_cargo_create_audit" BEFORE INSERT ON "public"."tms_cargo" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_cargo_update_audit" BEFORE UPDATE ON "public"."tms_cargo" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_carrier_create_audit" BEFORE INSERT ON "public"."tms_carrier" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_carrier_price_create_audit" BEFORE INSERT ON "public"."tms_carrier_price" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_carrier_price_update_audit" BEFORE UPDATE ON "public"."tms_carrier_price" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_carrier_update_audit" BEFORE UPDATE ON "public"."tms_carrier" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_contract_create_audit" BEFORE INSERT ON "public"."tms_contract" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_contract_update_audit" BEFORE UPDATE ON "public"."tms_contract" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_customer_address_create_audit" BEFORE INSERT ON "public"."tms_customer_address" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_customer_address_update_audit" BEFORE UPDATE ON "public"."tms_customer_address" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_customer_create_audit" BEFORE INSERT ON "public"."tms_customer" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_customer_price_create_audit" BEFORE INSERT ON "public"."tms_customer_price" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_customer_price_update_audit" BEFORE UPDATE ON "public"."tms_customer_price" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_customer_update_audit" BEFORE UPDATE ON "public"."tms_customer" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_driver_create_audit" BEFORE INSERT ON "public"."tms_driver" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_driver_update_audit" BEFORE UPDATE ON "public"."tms_driver" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_order_create_audit" BEFORE INSERT ON "public"."tms_order" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_order_sync_completed_waybill" AFTER UPDATE OF "order_status" ON "public"."tms_order" FOR EACH ROW EXECUTE FUNCTION "public"."trg_sync_completed_waybill_from_order"();
CREATE OR REPLACE TRIGGER "tms_order_sync_waybill_cancel" AFTER INSERT OR UPDATE OF "order_status" ON "public"."tms_order" FOR EACH ROW EXECUTE FUNCTION "public"."trg_sync_tms_waybill_cancel_from_order"();
CREATE OR REPLACE TRIGGER "tms_order_update_audit" BEFORE UPDATE ON "public"."tms_order" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_station_create_audit" BEFORE INSERT ON "public"."tms_station" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_station_update_audit" BEFORE UPDATE ON "public"."tms_station" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_waybill_create_audit" BEFORE INSERT ON "public"."tms_waybill" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_waybill_event_create_audit" BEFORE INSERT ON "public"."tms_waybill_event" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_waybill_event_set_parent_tenant" BEFORE INSERT OR UPDATE OF "waybill_id", "tenant_id" ON "public"."tms_waybill_event" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_waybill_child_tenant"();
CREATE OR REPLACE TRIGGER "tms_waybill_event_update_audit" BEFORE UPDATE ON "public"."tms_waybill_event" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_waybill_proof_create_audit" BEFORE INSERT ON "public"."tms_waybill_proof" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "tms_waybill_proof_set_parent_tenant" BEFORE INSERT OR UPDATE OF "waybill_id", "tenant_id" ON "public"."tms_waybill_proof" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_waybill_child_tenant"();
CREATE OR REPLACE TRIGGER "tms_waybill_proof_update_audit" BEFORE UPDATE ON "public"."tms_waybill_proof" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_waybill_sync_order_terminal_status" AFTER INSERT OR UPDATE ON "public"."tms_waybill" FOR EACH ROW EXECUTE FUNCTION "public"."trg_sync_order_terminal_status_from_waybill"();
CREATE OR REPLACE TRIGGER "tms_waybill_update_audit" BEFORE UPDATE ON "public"."tms_waybill" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "tms_waybill_validate_status_transition" BEFORE UPDATE OF "status" ON "public"."tms_waybill" FOR EACH ROW EXECUTE FUNCTION "public"."trg_validate_tms_waybill_status_transition"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."sys_attachment" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."sys_audit_log" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."sys_dict_type" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."sys_dictionary" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."sys_role" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."sys_role_menu" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."sys_user" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT OR UPDATE ON "public"."tms_carrier" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT OR UPDATE ON "public"."tms_customer" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT OR UPDATE ON "public"."tms_customer_address" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."vehicle_insurance_company" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."vehicle_parts_category" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_apply_current_tenant_id" BEFORE INSERT ON "public"."vehicle_supplier" FOR EACH ROW EXECUTE FUNCTION "app_private"."trg_apply_current_tenant_id"();
CREATE OR REPLACE TRIGGER "trg_cleanup_sys_role_menu_on_sys_role_delete" AFTER DELETE ON "public"."sys_role" FOR EACH ROW EXECUTE FUNCTION "public"."clean_role_menus_on_role_delete"();
CREATE OR REPLACE TRIGGER "trg_enforce_platform_super_user" BEFORE INSERT OR UPDATE OF "tenant_id", "user_email", "user_roles" ON "public"."sys_user" FOR EACH ROW EXECUTE FUNCTION "app_private"."enforce_platform_super_user"();
CREATE OR REPLACE TRIGGER "trg_enforce_sys_user_tenant_rules" BEFORE INSERT OR UPDATE OF "user_id", "tenant_id", "role_codes" ON "public"."sys_user_tenant" FOR EACH ROW EXECUTE FUNCTION "app_private"."enforce_sys_user_tenant_rules"();
CREATE OR REPLACE TRIGGER "trg_enforce_system_role_rules" BEFORE INSERT OR DELETE OR UPDATE OF "tenant_id", "role_code", "enabled" ON "public"."sys_role" FOR EACH ROW EXECUTE FUNCTION "app_private"."enforce_system_role_rules"();
CREATE OR REPLACE TRIGGER "trg_prevent_platform_tenant_change" BEFORE DELETE OR UPDATE ON "public"."sys_tenant" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_platform_tenant_change"();
CREATE OR REPLACE TRIGGER "trg_set_create_sys_dict_type" BEFORE INSERT ON "public"."sys_dict_type" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_create_sys_dictionary" BEFORE INSERT ON "public"."sys_dictionary" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_create_sys_menu" BEFORE INSERT OR UPDATE ON "public"."sys_menu" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('false', 'true');
CREATE OR REPLACE TRIGGER "trg_set_create_sys_role" BEFORE INSERT ON "public"."sys_role" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_create_sys_role_menu" BEFORE INSERT ON "public"."sys_role_menu" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_create_sys_user" BEFORE INSERT ON "public"."sys_user" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"();
CREATE OR REPLACE TRIGGER "trg_set_create_sys_user_tenant" BEFORE INSERT ON "public"."sys_user_tenant" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_create_vehicle_insurance_company_time_and_by" BEFORE INSERT ON "public"."vehicle_insurance_company" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_insert_update_by_sys_role_menu" BEFORE INSERT ON "public"."sys_role_menu" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "trg_set_update_extra_sys_role_menu" BEFORE UPDATE ON "public"."sys_role_menu" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "trg_set_update_sys_dict_type" BEFORE UPDATE ON "public"."sys_dict_type" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_update_sys_dictionary" BEFORE UPDATE ON "public"."sys_dictionary" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_update_sys_menu" BEFORE UPDATE ON "public"."sys_menu" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"('false', 'false');
CREATE OR REPLACE TRIGGER "trg_set_update_sys_role" BEFORE UPDATE ON "public"."sys_role" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_update_sys_role_menu" BEFORE UPDATE ON "public"."sys_role_menu" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_set_update_sys_user" BEFORE UPDATE ON "public"."sys_user" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "trg_set_update_sys_user_tenant" BEFORE UPDATE ON "public"."sys_user_tenant" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "trg_set_update_vehicle_insurance_company_time_and_by" BEFORE UPDATE ON "public"."vehicle_insurance_company" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "trg_vehicle_parts_category_create_audit" BEFORE INSERT ON "public"."vehicle_parts_category" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "trg_vehicle_parts_category_level" BEFORE INSERT OR UPDATE OF "parent_id" ON "public"."vehicle_parts_category" FOR EACH ROW EXECUTE FUNCTION "public"."set_vehicle_parts_category_level"();
CREATE OR REPLACE TRIGGER "trg_vehicle_parts_category_update_audit" BEFORE UPDATE ON "public"."vehicle_parts_category" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_accident_record_create_audit" BEFORE INSERT ON "public"."vehicle_accident_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_accident_record_update_audit" BEFORE UPDATE ON "public"."vehicle_accident_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_archive_create_audit" BEFORE INSERT ON "public"."vehicle_archive" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_archive_update_audit" BEFORE UPDATE ON "public"."vehicle_archive" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_inspection_create_audit" BEFORE INSERT ON "public"."vehicle_inspection" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_inspection_update_audit" BEFORE UPDATE ON "public"."vehicle_inspection" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_insurance_create_audit" BEFORE INSERT ON "public"."vehicle_insurance" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_insurance_update_audit" BEFORE UPDATE ON "public"."vehicle_insurance" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_maintenance_record_create_audit" BEFORE INSERT ON "public"."vehicle_maintenance_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_maintenance_record_update_audit" BEFORE UPDATE ON "public"."vehicle_maintenance_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_mileage_record_create_audit" BEFORE INSERT ON "public"."vehicle_mileage_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_mileage_record_update_audit" BEFORE UPDATE ON "public"."vehicle_mileage_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_part_usage_create_audit" BEFORE INSERT ON "public"."vehicle_part_usage" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_part_usage_update_audit" BEFORE UPDATE ON "public"."vehicle_part_usage" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_parts_create_audit" BEFORE INSERT ON "public"."vehicle_parts" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_parts_update_audit" BEFORE UPDATE ON "public"."vehicle_parts" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_routine_inspection_record_create_audit" BEFORE INSERT ON "public"."vehicle_routine_inspection_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_routine_inspection_record_update_audit" BEFORE UPDATE ON "public"."vehicle_routine_inspection_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_supplier_set_create_time_and_by" BEFORE INSERT ON "public"."vehicle_supplier" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_supplier_set_update_time_and_by" BEFORE UPDATE ON "public"."vehicle_supplier" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
CREATE OR REPLACE TRIGGER "vehicle_violation_record_create_audit" BEFORE INSERT ON "public"."vehicle_violation_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_create_time_and_by"('true', 'true');
CREATE OR REPLACE TRIGGER "vehicle_violation_record_update_audit" BEFORE UPDATE ON "public"."vehicle_violation_record" FOR EACH ROW EXECUTE FUNCTION "public"."trg_set_update_time_and_by"();
ALTER TABLE ONLY "public"."sys_attachment"
    ADD CONSTRAINT "sys_attachment_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."sys_audit_log"
    ADD CONSTRAINT "sys_audit_log_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."sys_dict_type"
    ADD CONSTRAINT "sys_dict_type_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."sys_dict_type"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."sys_dict_type"
    ADD CONSTRAINT "sys_dict_type_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."sys_dictionary"
    ADD CONSTRAINT "sys_dictionary_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."sys_dictionary"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."sys_dictionary"
    ADD CONSTRAINT "sys_dictionary_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."sys_dictionary"
    ADD CONSTRAINT "sys_dictionary_type_id_fkey" FOREIGN KEY ("type_id") REFERENCES "public"."sys_dict_type"("id");
ALTER TABLE ONLY "public"."sys_param"
    ADD CONSTRAINT "sys_param_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."sys_role_menu"
    ADD CONSTRAINT "sys_role_menu_menu_id_fkey" FOREIGN KEY ("menu_id") REFERENCES "public"."sys_menu"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."sys_role_menu"
    ADD CONSTRAINT "sys_role_menu_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."sys_role"("id");
ALTER TABLE ONLY "public"."sys_role_menu"
    ADD CONSTRAINT "sys_role_menu_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."sys_role"
    ADD CONSTRAINT "sys_role_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."sys_user"
    ADD CONSTRAINT "sys_user_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."sys_user_tenant"
    ADD CONSTRAINT "sys_user_tenant_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."sys_user_tenant"
    ADD CONSTRAINT "sys_user_tenant_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."sys_user"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."tms_carrier_price"
    ADD CONSTRAINT "tms_carrier_price_carrier_id_fkey" FOREIGN KEY ("carrier_id") REFERENCES "public"."tms_carrier"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."tms_carrier_price"
    ADD CONSTRAINT "tms_carrier_price_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."tms_driver"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_carrier_price"
    ADD CONSTRAINT "tms_carrier_price_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_contract"
    ADD CONSTRAINT "tms_contract_carrier_id_fkey" FOREIGN KEY ("carrier_id") REFERENCES "public"."tms_carrier"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."tms_customer_address"
    ADD CONSTRAINT "tms_customer_address_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."tms_customer"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."tms_customer_address"
    ADD CONSTRAINT "tms_customer_address_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."tms_customer_price"
    ADD CONSTRAINT "tms_customer_price_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."tms_customer"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."tms_customer_price"
    ADD CONSTRAINT "tms_customer_price_receiving_address_id_fkey" FOREIGN KEY ("receiving_address_id") REFERENCES "public"."tms_customer_address"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_customer_price"
    ADD CONSTRAINT "tms_customer_price_shipping_address_id_fkey" FOREIGN KEY ("shipping_address_id") REFERENCES "public"."tms_customer_address"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_customer"
    ADD CONSTRAINT "tms_customer_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."tms_driver"
    ADD CONSTRAINT "tms_driver_carrier_id_fkey" FOREIGN KEY ("carrier_id") REFERENCES "public"."tms_carrier"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_destination_station_id_fkey" FOREIGN KEY ("destination_station_id") REFERENCES "public"."tms_station"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_dispatch_driver_id_fkey" FOREIGN KEY ("dispatch_driver_id") REFERENCES "public"."tms_driver"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_dispatch_vehicle_id_fkey" FOREIGN KEY ("dispatch_vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_origin_station_id_fkey" FOREIGN KEY ("origin_station_id") REFERENCES "public"."tms_station"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_receiving_address_id_fkey" FOREIGN KEY ("receiving_address_id") REFERENCES "public"."tms_customer_address"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_receiving_customer_id_fkey" FOREIGN KEY ("receiving_customer_id") REFERENCES "public"."tms_customer"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_shipping_address_id_fkey" FOREIGN KEY ("shipping_address_id") REFERENCES "public"."tms_customer_address"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_shipping_customer_id_fkey" FOREIGN KEY ("shipping_customer_id") REFERENCES "public"."tms_customer"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_order"
    ADD CONSTRAINT "tms_order_transfer_station_id_fkey" FOREIGN KEY ("transfer_station_id") REFERENCES "public"."tms_station"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."tms_waybill"
    ADD CONSTRAINT "tms_waybill_cargo_id_fkey" FOREIGN KEY ("cargo_id") REFERENCES "public"."tms_cargo"("id");
ALTER TABLE ONLY "public"."tms_waybill"
    ADD CONSTRAINT "tms_waybill_carrier_id_fkey" FOREIGN KEY ("carrier_id") REFERENCES "public"."tms_carrier"("id");
ALTER TABLE ONLY "public"."tms_waybill"
    ADD CONSTRAINT "tms_waybill_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."tms_driver"("id");
ALTER TABLE ONLY "public"."tms_waybill_event"
    ADD CONSTRAINT "tms_waybill_event_waybill_id_fkey" FOREIGN KEY ("waybill_id") REFERENCES "public"."tms_waybill"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."tms_waybill"
    ADD CONSTRAINT "tms_waybill_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."tms_order"("id") ON DELETE RESTRICT;
ALTER TABLE ONLY "public"."tms_waybill_proof"
    ADD CONSTRAINT "tms_waybill_proof_attachment_id_fkey" FOREIGN KEY ("attachment_id") REFERENCES "public"."sys_attachment"("id");
ALTER TABLE ONLY "public"."tms_waybill_proof"
    ADD CONSTRAINT "tms_waybill_proof_waybill_id_fkey" FOREIGN KEY ("waybill_id") REFERENCES "public"."tms_waybill"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."tms_waybill"
    ADD CONSTRAINT "tms_waybill_receiver_address_id_fkey" FOREIGN KEY ("receiver_address_id") REFERENCES "public"."tms_customer_address"("id");
ALTER TABLE ONLY "public"."tms_waybill"
    ADD CONSTRAINT "tms_waybill_shipper_address_id_fkey" FOREIGN KEY ("shipper_address_id") REFERENCES "public"."tms_customer_address"("id");
ALTER TABLE ONLY "public"."tms_waybill"
    ADD CONSTRAINT "tms_waybill_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id");
ALTER TABLE ONLY "public"."vehicle_accident_record"
    ADD CONSTRAINT "vehicle_accident_record_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_archive"
    ADD CONSTRAINT "vehicle_archive_carrier_id_fkey" FOREIGN KEY ("carrier_id") REFERENCES "public"."tms_carrier"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_archive"
    ADD CONSTRAINT "vehicle_archive_primary_driver_id_fkey" FOREIGN KEY ("primary_driver_id") REFERENCES "public"."tms_driver"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_archive"
    ADD CONSTRAINT "vehicle_archive_secondary_driver_id_fkey" FOREIGN KEY ("secondary_driver_id") REFERENCES "public"."tms_driver"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_inspection"
    ADD CONSTRAINT "vehicle_inspection_compulsory_company_id_fkey" FOREIGN KEY ("compulsory_company_id") REFERENCES "public"."vehicle_insurance_company"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_inspection"
    ADD CONSTRAINT "vehicle_inspection_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_insurance"
    ADD CONSTRAINT "vehicle_insurance_commercial_company_id_fkey" FOREIGN KEY ("commercial_company_id") REFERENCES "public"."vehicle_insurance_company"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_insurance_company"
    ADD CONSTRAINT "vehicle_insurance_company_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."vehicle_insurance"
    ADD CONSTRAINT "vehicle_insurance_compulsory_company_id_fkey" FOREIGN KEY ("compulsory_company_id") REFERENCES "public"."vehicle_insurance_company"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_insurance"
    ADD CONSTRAINT "vehicle_insurance_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_maintenance_record"
    ADD CONSTRAINT "vehicle_maintenance_record_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_mileage_record"
    ADD CONSTRAINT "vehicle_mileage_record_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_part_usage"
    ADD CONSTRAINT "vehicle_part_usage_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."vehicle_parts_category"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_part_usage"
    ADD CONSTRAINT "vehicle_part_usage_part_id_fkey" FOREIGN KEY ("part_id") REFERENCES "public"."vehicle_parts"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_part_usage"
    ADD CONSTRAINT "vehicle_part_usage_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."vehicle_supplier"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_part_usage"
    ADD CONSTRAINT "vehicle_part_usage_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_parts"
    ADD CONSTRAINT "vehicle_parts_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."vehicle_parts_category"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_parts_category"
    ADD CONSTRAINT "vehicle_parts_category_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."vehicle_parts_category"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."vehicle_parts_category"
    ADD CONSTRAINT "vehicle_parts_category_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."vehicle_parts"
    ADD CONSTRAINT "vehicle_parts_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."vehicle_supplier"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_parts"
    ADD CONSTRAINT "vehicle_parts_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."vehicle_routine_inspection_record"
    ADD CONSTRAINT "vehicle_routine_inspection_record_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."vehicle_supplier"
    ADD CONSTRAINT "vehicle_supplier_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."sys_tenant"("id");
ALTER TABLE ONLY "public"."vehicle_violation_record"
    ADD CONSTRAINT "vehicle_violation_record_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicle_archive"("id") ON DELETE SET NULL;
CREATE POLICY "anon_read_website_config" ON "public"."sys_param" FOR SELECT TO "anon" USING ((("param_key" = 'website.config'::"text") AND ("enabled" = true)));
ALTER TABLE "public"."sys_attachment" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."sys_audit_log" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."sys_dict_type" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sys_dict_type_delete_platform_super" ON "public"."sys_dict_type" FOR DELETE USING ("app_private"."is_platform_super"());
CREATE POLICY "sys_dict_type_insert_platform_super" ON "public"."sys_dict_type" FOR INSERT WITH CHECK ("app_private"."is_platform_super"());
CREATE POLICY "sys_dict_type_select_global" ON "public"."sys_dict_type" FOR SELECT USING (true);
CREATE POLICY "sys_dict_type_update_platform_super" ON "public"."sys_dict_type" FOR UPDATE USING ("app_private"."is_platform_super"()) WITH CHECK ("app_private"."is_platform_super"());
ALTER TABLE "public"."sys_dictionary" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sys_dictionary_delete_platform_super" ON "public"."sys_dictionary" FOR DELETE USING ("app_private"."is_platform_super"());
CREATE POLICY "sys_dictionary_insert_platform_super" ON "public"."sys_dictionary" FOR INSERT WITH CHECK ("app_private"."is_platform_super"());
CREATE POLICY "sys_dictionary_select_global" ON "public"."sys_dictionary" FOR SELECT USING (true);
CREATE POLICY "sys_dictionary_update_platform_super" ON "public"."sys_dictionary" FOR UPDATE USING ("app_private"."is_platform_super"()) WITH CHECK ("app_private"."is_platform_super"());
ALTER TABLE "public"."sys_menu" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sys_menu_delete_platform_super" ON "public"."sys_menu" FOR DELETE TO "authenticated" USING ("app_private"."is_platform_super"());
CREATE POLICY "sys_menu_insert_platform_super" ON "public"."sys_menu" FOR INSERT TO "authenticated" WITH CHECK ("app_private"."is_platform_super"());
CREATE POLICY "sys_menu_select_global" ON "public"."sys_menu" FOR SELECT TO "authenticated" USING (true);
CREATE POLICY "sys_menu_update_platform_super" ON "public"."sys_menu" FOR UPDATE TO "authenticated" USING ("app_private"."is_platform_super"()) WITH CHECK ("app_private"."is_platform_super"());
ALTER TABLE "public"."sys_param" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sys_param_authenticated_read" ON "public"."sys_param" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()) OR ("tenant_id" = "app_private"."platform_tenant_id"())));
CREATE POLICY "sys_param_platform_super_delete" ON "public"."sys_param" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() AND ("builtin" = false)));
CREATE POLICY "sys_param_platform_super_insert" ON "public"."sys_param" FOR INSERT TO "authenticated" WITH CHECK ("app_private"."is_platform_super"());
CREATE POLICY "sys_param_platform_super_update" ON "public"."sys_param" FOR UPDATE TO "authenticated" USING ("app_private"."is_platform_super"()) WITH CHECK ("app_private"."is_platform_super"());
ALTER TABLE "public"."sys_role" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."sys_role_menu" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."sys_tenant" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."sys_user" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."sys_user_tenant" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_delete" ON "public"."sys_attachment" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."sys_audit_log" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."sys_role" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND "app_private"."is_tenant_admin"())));
CREATE POLICY "tenant_delete" ON "public"."sys_role_menu" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND "app_private"."is_tenant_admin"())));
CREATE POLICY "tenant_delete" ON "public"."sys_tenant" FOR DELETE TO "authenticated" USING ("app_private"."is_platform_super"());
CREATE POLICY "tenant_delete" ON "public"."sys_user" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND "app_private"."is_tenant_admin"())));
CREATE POLICY "tenant_delete" ON "public"."sys_user_tenant" FOR DELETE USING (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND "app_private"."is_tenant_admin"())));
CREATE POLICY "tenant_delete" ON "public"."tms_cargo" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."tms_carrier" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."tms_carrier_price" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."tms_contract" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."tms_customer" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."tms_customer_address" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."tms_customer_price" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."tms_order" FOR DELETE USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."tms_station" FOR DELETE USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."vehicle_archive" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."vehicle_insurance_company" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."vehicle_parts" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."vehicle_parts_category" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_delete" ON "public"."vehicle_supplier" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."sys_attachment" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."sys_audit_log" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."sys_role" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."sys_role_menu" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."sys_tenant" FOR INSERT TO "authenticated" WITH CHECK ("app_private"."is_platform_super"());
CREATE POLICY "tenant_insert" ON "public"."sys_user" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."sys_user_tenant" FOR INSERT WITH CHECK (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND "app_private"."is_tenant_admin"())));
CREATE POLICY "tenant_insert" ON "public"."tms_cargo" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."tms_carrier" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."tms_carrier_price" FOR INSERT TO "authenticated" WITH CHECK ((("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())) AND (EXISTS ( SELECT 1
   FROM "public"."tms_carrier" "carrier"
  WHERE (("carrier"."id" = "tms_carrier_price"."carrier_id") AND ("app_private"."is_platform_super"() OR ("carrier"."tenant_id" = "app_private"."current_user_tenant_id"()))))) AND (("driver_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."tms_driver" "driver"
  WHERE (("driver"."id" = "tms_carrier_price"."driver_id") AND ("driver"."carrier_id" = "tms_carrier_price"."carrier_id") AND ("app_private"."is_platform_super"() OR ("driver"."tenant_id" = "app_private"."current_user_tenant_id"())))))) AND (("vehicle_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."vehicle_archive" "vehicle"
  WHERE (("vehicle"."id" = "tms_carrier_price"."vehicle_id") AND (("vehicle"."carrier_id" IS NULL) OR ("vehicle"."carrier_id" = "tms_carrier_price"."carrier_id")) AND ("app_private"."is_platform_super"() OR ("vehicle"."tenant_id" = "app_private"."current_user_tenant_id"()))))))));
CREATE POLICY "tenant_insert" ON "public"."tms_contract" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."tms_customer" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."tms_customer_address" FOR INSERT TO "authenticated" WITH CHECK ((("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())) AND (EXISTS ( SELECT 1
   FROM "public"."tms_customer" "customer"
  WHERE (("customer"."id" = "tms_customer_address"."customer_id") AND ("app_private"."is_platform_super"() OR ("customer"."tenant_id" = "app_private"."current_user_tenant_id"())))))));
CREATE POLICY "tenant_insert" ON "public"."tms_customer_price" FOR INSERT TO "authenticated" WITH CHECK ((("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())) AND (EXISTS ( SELECT 1
   FROM "public"."tms_customer" "customer"
  WHERE (("customer"."id" = "tms_customer_price"."customer_id") AND ("app_private"."is_platform_super"() OR ("customer"."tenant_id" = "app_private"."current_user_tenant_id"())))))));
CREATE POLICY "tenant_insert" ON "public"."tms_order" FOR INSERT WITH CHECK ((("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())) AND (("shipping_customer_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."tms_customer" "customer"
  WHERE (("customer"."id" = "tms_order"."shipping_customer_id") AND ("app_private"."is_platform_super"() OR ("customer"."tenant_id" = "app_private"."current_user_tenant_id"())))))) AND (("receiving_customer_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."tms_customer" "customer"
  WHERE (("customer"."id" = "tms_order"."receiving_customer_id") AND ("app_private"."is_platform_super"() OR ("customer"."tenant_id" = "app_private"."current_user_tenant_id"()))))))));
CREATE POLICY "tenant_insert" ON "public"."tms_station" FOR INSERT WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."vehicle_archive" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."vehicle_insurance_company" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."vehicle_parts" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."vehicle_parts_category" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_insert" ON "public"."vehicle_supplier" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."sys_attachment" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."sys_audit_log" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."sys_role" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."sys_role_menu" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."sys_tenant" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."sys_user" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."sys_user_tenant" FOR SELECT USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()) OR ("user_id" = "app_private"."current_app_user_id"())));
CREATE POLICY "tenant_select" ON "public"."tms_cargo" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."tms_carrier" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."tms_carrier_price" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."tms_contract" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."tms_customer" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."tms_customer_address" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."tms_customer_price" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."tms_order" FOR SELECT USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."tms_station" FOR SELECT USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."vehicle_archive" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."vehicle_insurance_company" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."vehicle_parts" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."vehicle_parts_category" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_select" ON "public"."vehicle_supplier" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."sys_attachment" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."sys_audit_log" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."sys_role" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND "app_private"."is_tenant_admin"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."sys_role_menu" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND "app_private"."is_tenant_admin"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."sys_tenant" FOR UPDATE TO "authenticated" USING ("app_private"."is_platform_super"()) WITH CHECK ("app_private"."is_platform_super"());
CREATE POLICY "tenant_update" ON "public"."sys_user" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND ("app_private"."is_tenant_admin"() OR ("auth_user_id" = "auth"."uid"()))))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."sys_user_tenant" FOR UPDATE USING (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND "app_private"."is_tenant_admin"()))) WITH CHECK (("app_private"."is_platform_super"() OR (("tenant_id" = "app_private"."current_user_tenant_id"()) AND "app_private"."is_tenant_admin"())));
CREATE POLICY "tenant_update" ON "public"."tms_cargo" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."tms_carrier" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."tms_carrier_price" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK ((("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())) AND (EXISTS ( SELECT 1
   FROM "public"."tms_carrier" "carrier"
  WHERE (("carrier"."id" = "tms_carrier_price"."carrier_id") AND ("app_private"."is_platform_super"() OR ("carrier"."tenant_id" = "app_private"."current_user_tenant_id"()))))) AND (("driver_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."tms_driver" "driver"
  WHERE (("driver"."id" = "tms_carrier_price"."driver_id") AND ("driver"."carrier_id" = "tms_carrier_price"."carrier_id") AND ("app_private"."is_platform_super"() OR ("driver"."tenant_id" = "app_private"."current_user_tenant_id"())))))) AND (("vehicle_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."vehicle_archive" "vehicle"
  WHERE (("vehicle"."id" = "tms_carrier_price"."vehicle_id") AND (("vehicle"."carrier_id" IS NULL) OR ("vehicle"."carrier_id" = "tms_carrier_price"."carrier_id")) AND ("app_private"."is_platform_super"() OR ("vehicle"."tenant_id" = "app_private"."current_user_tenant_id"()))))))));
CREATE POLICY "tenant_update" ON "public"."tms_contract" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."tms_customer" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."tms_customer_address" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK ((("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())) AND (EXISTS ( SELECT 1
   FROM "public"."tms_customer" "customer"
  WHERE (("customer"."id" = "tms_customer_address"."customer_id") AND ("app_private"."is_platform_super"() OR ("customer"."tenant_id" = "app_private"."current_user_tenant_id"())))))));
CREATE POLICY "tenant_update" ON "public"."tms_customer_price" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK ((("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())) AND (EXISTS ( SELECT 1
   FROM "public"."tms_customer" "customer"
  WHERE (("customer"."id" = "tms_customer_price"."customer_id") AND ("app_private"."is_platform_super"() OR ("customer"."tenant_id" = "app_private"."current_user_tenant_id"())))))));
CREATE POLICY "tenant_update" ON "public"."tms_order" FOR UPDATE USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK ((("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())) AND (("shipping_customer_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."tms_customer" "customer"
  WHERE (("customer"."id" = "tms_order"."shipping_customer_id") AND ("app_private"."is_platform_super"() OR ("customer"."tenant_id" = "app_private"."current_user_tenant_id"())))))) AND (("receiving_customer_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."tms_customer" "customer"
  WHERE (("customer"."id" = "tms_order"."receiving_customer_id") AND ("app_private"."is_platform_super"() OR ("customer"."tenant_id" = "app_private"."current_user_tenant_id"()))))))));
CREATE POLICY "tenant_update" ON "public"."tms_station" FOR UPDATE USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."vehicle_archive" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."vehicle_insurance_company" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."vehicle_parts" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."vehicle_parts_category" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tenant_update" ON "public"."vehicle_supplier" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."tms_cargo" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_carrier" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_carrier_price" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_contract" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_customer" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_customer_address" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_customer_price" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_driver" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tms_driver_tenant_delete" ON "public"."tms_driver" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_driver_tenant_insert" ON "public"."tms_driver" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_driver_tenant_select" ON "public"."tms_driver" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_driver_tenant_update" ON "public"."tms_driver" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."tms_order" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_station" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_waybill" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tms_waybill_event" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tms_waybill_event_tenant_delete" ON "public"."tms_waybill_event" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_event_tenant_insert" ON "public"."tms_waybill_event" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_event_tenant_select" ON "public"."tms_waybill_event" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_event_tenant_update" ON "public"."tms_waybill_event" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."tms_waybill_proof" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tms_waybill_proof_tenant_delete" ON "public"."tms_waybill_proof" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_proof_tenant_insert" ON "public"."tms_waybill_proof" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_proof_tenant_select" ON "public"."tms_waybill_proof" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_proof_tenant_update" ON "public"."tms_waybill_proof" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_tenant_delete" ON "public"."tms_waybill" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_tenant_insert" ON "public"."tms_waybill" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_tenant_select" ON "public"."tms_waybill" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "tms_waybill_tenant_update" ON "public"."tms_waybill" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."vehicle_accident_record" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vehicle_accident_record_tenant_delete" ON "public"."vehicle_accident_record" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_accident_record_tenant_insert" ON "public"."vehicle_accident_record" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_accident_record_tenant_select" ON "public"."vehicle_accident_record" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_accident_record_tenant_update" ON "public"."vehicle_accident_record" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."vehicle_archive" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."vehicle_inspection" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vehicle_inspection_tenant_delete" ON "public"."vehicle_inspection" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_inspection_tenant_insert" ON "public"."vehicle_inspection" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_inspection_tenant_select" ON "public"."vehicle_inspection" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_inspection_tenant_update" ON "public"."vehicle_inspection" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."vehicle_insurance" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."vehicle_insurance_company" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vehicle_insurance_tenant_delete" ON "public"."vehicle_insurance" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_insurance_tenant_insert" ON "public"."vehicle_insurance" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_insurance_tenant_select" ON "public"."vehicle_insurance" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_insurance_tenant_update" ON "public"."vehicle_insurance" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."vehicle_maintenance_record" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vehicle_maintenance_record_tenant_delete" ON "public"."vehicle_maintenance_record" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_maintenance_record_tenant_insert" ON "public"."vehicle_maintenance_record" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_maintenance_record_tenant_select" ON "public"."vehicle_maintenance_record" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_maintenance_record_tenant_update" ON "public"."vehicle_maintenance_record" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."vehicle_mileage_record" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vehicle_mileage_record_tenant_delete" ON "public"."vehicle_mileage_record" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_mileage_record_tenant_insert" ON "public"."vehicle_mileage_record" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_mileage_record_tenant_select" ON "public"."vehicle_mileage_record" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_mileage_record_tenant_update" ON "public"."vehicle_mileage_record" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."vehicle_part_usage" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vehicle_part_usage_tenant_delete" ON "public"."vehicle_part_usage" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_part_usage_tenant_insert" ON "public"."vehicle_part_usage" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_part_usage_tenant_select" ON "public"."vehicle_part_usage" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_part_usage_tenant_update" ON "public"."vehicle_part_usage" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."vehicle_parts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."vehicle_parts_category" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."vehicle_routine_inspection_record" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vehicle_routine_inspection_record_tenant_delete" ON "public"."vehicle_routine_inspection_record" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_routine_inspection_record_tenant_insert" ON "public"."vehicle_routine_inspection_record" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_routine_inspection_record_tenant_select" ON "public"."vehicle_routine_inspection_record" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_routine_inspection_record_tenant_update" ON "public"."vehicle_routine_inspection_record" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER TABLE "public"."vehicle_supplier" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."vehicle_violation_record" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vehicle_violation_record_tenant_delete" ON "public"."vehicle_violation_record" FOR DELETE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_violation_record_tenant_insert" ON "public"."vehicle_violation_record" FOR INSERT TO "authenticated" WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_violation_record_tenant_select" ON "public"."vehicle_violation_record" FOR SELECT TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
CREATE POLICY "vehicle_violation_record_tenant_update" ON "public"."vehicle_violation_record" FOR UPDATE TO "authenticated" USING (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"()))) WITH CHECK (("app_private"."is_platform_super"() OR ("tenant_id" = "app_private"."current_user_tenant_id"())));
ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";
ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."sys_user";
ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."tms_order";
ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."tms_waybill";
ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."vehicle_archive";
GRANT USAGE ON SCHEMA "app_private" TO "authenticated";
GRANT USAGE ON SCHEMA "app_private" TO "service_role";
GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";
GRANT ALL ON FUNCTION "app_private"."current_user_tenant_id"() TO "authenticated";
GRANT ALL ON FUNCTION "app_private"."default_register_tenant_id"() TO "authenticated";
GRANT ALL ON FUNCTION "app_private"."is_platform_super"() TO "authenticated";
GRANT ALL ON FUNCTION "app_private"."is_tenant_admin"() TO "authenticated";
REVOKE ALL ON FUNCTION "app_private"."platform_tenant_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "app_private"."platform_tenant_id"() TO "authenticated";
GRANT ALL ON FUNCTION "app_private"."platform_tenant_id"() TO "service_role";
GRANT ALL ON FUNCTION "public"."clean_role_menus_on_role_delete"() TO "service_role";
REVOKE ALL ON FUNCTION "public"."current_is_super"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_is_super"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_is_super"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_is_super"() TO "service_role";
GRANT ALL ON FUNCTION "public"."execute_sql_query"("sql_query" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."execute_sql_query"("sql_query" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."execute_sql_query"("sql_query" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_app_user_display_name"() TO "service_role";
GRANT ALL ON FUNCTION "public"."get_database_metadata_all"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_database_metadata_all"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_database_metadata_all"() TO "service_role";
GRANT ALL ON FUNCTION "public"."get_menus_for_current_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_menus_for_current_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_menus_for_current_user"() TO "service_role";
GRANT ALL ON FUNCTION "public"."prevent_platform_tenant_change"() TO "service_role";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";
REVOKE ALL ON FUNCTION "public"."save_dict_type_tree_order"("p_updates" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_dict_type_tree_order"("p_updates" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_dict_type_tree_order"("p_updates" "jsonb") TO "service_role";
REVOKE ALL ON FUNCTION "public"."set_role_menus"("p_role_id" "uuid", "p_menu_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_role_menus"("p_role_id" "uuid", "p_menu_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_role_menus"("p_role_id" "uuid", "p_menu_ids" "uuid"[]) TO "service_role";
GRANT ALL ON FUNCTION "public"."set_vehicle_parts_category_level"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_vehicle_parts_category_level"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_vehicle_parts_category_level"() TO "service_role";
GRANT ALL ON FUNCTION "public"."sync_delete_app_user_on_auth_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_delete_app_user_on_auth_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_delete_app_user_on_auth_delete"() TO "service_role";
REVOKE ALL ON FUNCTION "public"."tms_cancel_order_with_waybill"("p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."tms_cancel_order_with_waybill"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."tms_cancel_order_with_waybill"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tms_cancel_order_with_waybill"("p_order_id" "uuid") TO "service_role";
REVOKE ALL ON FUNCTION "public"."tms_cancel_orders_with_waybills"("p_order_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."tms_cancel_orders_with_waybills"("p_order_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."tms_cancel_orders_with_waybills"("p_order_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tms_cancel_orders_with_waybills"("p_order_ids" "uuid"[]) TO "service_role";
REVOKE ALL ON FUNCTION "public"."tms_complete_order_with_waybill"("p_order_id" "uuid", "p_signed_cod_amount" numeric, "p_receipt_image_urls" "jsonb", "p_signed_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."tms_complete_order_with_waybill"("p_order_id" "uuid", "p_signed_cod_amount" numeric, "p_receipt_image_urls" "jsonb", "p_signed_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."tms_complete_order_with_waybill"("p_order_id" "uuid", "p_signed_cod_amount" numeric, "p_receipt_image_urls" "jsonb", "p_signed_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tms_complete_order_with_waybill"("p_order_id" "uuid", "p_signed_cod_amount" numeric, "p_receipt_image_urls" "jsonb", "p_signed_at" timestamp with time zone) TO "service_role";
REVOKE ALL ON FUNCTION "public"."tms_confirm_waybill_departure"("p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."tms_confirm_waybill_departure"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."tms_confirm_waybill_departure"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tms_confirm_waybill_departure"("p_order_id" "uuid") TO "service_role";
REVOKE ALL ON FUNCTION "public"."tms_delete_order_with_waybill"("p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."tms_delete_order_with_waybill"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."tms_delete_order_with_waybill"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tms_delete_order_with_waybill"("p_order_id" "uuid") TO "service_role";
REVOKE ALL ON FUNCTION "public"."tms_delete_orders_with_waybills"("p_order_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."tms_delete_orders_with_waybills"("p_order_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."tms_delete_orders_with_waybills"("p_order_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tms_delete_orders_with_waybills"("p_order_ids" "uuid"[]) TO "service_role";
GRANT ALL ON FUNCTION "public"."trg_set_create_time_and_by"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_set_create_time_and_by"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_set_create_time_and_by"() TO "service_role";
GRANT ALL ON FUNCTION "public"."trg_set_update_time_and_by"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_set_update_time_and_by"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_set_update_time_and_by"() TO "service_role";
GRANT ALL ON FUNCTION "public"."trg_set_waybill_child_tenant"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_set_waybill_child_tenant"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_set_waybill_child_tenant"() TO "service_role";
GRANT ALL ON FUNCTION "public"."trg_sync_completed_waybill_from_order"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_sync_completed_waybill_from_order"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_sync_completed_waybill_from_order"() TO "service_role";
GRANT ALL ON FUNCTION "public"."trg_sync_order_terminal_status_from_waybill"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_sync_order_terminal_status_from_waybill"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_sync_order_terminal_status_from_waybill"() TO "service_role";
GRANT ALL ON FUNCTION "public"."trg_sync_tms_order_status_from_waybill"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_sync_tms_order_status_from_waybill"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_sync_tms_order_status_from_waybill"() TO "service_role";
GRANT ALL ON FUNCTION "public"."trg_sync_tms_waybill_cancel_from_order"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_sync_tms_waybill_cancel_from_order"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_sync_tms_waybill_cancel_from_order"() TO "service_role";
GRANT ALL ON FUNCTION "public"."trg_validate_tms_waybill_status_transition"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_validate_tms_waybill_status_transition"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_validate_tms_waybill_status_transition"() TO "service_role";
GRANT ALL ON TABLE "public"."sys_attachment" TO "anon";
GRANT ALL ON TABLE "public"."sys_attachment" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_attachment" TO "service_role";
GRANT ALL ON TABLE "public"."sys_audit_log" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_dict_type" TO "anon";
GRANT ALL ON TABLE "public"."sys_dict_type" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_dict_type" TO "service_role";
GRANT ALL ON TABLE "public"."sys_dictionary" TO "anon";
GRANT ALL ON TABLE "public"."sys_dictionary" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_dictionary" TO "service_role";
GRANT ALL ON TABLE "public"."sys_menu" TO "anon";
GRANT ALL ON TABLE "public"."sys_menu" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_menu" TO "service_role";
GRANT ALL ON TABLE "public"."sys_param" TO "anon";
GRANT ALL ON TABLE "public"."sys_param" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_param" TO "service_role";
GRANT ALL ON TABLE "public"."sys_role" TO "anon";
GRANT ALL ON TABLE "public"."sys_role" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_role" TO "service_role";
GRANT ALL ON TABLE "public"."sys_role_menu" TO "anon";
GRANT ALL ON TABLE "public"."sys_role_menu" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_role_menu" TO "service_role";
GRANT ALL ON TABLE "public"."sys_tenant" TO "anon";
GRANT ALL ON TABLE "public"."sys_tenant" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_tenant" TO "service_role";
GRANT ALL ON TABLE "public"."sys_user" TO "anon";
GRANT ALL ON TABLE "public"."sys_user" TO "authenticated";
GRANT ALL ON TABLE "public"."sys_user" TO "service_role";
GRANT ALL ON TABLE "public"."sys_user_tenant" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_user_tenant" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."tms_cargo_code_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."tms_cargo_code_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."tms_cargo_code_seq" TO "service_role";
GRANT ALL ON TABLE "public"."tms_cargo" TO "anon";
GRANT ALL ON TABLE "public"."tms_cargo" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_cargo" TO "service_role";
GRANT ALL ON SEQUENCE "public"."tms_carrier_code_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."tms_carrier_code_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."tms_carrier_code_seq" TO "service_role";
GRANT ALL ON TABLE "public"."tms_carrier" TO "anon";
GRANT ALL ON TABLE "public"."tms_carrier" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_carrier" TO "service_role";
GRANT ALL ON TABLE "public"."tms_carrier_price" TO "anon";
GRANT ALL ON TABLE "public"."tms_carrier_price" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_carrier_price" TO "service_role";
GRANT ALL ON SEQUENCE "public"."tms_contract_no_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."tms_contract_no_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."tms_contract_no_seq" TO "service_role";
GRANT ALL ON TABLE "public"."tms_contract" TO "anon";
GRANT ALL ON TABLE "public"."tms_contract" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_contract" TO "service_role";
GRANT ALL ON SEQUENCE "public"."tms_customer_code_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."tms_customer_code_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."tms_customer_code_seq" TO "service_role";
GRANT ALL ON TABLE "public"."tms_customer" TO "anon";
GRANT ALL ON TABLE "public"."tms_customer" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_customer" TO "service_role";
GRANT ALL ON TABLE "public"."tms_customer_address" TO "anon";
GRANT ALL ON TABLE "public"."tms_customer_address" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_customer_address" TO "service_role";
GRANT ALL ON TABLE "public"."tms_customer_price" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_customer_price" TO "service_role";
GRANT ALL ON TABLE "public"."tms_driver" TO "anon";
GRANT ALL ON TABLE "public"."tms_driver" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_driver" TO "service_role";
GRANT ALL ON TABLE "public"."tms_order" TO "anon";
GRANT ALL ON TABLE "public"."tms_order" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_order" TO "service_role";
GRANT ALL ON TABLE "public"."tms_station" TO "anon";
GRANT ALL ON TABLE "public"."tms_station" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_station" TO "service_role";
GRANT ALL ON TABLE "public"."tms_waybill" TO "anon";
GRANT ALL ON TABLE "public"."tms_waybill" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_waybill" TO "service_role";
GRANT ALL ON TABLE "public"."tms_waybill_event" TO "anon";
GRANT ALL ON TABLE "public"."tms_waybill_event" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_waybill_event" TO "service_role";
GRANT ALL ON TABLE "public"."tms_waybill_proof" TO "anon";
GRANT ALL ON TABLE "public"."tms_waybill_proof" TO "authenticated";
GRANT ALL ON TABLE "public"."tms_waybill_proof" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_accident_record" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_accident_record" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_accident_record" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_archive" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_archive" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_archive" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_inspection" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_inspection" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_inspection" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_insurance" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_insurance" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_insurance" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_insurance_company" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_insurance_company" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_insurance_company" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_maintenance_record" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_maintenance_record" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_maintenance_record" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_mileage_record" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_mileage_record" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_mileage_record" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_part_usage" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_part_usage" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_part_usage" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_parts" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_parts" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_parts" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_parts_category" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_parts_category" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_parts_category" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_reminder_inspection_expiry" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_reminder_inspection_expiry" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_reminder_inspection_expiry" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_reminder_insurance_expiry" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_reminder_insurance_expiry" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_reminder_insurance_expiry" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_reminder_maintenance_expiry" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_reminder_maintenance_expiry" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_reminder_maintenance_expiry" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_reminder_part_service_life" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_reminder_part_service_life" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_reminder_part_service_life" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_reminder_vehicle_service_life" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_reminder_vehicle_service_life" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_reminder_vehicle_service_life" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_routine_inspection_record" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_routine_inspection_record" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_routine_inspection_record" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_supplier" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_supplier" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_supplier" TO "service_role";
GRANT ALL ON TABLE "public"."vehicle_violation_record" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_violation_record" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_violation_record" TO "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
