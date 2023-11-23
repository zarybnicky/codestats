CREATE FUNCTION sqlq.cancelling_job(job_id uuid) RETURNS sqlq.job_states
    LANGUAGE sql
    AS $$
  UPDATE sqlq.jobs 
        SET status = 'cancelling'
   WHERE id = job_id AND status = 'running' OR status ='pending'
        RETURNING status;
$$;


