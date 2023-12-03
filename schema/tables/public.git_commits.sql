CREATE TABLE public.git_commits (
    repo_id uuid NOT NULL,
    hash text NOT NULL,
    message text,
    author_name text,
    author_email text,
    author_when timestamp with time zone NOT NULL,
    committer_name text,
    committer_email text,
    committer_when timestamp with time zone NOT NULL,
    parents integer NOT NULL,
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL,
    additions integer,
    deletions integer
);

COMMENT ON TABLE public.git_commits IS 'git commit history of a repo';
COMMENT ON COLUMN public.git_commits.repo_id IS 'foreign key for public.repos.id';
COMMENT ON COLUMN public.git_commits.hash IS 'hash of the commit';
COMMENT ON COLUMN public.git_commits.message IS 'message of the commit';
COMMENT ON COLUMN public.git_commits.author_name IS 'name of the author of the the modification';
COMMENT ON COLUMN public.git_commits.author_email IS 'email of the author of the modification';
COMMENT ON COLUMN public.git_commits.author_when IS 'timestamp of when the modifcation was authored';
COMMENT ON COLUMN public.git_commits.committer_name IS 'name of the author who committed the modification';
COMMENT ON COLUMN public.git_commits.committer_email IS 'email of the author who committed the modification';
COMMENT ON COLUMN public.git_commits.committer_when IS 'timestamp of when the commit was made';
COMMENT ON COLUMN public.git_commits.parents IS 'the number of parents of the commit';
COMMENT ON COLUMN public.git_commits._mergestat_synced_at IS 'timestamp when record was synced into the MergeStat database';

GRANT SELECT ON TABLE public.git_commits TO readaccess;
GRANT ALL ON TABLE public.git_commits TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_commits TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.git_commits TO mergestat_role_user;
GRANT ALL ON TABLE public.git_commits TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_commits TO mergestat_role_demo;
GRANT SELECT ON TABLE public.git_commits TO mergestat_role_queries_only;

ALTER TABLE ONLY public.git_commits
    ADD CONSTRAINT commits_pkey PRIMARY KEY (repo_id, hash);
ALTER TABLE ONLY public.git_commits
    ADD CONSTRAINT git_commits_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;

CREATE INDEX commits_author_when_idx ON public.git_commits USING btree (repo_id, author_when);
CREATE INDEX idx_commits_repo_id_fkey ON public.git_commits USING btree (repo_id);
CREATE INDEX idx_git_commits_repo_id_hash_parents ON public.git_commits USING btree (repo_id, hash, parents);