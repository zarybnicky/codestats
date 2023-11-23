CREATE TABLE public.git_files (
    repo_id uuid NOT NULL,
    path text NOT NULL,
    executable boolean NOT NULL,
    contents text,
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL
);

COMMENT ON TABLE public.git_files IS 'git files (content and paths) of a repo';
COMMENT ON COLUMN public.git_files.repo_id IS 'foreign key for public.repos.id';
COMMENT ON COLUMN public.git_files.path IS 'path of the file';
COMMENT ON COLUMN public.git_files.executable IS 'boolean to determine if the file is an executable';
COMMENT ON COLUMN public.git_files.contents IS 'contents of the file';
COMMENT ON COLUMN public.git_files._mergestat_synced_at IS 'timestamp when record was synced into the MergeStat database';

GRANT SELECT ON TABLE public.git_files TO readaccess;
GRANT ALL ON TABLE public.git_files TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_files TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.git_files TO mergestat_role_user;
GRANT ALL ON TABLE public.git_files TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_files TO mergestat_role_demo;
GRANT SELECT ON TABLE public.git_files TO mergestat_role_queries_only;

ALTER TABLE ONLY public.git_files
    ADD CONSTRAINT files_pkey PRIMARY KEY (repo_id, path);
ALTER TABLE ONLY public.git_files
    ADD CONSTRAINT git_files_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;

CREATE INDEX idx_files_repo_id_fkey ON public.git_files USING btree (repo_id);
CREATE INDEX idx_gist_git_files_path ON public.git_files USING gist (path public.gist_trgm_ops);