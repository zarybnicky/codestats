CREATE FUNCTION public.explore_ui(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   RESPONSE JSONB;
   RESPONSE_TYPE TEXT;
   FILE_PATH_PATTERN_PARAM TEXT;
   FILE_CONTENTS_PATTERN_PARAM TEXT;
   AUTHOR_NAME_PATTERN_PARAM TEXT;
   DAYS_SINCE_REPO_MODIFIED_LAST_PARAM INTEGER;
   DAYS_SINCE_REPO_NOT_MODIFIED_LAST_PARAM INTEGER;
   DAYS_SINCE_FILE_MODIFIED_LAST_PARAM INTEGER;
   DAYS_SINCE_FILE_NOT_MODIFIED_LAST_PARAM INTEGER;
   DAYS_SINCE_AUTHORED_LAST_PARAM INTEGER;
   DAYS_SINCE_NOT_AUTHORED_LAST_PARAM INTEGER;
   DAYS_SINCE_COMMITTED_LAST_PARAM INTEGER;
   DAYS_SINCE_NOT_COMMITTED_LAST_PARAM INTEGER;
   REPO_PATTERN_PARAM TEXT;
BEGIN
    SELECT COALESCE(params->>'RESPONSE_TYPE', 'DEFAULT') INTO RESPONSE_TYPE;
    SELECT params->>'file_path_pattern' INTO FILE_PATH_PATTERN_PARAM;
    SELECT params->>'file_contents_pattern' INTO FILE_CONTENTS_PATTERN_PARAM;
    SELECT params->>'author_name_pattern' INTO AUTHOR_NAME_PATTERN_PARAM;
    SELECT params->>'days_since_repo_modified_last' INTO DAYS_SINCE_REPO_MODIFIED_LAST_PARAM;
    SELECT params->>'days_since_repo_not_modified_last' INTO DAYS_SINCE_REPO_NOT_MODIFIED_LAST_PARAM;
    SELECT params->>'days_since_file_modified_last' INTO DAYS_SINCE_FILE_MODIFIED_LAST_PARAM;
    SELECT params->>'days_since_file_not_modified_last' INTO DAYS_SINCE_FILE_NOT_MODIFIED_LAST_PARAM;
    SELECT params->>'days_since_authored_last' INTO DAYS_SINCE_AUTHORED_LAST_PARAM;
    SELECT params->>'days_since_not_authored_last' INTO DAYS_SINCE_NOT_AUTHORED_LAST_PARAM;
    SELECT params->>'days_since_committed_last' INTO DAYS_SINCE_COMMITTED_LAST_PARAM;
    SELECT params->>'days_since_not_committed_last' INTO DAYS_SINCE_NOT_COMMITTED_LAST_PARAM;
    SELECT params->>'repo_pattern' INTO REPO_PATTERN_PARAM;

    WITH base_query AS (
        SELECT 
            repos.repo,
            git_files.path AS file_path,
            git_commits.author_when,
            git_commits.author_name,
            git_commits.committer_when,
            git_commits.committer_name,
            git_commits.hash,
            _mergestat_explore_repo_metadata.last_commit_committer_when AS repo_last_modified,
            _mergestat_explore_file_metadata.last_commit_committer_when AS file_last_modified
        FROM git_commits 
        INNER JOIN repos ON git_commits.repo_id = repos.id 
        INNER JOIN git_commit_stats ON git_commit_stats.repo_id = git_commits.repo_id AND git_commit_stats.commit_hash = git_commits.hash and parents < 2
        INNER JOIN git_files ON git_commit_stats.repo_id = git_files.repo_id AND git_commit_stats.file_path = git_files.path
        INNER JOIN _mergestat_explore_repo_metadata ON git_commits.repo_id = _mergestat_explore_repo_metadata.repo_id
        INNER JOIN _mergestat_explore_file_metadata ON git_commits.repo_id = _mergestat_explore_file_metadata.repo_id AND _mergestat_explore_file_metadata.path = git_files.path
        WHERE
            (FILE_PATH_PATTERN_PARAM IS NULL OR git_files.path LIKE FILE_PATH_PATTERN_PARAM)
            AND
            (FILE_CONTENTS_PATTERN_PARAM IS NULL OR git_files.contents LIKE FILE_CONTENTS_PATTERN_PARAM)
            AND
            (AUTHOR_NAME_PATTERN_PARAM IS NULL OR git_commits.author_name LIKE AUTHOR_NAME_PATTERN_PARAM)
            AND
            (REPO_PATTERN_PARAM IS NULL OR repos.repo LIKE REPO_PATTERN_PARAM)
            AND
            (DAYS_SINCE_REPO_NOT_MODIFIED_LAST_PARAM IS NULL OR _mergestat_explore_repo_metadata.last_commit_committer_when < NOW() - (DAYS_SINCE_REPO_NOT_MODIFIED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_FILE_NOT_MODIFIED_LAST_PARAM IS NULL OR _mergestat_explore_file_metadata.last_commit_committer_when < NOW() - (DAYS_SINCE_FILE_NOT_MODIFIED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_NOT_AUTHORED_LAST_PARAM IS NULL OR git_commits.author_when < NOW() - (DAYS_SINCE_NOT_AUTHORED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_NOT_COMMITTED_LAST_PARAM IS NULL OR git_commits.committer_when < NOW() - (DAYS_SINCE_NOT_COMMITTED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_REPO_MODIFIED_LAST_PARAM IS NULL OR _mergestat_explore_repo_metadata.last_commit_committer_when >= NOW() - (DAYS_SINCE_REPO_MODIFIED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_FILE_MODIFIED_LAST_PARAM IS NULL OR _mergestat_explore_file_metadata.last_commit_committer_when >= NOW() - (DAYS_SINCE_FILE_MODIFIED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_AUTHORED_LAST_PARAM IS NULL OR git_commits.author_when >= NOW() - (DAYS_SINCE_AUTHORED_LAST_PARAM || ' day')::INTERVAL)
            AND
            (DAYS_SINCE_COMMITTED_LAST_PARAM IS NULL OR git_commits.committer_when >= NOW() - (DAYS_SINCE_COMMITTED_LAST_PARAM || ' day')::INTERVAL)
    )
    SELECT
        CASE
        WHEN RESPONSE_TYPE = 'FILES'
            THEN (
                SELECT jsonb_agg(b) AS agg
                FROM (
                    SELECT DISTINCT
                        repo,
                        file_path,
                        file_last_modified
                    FROM base_query
                    ORDER BY 3 DESC
                    LIMIT 1001
                )b
            )
        WHEN RESPONSE_TYPE = 'REPOS'
            THEN (
                SELECT jsonb_agg(b) AS agg
                FROM (
                    SELECT
                        repo,
                        repo_last_modified,
                        COUNT(DISTINCT file_path) AS file_count 
                    FROM base_query
                    GROUP BY 1, 2
                    ORDER BY 3 DESC
                    LIMIT 1001
                )b
            )
        WHEN RESPONSE_TYPE = 'AUTHORS'
            THEN (
                SELECT jsonb_agg(b) AS agg
                FROM (
                    SELECT 
                        author_name,
                        COUNT(DISTINCT hash) AS commits_count 
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 2 DESC
                    LIMIT 1001
                )b
            )
        ELSE (
            jsonb_build_object('top_10_repos', (SELECT JSON_AGG(TO_JSONB(top_10_repos)) FROM (
                SELECT
                    base_query.repo,
                    providers.vendor,
                    providers.settings->>'url' AS vendor_url,
                    COUNT(DISTINCT file_path) AS file_count 
                FROM base_query
                INNER JOIN repos ON base_query.repo = repos.repo
                INNER JOIN mergestat.providers ON repos.provider = providers.id
                GROUP BY 1, 2, 3
                ORDER BY 4 DESC
                LIMIT 10
            )top_10_repos)) ||
            jsonb_build_object('top_10_authors', (SELECT JSON_AGG(TO_JSONB(top_10_authors)) FROM (
                SELECT 
                    author_name,
                    COUNT(DISTINCT hash) AS commits_count 
                FROM base_query
                GROUP BY 1
                ORDER BY 2 DESC
                LIMIT 10
            )top_10_authors)) ||
            jsonb_build_object('repo_last_modified', 
                jsonb_build_object('month', (SELECT JSON_AGG(TO_JSONB(repo_last_modified_by_year_month)) FROM (
                    SELECT
                        TO_CHAR(repo_last_modified, 'YYYY-MM') AS year_month,
                        COUNT(DISTINCT repo) as count
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 1
                )repo_last_modified_by_year_month)) || 
                jsonb_build_object('year', (SELECT JSON_AGG(TO_JSONB(repo_last_modified_by_year)) FROM (
                    SELECT
                        TO_CHAR(repo_last_modified, 'YYYY') AS year,
                        COUNT(DISTINCT repo) as count
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 1
                )repo_last_modified_by_year))) ||
            jsonb_build_object('file_last_modified', 
                jsonb_build_object('month', (SELECT JSON_AGG(TO_JSONB(file_last_modified_by_year_month)) FROM (
                    SELECT
                        TO_CHAR(file_last_modified, 'YYYY-MM') AS year_month,
                        COUNT(DISTINCT repo || file_path) as count
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 1
                )file_last_modified_by_year_month)) || 
                jsonb_build_object('year', (SELECT JSON_AGG(TO_JSONB(file_last_modified_by_year)) FROM (
                    SELECT
                        TO_CHAR(file_last_modified, 'YYYY') AS year,
                        COUNT(DISTINCT repo || file_path) as count
                    FROM base_query
                    GROUP BY 1
                    ORDER BY 1
                )file_last_modified_by_year))) ||
            jsonb_build_object('repos', (SELECT COUNT(DISTINCT repo) AS count FROM base_query)) ||
            jsonb_build_object('files', (SELECT COUNT(DISTINCT repo || file_path) AS count FROM base_query)) ||
            jsonb_build_object('authors', (SELECT COUNT(DISTINCT author_name) AS count FROM base_query))
        )
        END
    INTO RESPONSE;
    
    RETURN RESPONSE;
END; $$;


