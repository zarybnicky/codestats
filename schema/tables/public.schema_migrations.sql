CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    dirty boolean NOT NULL
);

COMMENT ON TABLE public.schema_migrations IS 'MergeStat internal table to track schema migrations';

GRANT SELECT ON TABLE public.schema_migrations TO readaccess;
GRANT ALL ON TABLE public.schema_migrations TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.schema_migrations TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.schema_migrations TO mergestat_role_user;
GRANT ALL ON TABLE public.schema_migrations TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.schema_migrations TO mergestat_role_demo;
GRANT SELECT ON TABLE public.schema_migrations TO mergestat_role_queries_only;

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);

CREATE TRIGGER track_applied_migrations AFTER INSERT ON public.schema_migrations FOR EACH ROW EXECUTE FUNCTION public.track_applied_migration();
