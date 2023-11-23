CREATE TABLE mergestat.repo_imports (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    settings jsonb DEFAULT jsonb_build_object() NOT NULL,
    last_import timestamp with time zone,
    import_interval interval DEFAULT '00:30:00'::interval,
    last_import_started_at timestamp with time zone,
    import_status text,
    import_error text,
    provider uuid NOT NULL,
    CONSTRAINT repo_imports_import_interval_check CHECK ((import_interval > '00:00:30'::interval))
);

COMMENT ON TABLE mergestat.repo_imports IS 'Table for "dynamic" repo imports - regularly loading from a GitHub org for example';

GRANT ALL ON TABLE mergestat.repo_imports TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_imports TO readaccess;
GRANT SELECT ON TABLE mergestat.repo_imports TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.repo_imports TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.repo_imports TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.repo_imports TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.repo_imports TO mergestat_role_queries_only;

ALTER TABLE ONLY mergestat.repo_imports
    ADD CONSTRAINT repo_imports_pkey PRIMARY KEY (id);
ALTER TABLE ONLY mergestat.repo_imports
    ADD CONSTRAINT fk_providers_repo_imports_provider FOREIGN KEY (provider) REFERENCES mergestat.providers(id) ON DELETE CASCADE;

CREATE TRIGGER set_mergestat_repo_imports_updated_at BEFORE UPDATE ON mergestat.repo_imports FOR EACH ROW EXECUTE FUNCTION mergestat.set_current_timestamp_updated_at();
