CREATE TABLE public.schema_migrations_history (
    id integer NOT NULL,
    version bigint NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
);

COMMENT ON TABLE public.schema_migrations_history IS 'MergeStat internal table to track schema migrations history';

GRANT SELECT ON TABLE public.schema_migrations_history TO readaccess;
GRANT ALL ON TABLE public.schema_migrations_history TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.schema_migrations_history TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.schema_migrations_history TO mergestat_role_user;
GRANT ALL ON TABLE public.schema_migrations_history TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.schema_migrations_history TO mergestat_role_demo;
GRANT SELECT ON TABLE public.schema_migrations_history TO mergestat_role_queries_only;

ALTER TABLE ONLY public.schema_migrations_history
    ADD CONSTRAINT schema_migrations_history_pkey PRIMARY KEY (id);

