    old_file_mode text,
    new_file_mode text
    ADD CONSTRAINT commit_stats_pkey PRIMARY KEY (repo_id, file_path, commit_hash);