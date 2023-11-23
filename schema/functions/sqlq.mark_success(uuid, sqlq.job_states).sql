CREATE FUNCTION sqlq.mark_success(id uuid, expectedstate sqlq.job_states) RETURNS SETOF sqlq.jobs
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY UPDATE sqlq.jobs SET status = 'success', completed_at = NOW()
        WHERE jobs.id = $1 AND status = $2
    RETURNING *;
END;
$_$;


