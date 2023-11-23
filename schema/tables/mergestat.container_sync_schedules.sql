CREATE TABLE mergestat.container_sync_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sync_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

GRANT SELECT ON TABLE mergestat.container_sync_schedules TO readaccess;
GRANT ALL ON TABLE mergestat.container_sync_schedules TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_sync_schedules TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_sync_schedules TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_sync_schedules TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_sync_schedules TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_sync_schedules TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.container_sync_schedules
    ADD CONSTRAINT container_sync_schedules_pkey PRIMARY KEY (id);
ALTER TABLE ONLY mergestat.container_sync_schedules
    ADD CONSTRAINT unique_container_sync_schedule UNIQUE (sync_id);
ALTER TABLE ONLY mergestat.container_sync_schedules
    ADD CONSTRAINT fk_schedule_sync FOREIGN KEY (sync_id) REFERENCES mergestat.container_syncs(id) ON DELETE CASCADE;

