CREATE VIEW mergestat.schema_introspection AS
 SELECT t.table_schema AS schema,
    t.table_name,
    t.table_type,
    c.column_name,
    c.ordinal_position,
    c.is_nullable,
    c.data_type,
    c.udt_name,
    col_description(((format('%s.%s'::text, c.table_schema, c.table_name))::regclass)::oid, (c.ordinal_position)::integer) AS column_description
   FROM (information_schema.tables t
     JOIN information_schema.columns c ON ((((t.table_name)::name = (c.table_name)::name) AND ((t.table_schema)::name = (c.table_schema)::name))))
  WHERE (((t.table_schema)::name = ANY (ARRAY['public'::name, 'mergestat'::name, 'sqlq'::name])) AND ((t.table_name)::name !~~ 'g\_%'::text) AND ((t.table_name)::name !~~ 'google\_%'::text) AND ((t.table_name)::name !~~ 'hypopg\_%'::text))
  ORDER BY (array_position(ARRAY['public'::text, 'mergestat'::text, 'sqlq'::text], (t.table_schema)::text)), t.table_name, c.column_name;

GRANT SELECT ON TABLE mergestat.schema_introspection TO readaccess;
GRANT ALL ON TABLE mergestat.schema_introspection TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.schema_introspection TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.schema_introspection TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.schema_introspection TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.schema_introspection TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.schema_introspection TO mergestat_role_queries_only;

