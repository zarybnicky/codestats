CREATE FUNCTION mergestat.sync_now(container_sync_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE 
    queue_name TEXT;
    queue_concurrency INTEGER;
    queue_priority INTEGER;
    job_id UUID;
    is_sync_already_running BOOLEAN;
BEGIN
    --Check if a sync run is already queued
    WITH sync_running(id, queue, job, status) AS (
        SELECT DISTINCT ON (syncs.id) syncs.id, (image.queue || '-' || repo.provider) AS queue, exec.job_id, job.status,
            CASE WHEN image.queue = 'github' THEN 1 ELSE 0 END AS concurrency
            FROM mergestat.container_syncs syncs
                INNER JOIN mergestat.container_images image ON image.id = syncs.image_id
                INNER JOIN public.repos repo ON repo.id = syncs.repo_id
                LEFT OUTER JOIN mergestat.container_sync_executions exec ON exec.sync_id = syncs.id
                LEFT OUTER JOIN sqlq.jobs job ON job.id = exec.job_id
        WHERE syncs.id = container_sync_id
        ORDER BY syncs.id, exec.created_at DESC
    )
    SELECT CASE WHEN (SELECT COUNT(*) FROM sync_running WHERE status IN ('pending','running')) > 0 THEN TRUE ELSE FALSE END
    INTO is_sync_already_running;
    
    
    IF is_sync_already_running = FALSE
    THEN    
        --Get the queue name
        SELECT DISTINCT (ci.queue || '-' || r.provider)
        INTO queue_name
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_images ci ON ci.id = cs.image_id
        INNER JOIN public.repos r ON r.id = cs.repo_id
        WHERE cs.id = container_sync_id;
        
        --Get the queue concurrency
        SELECT DISTINCT CASE WHEN ci.queue = 'github' THEN 1 ELSE NULL END
        INTO queue_concurrency
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_images ci ON ci.id = cs.image_id
        INNER JOIN public.repos r ON r.id = cs.repo_id
        WHERE cs.id = container_sync_id;

        --Get the queue priority
        SELECT DISTINCT CASE WHEN ci.queue = 'github' THEN 1 ELSE 2 END
        INTO queue_priority
        FROM mergestat.container_syncs cs
        INNER JOIN mergestat.container_images ci ON ci.id = cs.image_id
        INNER JOIN public.repos r ON r.id = cs.repo_id
        WHERE cs.id = container_sync_id;
        
        --Add the queue if missing
        INSERT INTO sqlq.queues (name, concurrency, priority) VALUES (queue_name, queue_concurrency, queue_priority) ON CONFLICT (name) DO UPDATE SET concurrency = excluded.concurrency, priority = excluded.priority;
        
        --Add the job
        INSERT INTO sqlq.jobs (queue, typename, parameters, priority) VALUES (queue_name, 'container/sync', jsonb_build_object('ID', container_sync_id), 0) RETURNING id INTO job_id;
        
        --Add the container sync execution
        INSERT INTO mergestat.container_sync_executions (sync_id, job_id) VALUES (container_sync_id, job_id);
    END IF;
    
    RETURN TRUE;
    
END; $$;


