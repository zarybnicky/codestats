CREATE FUNCTION mergestat.set_sync_job_status(new_status text, repo_sync_queue_id bigint) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE _repo_sync_id UUID;
BEGIN
    IF new_status = 'DONE' THEN
            WITH update_queue AS (
                UPDATE mergestat.repo_sync_queue SET "status" = new_status WHERE mergestat.repo_sync_queue.id = repo_sync_queue_id
                RETURNING *
            )
            UPDATE mergestat.repo_syncs set last_completed_repo_sync_queue_id = repo_sync_queue_id
            FROM update_queue
            WHERE mergestat.repo_syncs.id = update_queue.repo_sync_id
            RETURNING mergestat.repo_syncs.id INTO _repo_sync_id;
    ELSE    
            UPDATE mergestat.repo_sync_queue SET "status" = new_status WHERE mergestat.repo_sync_queue.id = repo_sync_queue_id
            RETURNING repo_sync_id INTO _repo_sync_id;
    END IF;
    
    RETURN _repo_sync_id;    
END;
$$;


