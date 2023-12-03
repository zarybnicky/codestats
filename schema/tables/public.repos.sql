CREATE TABLE public.repos (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    repo text NOT NULL,
    ref text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    settings jsonb DEFAULT jsonb_build_object() NOT NULL,
    tags jsonb DEFAULT jsonb_build_array() NOT NULL,
    repo_import_id uuid,
    provider uuid NOT NULL,
    is_duplicate boolean DEFAULT false NOT NULL
);

COMMENT ON TABLE public.repos IS 'git repositories to track';
COMMENT ON COLUMN public.repos.id IS 'MergeStat identifier for the repo';
COMMENT ON COLUMN public.repos.repo IS 'URL for the repo';
COMMENT ON COLUMN public.repos.ref IS 'ref for the repo';
COMMENT ON COLUMN public.repos.created_at IS 'timestamp of when the MergeStat repo entry was created';
COMMENT ON COLUMN public.repos.settings IS 'JSON settings for the repo';
COMMENT ON COLUMN public.repos.tags IS 'array of tags for the repo for topics in GitHub as well as tags added in MergeStat';
COMMENT ON COLUMN public.repos.repo_import_id IS 'foreign key for mergestat.repo_imports.id';

GRANT SELECT ON TABLE public.repos TO readaccess;
GRANT ALL ON TABLE public.repos TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.repos TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.repos TO mergestat_role_user;
GRANT ALL ON TABLE public.repos TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.repos TO mergestat_role_demo;
GRANT SELECT ON TABLE public.repos TO mergestat_role_queries_only;

ALTER TABLE ONLY public.repos
    ADD CONSTRAINT repos_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.repos
    ADD CONSTRAINT fk_repos_provider FOREIGN KEY (provider) REFERENCES mergestat.providers(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.repos
    ADD CONSTRAINT repos_repo_import_id_fkey FOREIGN KEY (repo_import_id) REFERENCES mergestat.repo_imports(id) ON UPDATE RESTRICT ON DELETE CASCADE;

CREATE INDEX idx_repos_repo_import_id_fkey ON public.repos USING btree (repo_import_id);
CREATE INDEX repos_is_duplicate ON public.repos USING btree (is_duplicate);
CREATE UNIQUE INDEX repos_repo_ref_unique ON public.repos USING btree (repo, ((ref IS NULL))) WHERE (ref IS NULL);