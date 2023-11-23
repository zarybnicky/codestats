CREATE FUNCTION mergestat.simple_repo_sync_queue_cleanup(days_to_retain_param integer DEFAULT 30) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare _rows_deleted INTEGER;
begin
    DELETE FROM mergestat.repo_sync_queue WHERE created_at < CURRENT_DATE - days_to_retain_param;
    GET DIAGNOSTICS _rows_deleted = ROW_COUNT;
    
    RETURN _rows_deleted;
end;
$$;


