CREATE TABLE public._mergestat_explore_repo_metadata (
    repo_id uuid NOT NULL,
    last_commit_hash text,
    last_commit_message text,
    last_commit_author_name text,
    last_commit_author_email text,
    last_commit_author_when timestamp with time zone,
    last_commit_committer_name text,
    last_commit_committer_email text,
    last_commit_committer_when timestamp with time zone,
    last_commit_parents integer,
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL
);

COMMENT ON TABLE public._mergestat_explore_repo_metadata IS 'repo metadata for explore experience';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.repo_id IS 'foreign key for public.repos.id';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_hash IS 'hash based reference to last commit';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_message IS 'message of the commit';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_author_name IS 'name of the author of the the modification';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_author_email IS 'email of the author of the modification';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_author_when IS 'timestamp of when the modifcation was authored';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_committer_name IS 'name of the author who committed the modification';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_committer_email IS 'email of the author who committed the modification';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_committer_when IS 'timestamp of when the commit was made';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata.last_commit_parents IS 'the number of parents of the commit';
COMMENT ON COLUMN public._mergestat_explore_repo_metadata._mergestat_synced_at IS 'timestamp when record was synced into the MergeStat database';

GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO readaccess;
GRANT ALL ON TABLE public._mergestat_explore_repo_metadata TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_readonly;
GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_user;
GRANT ALL ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_demo;
GRANT SELECT ON TABLE public._mergestat_explore_repo_metadata TO mergestat_role_queries_only;

ALTER TABLE ONLY public._mergestat_explore_repo_metadata
    ADD CONSTRAINT _mergestat_explore_repo_metadata_pkey PRIMARY KEY (repo_id);
ALTER TABLE ONLY public._mergestat_explore_repo_metadata
    ADD CONSTRAINT _mergestat_explore_repo_metadata_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;

