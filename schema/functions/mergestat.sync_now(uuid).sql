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


