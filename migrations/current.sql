alter table git_files add column if not exists size integer;
alter table git_files add column if not exists ext text;

create index if not exists git_commits_author_name_gin on git_commits using gin (author_name gin_trgm_ops);
create index if not exists git_commits_author_email_gin on git_commits using gin (author_email gin_trgm_ops);
create index if not exists repos_repo_gin on repos using gin (repo gin_trgm_ops);
