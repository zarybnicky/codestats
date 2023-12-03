CREATE TABLE public.git_commit_stats (
    repo_id uuid NOT NULL,
    commit_hash text NOT NULL,
    file_path text NOT NULL,
    additions integer NOT NULL,
    deletions integer NOT NULL,
    _mergestat_synced_at timestamp with time zone DEFAULT now() NOT NULL,
    old_file_mode text,
    new_file_mode text
);

COMMENT ON TABLE public.git_commit_stats IS 'git commit stats of a repo';
COMMENT ON COLUMN public.git_commit_stats.repo_id IS 'foreign key for public.repos.id';
COMMENT ON COLUMN public.git_commit_stats.commit_hash IS 'hash of the commit';
COMMENT ON COLUMN public.git_commit_stats.file_path IS 'path of the file the modification was made in';
COMMENT ON COLUMN public.git_commit_stats.additions IS 'the number of additions in this path of the commit';
COMMENT ON COLUMN public.git_commit_stats.deletions IS 'the number of deletions in this path of the commit';
COMMENT ON COLUMN public.git_commit_stats._mergestat_synced_at IS 'timestamp when record was synced into the MergeStat database';
COMMENT ON COLUMN public.git_commit_stats.old_file_mode IS 'old file mode derived from git mode. possible values (unknown, none, regular_file, symbolic_link, git_link)';
COMMENT ON COLUMN public.git_commit_stats.new_file_mode IS 'new file mode derived from git mode. possible values (unknown, none, regular_file, symbolic_link, git_link)';

GRANT SELECT ON TABLE public.git_commit_stats TO readaccess;
GRANT ALL ON TABLE public.git_commit_stats TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_commit_stats TO mergestat_role_readonly;
GRANT SELECT ON TABLE public.git_commit_stats TO mergestat_role_user;
GRANT ALL ON TABLE public.git_commit_stats TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.git_commit_stats TO mergestat_role_demo;
GRANT SELECT ON TABLE public.git_commit_stats TO mergestat_role_queries_only;

ALTER TABLE ONLY public.git_commit_stats
    ADD CONSTRAINT commit_stats_pkey PRIMARY KEY (repo_id, file_path, commit_hash);
ALTER TABLE ONLY public.git_commit_stats
    ADD CONSTRAINT git_commit_stats_repo_id_fkey FOREIGN KEY (repo_id) REFERENCES public.repos(id) ON UPDATE RESTRICT ON DELETE CASCADE;

CREATE INDEX idx_commit_stats_repo_id_fkey ON public.git_commit_stats USING btree (repo_id);
CREATE INDEX idx_git_commit_stats_repo_id_hash_file_path ON public.git_commit_stats USING btree (repo_id, commit_hash, file_path);