-- Existing grants remain unchanged. New public-schema functions must opt in
-- to authenticated execution explicitly in the migration that creates them.
alter default privileges for role postgres in schema public
  revoke execute on functions from authenticated;;
