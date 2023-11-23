CREATE TABLE mergestat.container_sync_executions (
    sync_id uuid NOT NULL,
    job_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

GRANT SELECT ON TABLE mergestat.container_sync_executions TO readaccess;
GRANT ALL ON TABLE mergestat.container_sync_executions TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_sync_executions TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_sync_executions TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_sync_executions TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_sync_executions TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_sync_executions TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.container_sync_executions
    ADD CONSTRAINT container_sync_executions_pkey PRIMARY KEY (sync_id, job_id);
ALTER TABLE ONLY mergestat.container_sync_executions
    ADD CONSTRAINT fk_execution_job FOREIGN KEY (job_id) REFERENCES sqlq.jobs(id) ON DELETE CASCADE;
ALTER TABLE ONLY mergestat.container_sync_executions
    ADD CONSTRAINT fk_execution_sync FOREIGN KEY (sync_id) REFERENCES mergestat.container_syncs(id) ON DELETE CASCADE;

