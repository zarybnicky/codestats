CREATE VIEW mergestat.latest_repo_syncs AS
 SELECT DISTINCT ON (repo_sync_queue.repo_sync_id) repo_sync_queue.id,
    repo_sync_queue.created_at,
    repo_sync_queue.repo_sync_id,
    repo_sync_queue.status,
    repo_sync_queue.started_at,
    repo_sync_queue.done_at
   FROM mergestat.repo_sync_queue
  WHERE (repo_sync_queue.status = 'DONE'::text)
  ORDER BY repo_sync_queue.repo_sync_id, repo_sync_queue.created_at DESC;

GRANT ALL ON TABLE mergestat.latest_repo_syncs TO mergestat_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.latest_repo_syncs TO readaccess;
GRANT SELECT ON TABLE mergestat.latest_repo_syncs TO mergestat_role_readonly;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mergestat.latest_repo_syncs TO mergestat_role_user;
GRANT ALL ON TABLE mergestat.latest_repo_syncs TO mergestat_role_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE mergestat.latest_repo_syncs TO mergestat_role_demo;
GRANT SELECT ON TABLE mergestat.latest_repo_syncs TO mergestat_role_queries_only;

