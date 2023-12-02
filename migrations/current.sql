ALTER TABLE ONLY public.git_commit_stats
    DROP CONSTRAINT commit_stats_pkey,
    ADD CONSTRAINT commit_stats_pkey PRIMARY KEY (repo_id, file_path, commit_hash);


alter table git_commit_stats alter column old_file_mode drop not null;
alter table git_commit_stats alter column old_file_mode set default null;
alter table git_commit_stats alter column new_file_mode drop not null;
alter table git_commit_stats alter column new_file_mode set default null;

alter table git_commits add column if not exists additions integer;
alter table git_commits add column if not exists deletions integer;

update git_commit_stats set old_file_mode=null where old_file_mode='unknown';
update git_commit_stats set new_file_mode=null where new_file_mode='unknown';

alter table repos add column if not exists is_duplicate boolean not null default false;

drop index if exists repos_is_duplicate;
create index repos_is_duplicate on repos (is_duplicate);
