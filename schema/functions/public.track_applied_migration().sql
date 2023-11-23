CREATE FUNCTION public.track_applied_migration() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE _current_version BIGINT;
BEGIN
    SELECT COALESCE(MAX(version),0) FROM public.schema_migrations_history INTO _current_version;
    IF new.dirty = false AND new.version > _current_version THEN
        INSERT INTO public.schema_migrations_history(version) VALUES (new.version);
    ELSE
        UPDATE public.schema_migrations SET version = (SELECT MAX(version) FROM public.schema_migrations_history), dirty = false;
    END IF;
    RETURN NEW;
END;
$$;


