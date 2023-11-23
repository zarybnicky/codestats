CREATE FUNCTION mergestat.get_repos_syncs_by_status(repo_id_param uuid, status_param text) RETURNS jsonb
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
        WHERE cs.repo_id = repo_id_param AND j.status NOT IN ('pending','running')
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
        LEFT JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        LEFT JOIN mergestat.container_images ci ON cs.image_id = ci.id
        LEFT JOIN sqlq.jobs j ON cse.job_id = j.id
        WHERE cs.repo_id = repo_id_param AND j.status IN ('pending','running')
        ORDER BY cs.id, j.created_at DESC
    ),
    selected_sync AS(
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'running' AS selection FROM current_syncs WHERE status = 'running'
        UNION
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'pending' AS selection FROM current_syncs WHERE status = 'pending'
        UNION
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'success' AS selection FROM last_completed_syncs WHERE status = 'success'
        UNION
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'warning' AS selection FROM last_completed_syncs WHERE warning_count > 0
        UNION
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at, 'errored' AS selection FROM last_completed_syncs WHERE status = 'errored' OR error_count > 0
    )
    SELECT 
        JSONB_OBJECT_AGG(job_id, TO_JSONB(t) - 'job_id')
    INTO response
    FROM (
        SELECT container_sync_id, job_id, container_image_name, sync_last_completed_at FROM selected_sync WHERE selection = status_param
    )t;

    RETURN response;
END; $$;


