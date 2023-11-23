CREATE TABLE mergestat.repo_import_types (
    type text NOT NULL,
    description text NOT NULL
);

COMMENT ON TABLE mergestat.repo_import_types IS 'Types of repo imports';

GRANT ALL ON TABLE mergestat.repo_import_types TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_import_types TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_import_types TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_import_types TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_import_types TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_import_types TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_import_types TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_import_types
    ADD CONSTRAINT repo_import_types_pkey PRIMARY KEY (type);

