CREATE VIEW mergestat.user_mgmt_pg_users AS
 WITH users AS (
         SELECT r.rolname,
            r.rolsuper,
            r.rolinherit,
            r.rolcreaterole,
            r.rolcreatedb,
            r.rolcanlogin,
            r.rolconnlimit,
            r.rolvaliduntil,
            r.rolreplication,
            r.rolbypassrls,
            ARRAY( SELECT b.rolname
                   FROM (pg_auth_members m
                     JOIN pg_roles b ON ((m.roleid = b.oid)))
                  WHERE (m.member = r.oid)) AS memberof
           FROM pg_roles r
          WHERE ((r.rolname !~ '^pg_'::text) AND r.rolcanlogin)
          ORDER BY r.rolname
        )
 SELECT users.rolname,
    users.rolsuper,
    users.rolinherit,
    users.rolcreaterole,
    users.rolcreatedb,
    users.rolcanlogin,
    users.rolconnlimit,
    users.rolvaliduntil,
    users.rolreplication,
    users.rolbypassrls,
    users.memberof
   FROM users
  WHERE ((users.memberof && ARRAY['mergestat_role_admin'::name, 'mergestat_role_user'::name, 'mergestat_role_queries_only'::name, 'mergestat_role_readonly'::name]) AND (users.rolname <> 'mergestat_admin'::name));

GRANT SELECT ON TABLE mergestat.user_mgmt_pg_users TO readaccess;
GRANT ALL ON TABLE mergestat.user_mgmt_pg_users TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.user_mgmt_pg_users TO mergestat_role_queries_only;

