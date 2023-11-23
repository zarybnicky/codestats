CREATE TABLE mergestat.repo_sync_logs (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    log_type text NOT NULL,
    message text NOT NULL,
    repo_sync_queue_id bigint NOT NULL
);

GRANT ALL ON TABLE mergestat.repo_sync_logs TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_logs TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_logs TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_logs TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_logs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_logs TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_logs TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_sync_logs
    ADD CONSTRAINT repo_sync_logs_pkey PRIMARY KEY (id);
ALTER TABLE ONLY mergestat.repo_sync_logs
    ADD CONSTRAINT repo_sync_logs_log_type_fkey FOREIGN KEY (log_type) REFERENCES mergestat.repo_sync_log_types(type) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY mergestat.repo_sync_logs
    ADD CONSTRAINT repo_sync_logs_repo_sync_queue_id_fkey FOREIGN KEY (repo_sync_queue_id) REFERENCES mergestat.repo_sync_queue(id) ON UPDATE RESTRICT ON DELETE CASCADE;

CREATE INDEX idx_repo_sync_logs_repo_sync_created_at ON mergestat.repo_sync_logs USING btree (created_at DESC);
CREATE INDEX idx_repo_sync_logs_repo_sync_queue_id ON mergestat.repo_sync_logs USING btree (repo_sync_queue_id DESC);
CREATE INDEX idx_repo_sync_logs_repo_sync_queue_id_fkey ON mergestat.repo_sync_logs USING btree (repo_sync_queue_id);