CREATE TABLE mergestat.repo_sync_types (
    type text NOT NULL,
    description text,
    short_name text DEFAULT ''::text NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    type_group text DEFAULT 'DEFAULT'::text NOT NULL
);

GRANT ALL ON TABLE mergestat.repo_sync_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_types TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_types TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_sync_types
    ADD CONSTRAINT repo_sync_types_pkey PRIMARY KEY (type);
ALTER TABLE ONLY mergestat.repo_sync_types
    ADD CONSTRAINT repo_sync_types_type_group_fkey FOREIGN KEY (type_group) REFERENCES mergestat.repo_sync_type_groups("group") ON UPDATE RESTRICT ON DELETE RESTRICT;

