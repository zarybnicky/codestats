CREATE TABLE mergestat.repo_syncs (
    repo_id uuid NOT NULL,
    sync_type text NOT NULL,
    settings jsonb DEFAULT jsonb_build_object() NOT NULL,
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    schedule_enabled boolean DEFAULT false NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    last_completed_repo_sync_queue_id bigint
);

GRANT ALL ON TABLE mergestat.repo_syncs TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_syncs TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_syncs TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_syncs TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_syncs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_syncs TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_syncs TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT repo_sync_settings_pkey PRIMARY KEY (id);
ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT repo_syncs_repo_id_sync_type_key UNIQUE (repo_id, sync_type);
ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT last_completed_repo_sync_queue_id_fk FOREIGN KEY (last_completed_repo_sync_queue_id) REFERENCES mergestat.repo_sync_queue(id) ON DELETE SET NULL;
ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT repo_sync_settings_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY mergestat.repo_syncs
    ADD CONSTRAINT repo_syncs_sync_type_fkey FOREIGN KEY (sync_type) REFERENCES mergestat.repo_sync_types(type) ON UPDATE RESTRICT ON DELETE RESTRICT;

CREATE INDEX idx_repo_sync_settings_repo_id_fkey ON mergestat.repo_syncs USING btree (repo_id);