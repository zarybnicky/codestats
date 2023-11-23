CREATE FUNCTION mergestat.user_mgmt_set_user_role(username name, role text) RETURNS smallint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
BEGIN


