CREATE FUNCTION public.repos_stats(repos public.repos) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   response JSONB;
BEGIN
    WITH last_completed_syncs AS(
        SELECT DISTINCT ON (cs.id) 
            cs.id AS container_sync_id,
            ci.name AS container_image_name,
            j.id AS job_id,
            j.status,
            j.completed_at AS sync_last_completed_at,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'warn') warning_count,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'error') error_count
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        INNER JOIN mergestat.container_images ci ON cs.image_id = ci.id
        INNER JOIN sqlq.jobs j ON cse.job_id = j.id
        WHERE cs.repo_id = repos.id AND j.status NOT IN ('pending','running')
        ORDER BY cs.id, j.created_at DESC
    ),
    current_syncs AS(
        SELECT DISTINCT ON (cs.id)
            cs.id AS container_sync_id,
            ci.name AS container_image_name,
            j.id AS job_id,
            j.status,
            j.completed_at AS sync_last_completed_at
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        INNER JOIN mergestat.container_images ci ON cs.image_id = ci.id
        INNER JOIN sqlq.jobs j ON cse.job_id = j.id AND j.status IN ('pending','running')
        WHERE cs.repo_id = repos.id
        ORDER BY cs.id, j.created_at DESC
    ),
    scheduled_syncs AS(
        SELECT COUNT(DISTINCT css.id) as sync_count
        FROM mergestat.container_sync_schedules css 
        INNER JOIN mergestat.container_syncs cs ON css.sync_id = cs.id
        WHERE cs.repo_id = repos.id
    )
    SELECT 
        (ROW_TO_JSON(t)::JSONB)
    INTO response
    FROM (
        SELECT
            (SELECT sync_count from scheduled_syncs) AS sync_count,
            (SELECT MAX(sync_last_completed_at) FROM last_completed_syncs) AS last_sync_time,
            (SELECT COUNT(1) FROM current_syncs WHERE status = 'running') AS running,
            (SELECT COUNT(1) FROM current_syncs WHERE status = 'pending') AS pending,
            (SELECT COUNT(1) FROM last_completed_syncs WHERE status = 'errored' OR error_count > 0) AS error,
            (SELECT COUNT(1) FROM last_completed_syncs WHERE status = 'success' AND error_count = 0 AND warning_count = 0) AS success,
            (SELECT COUNT(1) FROM last_completed_syncs WHERE warning_count > 0 AND status = 'success' AND error_count = 0) AS warning
    )t;

    RETURN response;
END; $$;


