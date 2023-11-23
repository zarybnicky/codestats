CREATE TYPE sqlq.job_states AS ENUM (
    'pending',
    'running',
    'success',
    'errored',
    'cancelling',
    'cancelled'
);


