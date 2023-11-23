CREATE TABLE mergestat.saved_queries (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    created_by text,
    created_at timestamp with time zone,
    name text NOT NULL,
    description text,
    sql text NOT NULL,
    metadata jsonb
);

COMMENT ON TABLE mergestat.saved_queries IS 'Table to save queries';
COMMENT ON COLUMN mergestat.saved_queries.created_by IS 'query creator';
COMMENT ON COLUMN mergestat.saved_queries.created_at IS 'timestamp when query was created';
COMMENT ON COLUMN mergestat.saved_queries.name IS 'query name';
COMMENT ON COLUMN mergestat.saved_queries.description IS 'query description';
COMMENT ON COLUMN mergestat.saved_queries.sql IS 'query sql';
COMMENT ON COLUMN mergestat.saved_queries.metadata IS 'query metadata';

GRANT SELECT ON TABLE mergestat.saved_queries TO readaccess;
GRANT ALL ON TABLE mergestat.saved_queries TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.saved_queries TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.saved_queries TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.saved_queries TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.saved_queries TO mergestat_role_demo;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.saved_queries TO mergestat_role_queries_only;
ALTER TABLE mergestat.saved_queries ENABLE ROW LEVEL SECURITY;

ALTER TABLE ONLY mergestat.saved_queries
    ADD CONSTRAINT saved_queries_pkey PRIMARY KEY (id);

CREATE POLICY saved_queries_all_access ON mergestat.saved_queries USING ((created_by = CURRENT_USER));
CREATE POLICY saved_queries_all_access_admin ON mergestat.saved_queries TO mergestat_role_admin USING (true);
CREATE POLICY saved_queries_all_view ON mergestat.saved_queries FOR SELECT USING (true);

