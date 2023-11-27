-- Write your migration here

do $$
begin
if not exists (select * from mergestat.providers) then
  insert into mergestat.providers (name, vendor, settings)
  values ('Gitolite', 'local', '{}'), ('Gitlab', 'local', '{}');
end if;
end
$$;
