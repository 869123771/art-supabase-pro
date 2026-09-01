revoke all on function public.current_is_super() from public, anon;
grant execute on function public.current_is_super() to authenticated, service_role;

alter function public.execute_sql_query(text)
  set search_path = pg_catalog, public;

alter function public.get_database_metadata_all()
  set search_path = pg_catalog, public;;
