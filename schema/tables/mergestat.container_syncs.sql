CREATE TABLE mergestat.container_syncs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    repo_id uuid NOT NULL,
    image_id uuid NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb NOT NULL
);

GRANT SELECT ON TABLE mergestat.container_syncs TO readaccess;
GRANT ALL ON TABLE mergestat.container_syncs TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_syncs TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.container_syncs TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.container_syncs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.container_syncs TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.container_syncs TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.container_syncs
    ADD CONSTRAINT container_syncs_pkey PRIMARY KEY (id);
ALTER TABLE ONLY mergestat.container_syncs
    ADD CONSTRAINT unq_repo_image UNIQUE (repo_id, image_id);
ALTER TABLE ONLY mergestat.container_syncs
    ADD CONSTRAINT fk_sync_container FOREIGN KEY (image_id) REFERENCES mergestat.container_images(id) ON DELETE CASCADE;
ALTER TABLE ONLY mergestat.container_syncs
    ADD CONSTRAINT fk_sync_repository FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON DELETE CASCADE;

