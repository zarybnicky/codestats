CREATE FUNCTION public.getfilesolderthan(file_pattern text, older_than_days integer) RETURNS TABLE(repo text, file_path text, author_when timestamp with time zone, author_name text, author_email text, hash text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH top_author_when AS (
        SELECT DISTINCT ON (repos.repo, git_commit_stats.file_path) repos.repo, git_commit_stats.file_path, git_commits.author_when, git_commits.author_name, git_commits.author_email, git_commits.hash
        FROM git_commits 
        INNER JOIN repos ON git_commits.repo_id = repos.id 
        INNER JOIN git_commit_stats ON git_commit_stats.repo_id = git_commits.repo_id AND git_commit_stats.commit_hash = git_commits.hash and parents < 2
        WHERE git_commit_stats.file_path LIKE file_pattern
        ORDER BY repos.repo, git_commit_stats.file_path, git_commits.author_when DESC
    )
    SELECT * FROM top_author_when
    WHERE top_author_when.author_when < NOW() - (older_than_days || ' day')::INTERVAL
    ORDER BY top_author_when.author_when DESC;
END
$$;


