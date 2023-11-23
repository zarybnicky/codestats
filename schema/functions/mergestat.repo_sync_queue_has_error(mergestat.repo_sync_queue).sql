CREATE FUNCTION mergestat.repo_sync_queue_has_error(job mergestat.repo_sync_queue) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT EXISTS (SELECT * FROM mergestat.repo_sync_logs WHERE repo_sync_queue_id = job.id AND log_type = 'ERROR')
$$;


