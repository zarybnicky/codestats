CREATE FUNCTION mergestat.add_sync_variable(repo_id uuid, key text, value text, secret text) RETURNS mergestat.sync_variables
    LANGUAGE plpgsql
    AS $$
DECLARE _inserted_row mergestat.sync_variables;
BEGIN
    INSERT INTO mergestat.sync_variables(repo_id, key, value)
        VALUES (repo_id, key, pgp_sym_encrypt(value, secret)) RETURNING * INTO _inserted_row;

    RETURN _inserted_row;
END;
$$;


