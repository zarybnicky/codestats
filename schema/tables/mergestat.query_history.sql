CREATE TABLE mergestat.query_history (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    run_at timestamp with time zone DEFAULT now(),
    run_by text NOT NULL,
    query text NOT NULL
);

GRANT SELECT ON TABLE mergestat.query_history TO readaccess;
GRANT ALL ON TABLE mergestat.query_history TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT,INSERT ON TABLE mergestat.query_history TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.query_history TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.query_history TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT,INSERT ON TABLE mergestat.query_history TO mergestat_role_demo;
GRANT SELECT,INSERT ON TABLE mergestat.query_history TO mergestat_role_queries_only;
ALTER TABLE mergestat.query_history ENABLE ROW LEVEL SECURITY;

ALTER TABLE ONLY mergestat.query_history
    ADD CONSTRAINT query_history_pkey PRIMARY KEY (id);

CREATE POLICY query_history_access ON mergestat.query_history USING ((run_by = CURRENT_USER));

