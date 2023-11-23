CREATE TABLE mergestat.repo_sync_type_labels (
    label text NOT NULL,
    description text,
    color text DEFAULT '#dddddd'::text NOT NULL,
    CONSTRAINT repo_sync_type_labels_color_check CHECK (((color IS NULL) OR (color ~* '^#[a-f0-9]{2}[a-f0-9]{2}[a-f0-9]{2}$'::text)))
);

COMMENT ON TABLE mergestat.repo_sync_type_labels IS '@name labels';

GRANT SELECT ON TABLE mergestat.repo_sync_type_labels TO readaccess;
GRANT ALL ON TABLE mergestat.repo_sync_type_labels TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_type_labels TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_sync_type_labels
    ADD CONSTRAINT repo_sync_type_labels_pkey PRIMARY KEY (label);

