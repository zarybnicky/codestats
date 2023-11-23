CREATE TABLE mergestat.saved_explores (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    created_by text,
    created_at timestamp with time zone,
    name text,
    description text,
    metadata jsonb
);

COMMENT ON TABLE mergestat.saved_explores IS 'Table to save explores';
COMMENT ON COLUMN mergestat.saved_explores.created_by IS 'explore creator';
COMMENT ON COLUMN mergestat.saved_explores.created_at IS 'timestamp when explore was created';
COMMENT ON COLUMN mergestat.saved_explores.name IS 'explore name';
COMMENT ON COLUMN mergestat.saved_explores.description IS 'explore description';
COMMENT ON COLUMN mergestat.saved_explores.metadata IS 'explore metadata';

GRANT SELECT ON TABLE mergestat.saved_explores TO readaccess;
GRANT ALL ON TABLE mergestat.saved_explores TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.saved_explores TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.saved_explores TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.saved_explores TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.saved_explores TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.saved_explores TO mergestat_role_queries_only;
ALTER TABLE mergestat.saved_explores ENABLE ROW LEVEL SECURITY;

ALTER TABLE ONLY mergestat.saved_explores
    ADD CONSTRAINT saved_explores_pkey PRIMARY KEY (id);

CREATE POLICY saved_explores_all_access ON mergestat.saved_explores USING ((created_by = CURRENT_USER));
CREATE POLICY saved_explores_all_access_admin ON mergestat.saved_explores TO mergestat_role_admin USING (true);
CREATE POLICY saved_explores_all_view ON mergestat.saved_explores FOR SELECT USING (true);

