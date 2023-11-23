CREATE TABLE mergestat.repo_sync_queue_status_types (
    type text NOT NULL,
    description text
);

GRANT ALL ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_queue_status_types TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_queue_status_types TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_sync_queue_status_types
    ADD CONSTRAINT repo_sync_queue_status_types_pkey PRIMARY KEY (type);

