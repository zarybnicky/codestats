CREATE FUNCTION mergestat.add_service_auth_credential(provider_id uuid, credential_type text, username text, token text, secret text) RETURNS mergestat.service_auth_credentials
    LANGUAGE plpgsql
    AS $$
DECLARE _inserted_row mergestat.service_auth_credentials;
BEGIN
    INSERT INTO mergestat.service_auth_credentials (provider, type, username, credentials)
        VALUES (provider_id, credential_type, pgp_sym_encrypt(username, secret), pgp_sym_encrypt(token, secret)) RETURNING * INTO _inserted_row;

    RETURN _inserted_row;
END;
$$;


