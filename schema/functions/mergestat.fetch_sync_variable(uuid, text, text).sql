CREATE FUNCTION mergestat.fetch_sync_variable(uuid, text, text) RETURNS TABLE(repo_id uuid, key text, value text)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY SELECT var.repo_id, var.key::text, pgp_sym_decrypt(var.value, $3)
        FROM mergestat.sync_variables var
    WHERE var.repo_id = $1 AND var.key = $2;
END;
$_$;


