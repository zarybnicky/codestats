CREATE TABLE mergestat.repo_sync_queue (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    repo_sync_id uuid NOT NULL,
    status text NOT NULL,
    started_at timestamp with time zone,
    done_at timestamp with time zone,
    last_keep_alive timestamp with time zone,
    priority integer DEFAULT 0 NOT NULL,
    type_group text DEFAULT 'DEFAULT'::text NOT NULL
);

GRANT ALL ON TABLE mergestat.repo_sync_queue TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_queue TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_sync_queue TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_queue TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_queue TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_queue TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_queue TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_sync_queue
    ADD CONSTRAINT repo_sync_queue_pkey PRIMARY KEY (id);
ALTER TABLE ONLY mergestat.repo_sync_queue
    ADD CONSTRAINT repo_sync_queue_repo_sync_id_fkey FOREIGN KEY (repo_sync_id) REFERENCES mergestat.repo_syncs(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY mergestat.repo_sync_queue
    ADD CONSTRAINT repo_sync_queue_status_fkey FOREIGN KEY (status) REFERENCES mergestat.repo_sync_queue_status_types(type) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY mergestat.repo_sync_queue
    ADD CONSTRAINT repo_sync_queue_type_group_fkey FOREIGN KEY (type_group) REFERENCES mergestat.repo_sync_type_groups("group") ON UPDATE RESTRICT ON DELETE RESTRICT;

CREATE TRIGGER repo_sync_queue_status_update_trigger BEFORE UPDATE ON mergestat.repo_sync_queue FOR EACH ROW EXECUTE FUNCTION public.repo_sync_queue_status_update_trigger();

CREATE INDEX idx_repo_sync_queue_created_at ON mergestat.repo_sync_queue USING btree (created_at DESC);
CREATE INDEX idx_repo_sync_queue_done_at ON mergestat.repo_sync_queue USING btree (done_at DESC);
CREATE INDEX idx_repo_sync_queue_repo_sync_id_fkey ON mergestat.repo_sync_queue USING btree (repo_sync_id);
CREATE INDEX idx_repo_sync_queue_status ON mergestat.repo_sync_queue USING btree (status DESC);