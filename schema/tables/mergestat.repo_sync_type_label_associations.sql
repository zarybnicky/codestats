CREATE TABLE mergestat.repo_sync_type_label_associations (
    label text NOT NULL,
    repo_sync_type text NOT NULL
);

COMMENT ON TABLE mergestat.repo_sync_type_label_associations IS '@name labelAssociations';

GRANT SELECT ON TABLE mergestat.repo_sync_type_label_associations TO readaccess;
GRANT ALL ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_sync_type_label_associations TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_sync_type_label_associations
    ADD CONSTRAINT repo_sync_type_label_associations_label_repo_sync_type_key UNIQUE (label, repo_sync_type);
ALTER TABLE ONLY mergestat.repo_sync_type_label_associations
    ADD CONSTRAINT repo_sync_type_label_associations_label_fkey FOREIGN KEY (label) REFERENCES mergestat.repo_sync_type_labels(label) ON DELETE CASCADE;
ALTER TABLE ONLY mergestat.repo_sync_type_label_associations
    ADD CONSTRAINT repo_sync_type_label_associations_repo_sync_type_fkey FOREIGN KEY (repo_sync_type) REFERENCES mergestat.repo_sync_types(type) ON DELETE CASCADE;

