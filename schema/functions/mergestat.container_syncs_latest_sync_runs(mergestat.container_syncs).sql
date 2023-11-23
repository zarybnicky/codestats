CREATE FUNCTION mergestat.container_syncs_latest_sync_runs(container_syncs mergestat.container_syncs) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   response JSONB;
BEGIN
    WITH last_completed_syncs AS(
        SELECT
            cs.id AS container_sync_id,
            ci.name AS container_image_name,
            j.id AS job_id,
            j.status,
            j.created_at,
            j.started_at,
            j.completed_at,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'warn') warning_count,
            (SELECT COUNT(1) FROM sqlq.job_logs WHERE sqlq.job_logs.job = j.id AND level = 'error') error_count
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_sync_executions cse ON cs.id = cse.sync_id
        INNER JOIN mergestat.container_images ci ON cs.image_id = ci.id
        INNER JOIN sqlq.jobs j ON cse.job_id = j.id
        WHERE cs.id = container_syncs.id
        ORDER BY cs.id, j.created_at DESC
        LIMIT 15
    )
    SELECT 
        JSONB_OBJECT_AGG(job_id, TO_JSONB(t) - 'job_id')
    INTO response
    FROM (
        SELECT job_id, created_at, started_at, completed_at, ((EXTRACT('epoch' FROM completed_at)-EXTRACT('epoch' FROM started_at))*1000)::INTEGER AS duration_ms, status FROM last_completed_syncs    
    )t;

    RETURN response;
END; $$;


