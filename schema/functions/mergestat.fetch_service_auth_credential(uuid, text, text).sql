CREATE FUNCTION mergestat.fetch_service_auth_credential(provider_id uuid, credential_type text, secret text) RETURNS TABLE(id uuid, username text, token text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT c.id, pgp_sym_decrypt(c.username, secret), pgp_sym_decrypt(c.credentials, secret) AS token, c.created_at
        FROM mergestat.service_auth_credentials c
    WHERE c.provider = provider_id AND
        (credential_type IS NULL OR c.type = credential_type)
    ORDER BY is_default DESC, created_at DESC;
END;
$$;


