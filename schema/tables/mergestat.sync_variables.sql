CREATE TABLE mergestat.sync_variables (
    repo_id uuid NOT NULL,
    key public.citext NOT NULL,
    value bytea
);

GRANT SELECT ON TABLE mergestat.sync_variables TO readaccess;
GRANT ALL ON TABLE mergestat.sync_variables TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.sync_variables TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.sync_variables TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.sync_variables TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.sync_variables TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.sync_variables TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.sync_variables
    ADD CONSTRAINT sync_variables_pkey PRIMARY KEY (repo_id, key);
ALTER TABLE ONLY mergestat.sync_variables
    ADD CONSTRAINT sync_variables_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id);

