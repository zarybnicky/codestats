CREATE FUNCTION sqlq.dequeue_job(queues text[], jobtypes text[]) RETURNS SETOF sqlq.jobs
    LANGUAGE sql
    AS $_$
WITH queues AS (
    SELECT name, concurrency, priority FROM sqlq.queues WHERE (ARRAY_LENGTH($1, 1) IS NULL OR name = ANY($1))
), running (name, count) AS (
    SELECT queue, COUNT(*) FROM sqlq.jobs, queues
    WHERE jobs.queue = queues.name AND status = 'running'
    GROUP BY queue
), queue_with_capacity AS (
    SELECT queues.name, queues.priority FROM queues LEFT OUTER JOIN running USING(name)
    WHERE (concurrency IS NULL OR (concurrency - COALESCE(running.count, 0) > 0))
), dequeued(id) AS (
    SELECT job.id FROM sqlq.jobs job, queue_with_capacity q
    WHERE job.status = 'pending'
      AND (job.last_queued_at+make_interval(secs => job.run_after/1e9)) <= NOW() -- value in run_after is stored as nanoseconds
      AND job.queue = q.name
      AND (ARRAY_LENGTH($2, 1) IS NULL OR job.typename = ANY($2))
    ORDER BY q.priority ASC, job.priority ASC, job.created_at ASC
    LIMIT 1
)
UPDATE sqlq.jobs
SET status = 'running', started_at = NOW(), last_keepalive = NOW(), attempt = attempt + 1
FROM dequeued dq
WHERE jobs.id = dq.id
RETURNING jobs.*
$_$;


