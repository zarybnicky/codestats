CREATE TABLE IF NOT EXISTS providers (
    name text NOT NULL,
    root text,
    origin text,
    PRIMARY KEY (name)
);

CREATE TABLE IF NOT EXISTS repos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    repo text NOT NULL,
    provider text NOT NULL,
    is_duplicate boolean not null default false,
    PRIMARY KEY (id),
    FOREIGN KEY (provider) REFERENCES providers (name)
);

CREATE TABLE IF NOT EXISTS git_commit_stats (
    repo_id uuid NOT NULL,
    commit_hash text NOT NULL,
    file_path text NOT NULL,
    additions integer NOT NULL,
    deletions integer NOT NULL,
    PRIMARY KEY (repo_id, commit_hash, file_path),
    FOREIGN KEY (repo_id) REFERENCES repos(id)
);

CREATE TABLE IF NOT EXISTS git_commits (
    repo_id uuid NOT NULL,
    hash text NOT NULL,
    message text,
    author_name text,
    author_email text,
    author_when timestamp_ns NOT NULL,
    committer_name text,
    committer_email text,
    committer_when timestamp_ns NOT NULL,
    parents integer NOT NULL,
    additions integer,
    deletions integer,
    PRIMARY KEY (repo_id, hash),
    FOREIGN KEY (repo_id) REFERENCES repos(id)
);

CREATE TABLE IF NOT EXISTS git_files (
    repo_id uuid NOT NULL,
    path text NOT NULL,
    executable boolean NOT NULL,
    size int,
    ext text,
    PRIMARY KEY (repo_id, path),
    FOREIGN KEY (repo_id) REFERENCES repos(id)
);
