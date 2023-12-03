--! Previous: sha1:a418347695c4ac983df031bff794b28b0062741a
--! Hash: sha1:ffa7ec98fb6f927f814333475437db590e4dcbbc

ALTER TABLE ONLY public.git_commit_stats
    DROP CONSTRAINT commit_stats_pkey,
    ADD CONSTRAINT commit_stats_pkey PRIMARY KEY (repo_id, file_path, commit_hash);

alter table public.git_commit_stats alter column old_file_mode drop not null;
alter table public.git_commit_stats alter column old_file_mode set default null;
alter table public.git_commit_stats alter column new_file_mode drop not null;
alter table public.git_commit_stats alter column new_file_mode set default null;

alter table public.git_commits add column if not exists additions integer;
alter table public.git_commits add column if not exists deletions integer;

update public.git_commit_stats set old_file_mode=null where old_file_mode='unknown';
update public.git_commit_stats set new_file_mode=null where new_file_mode='unknown';

alter table public.repos add column if not exists is_duplicate boolean not null default false;

drop index if exists repos_is_duplicate;
create index repos_is_duplicate on public.repos (is_duplicate);
