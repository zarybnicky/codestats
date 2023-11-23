CREATE TABLE mergestat.repo_sync_type_groups (
    "group" text NOT NULL,
    concurrent_syncs integer
);

GRANT SELECT ON TABLE mergestat.repo_sync_type_groups TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_admin WITH GRANT OPTION;
GRANT ALL ON TABLE mergestat.repo_sync_type_groups TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_type_groups TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_sync_type_groups
    ADD CONSTRAINT repo_sync_type_groups_group_pkey PRIMARY KEY ("group");

