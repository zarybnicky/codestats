from typing import List, Optional

from sqlalchemy import ARRAY, BigInteger, Boolean, CheckConstraint, Column, DateTime, ForeignKeyConstraint, Index, Integer, LargeBinary, PrimaryKeyConstraint, String, Table, Text, UniqueConstraint, Uuid, text
from sqlalchemy.dialects.postgresql import CITEXT, ENUM, INTERVAL, JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
import datetime
import uuid

class Base(DeclarativeBase):
    pass


class ContainerImageTypes(Base):
    __tablename__ = 'container_image_types'
    __table_args__ = (
        PrimaryKeyConstraint('name', name='container_image_types_pkey'),
        {'schema': 'mergestat'}
    )

    name: Mapped[str] = mapped_column(Text, primary_key=True)
    display_name: Mapped[str] = mapped_column(Text)
    description: Mapped[Optional[str]] = mapped_column(Text)

    container_images: Mapped[List['ContainerImages']] = relationship('ContainerImages', back_populates='container_image_types')


t_latest_repo_syncs = Table(
    'latest_repo_syncs', Base.metadata,
    Column('id', BigInteger),
    Column('created_at', DateTime(True)),
    Column('repo_sync_id', Uuid),
    Column('status', Text),
    Column('started_at', DateTime(True)),
    Column('done_at', DateTime(True)),
    schema='mergestat'
)


class QueryHistory(Base):
    __tablename__ = 'query_history'
    __table_args__ = (
        PrimaryKeyConstraint('id', name='query_history_pkey'),
        {'schema': 'mergestat'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'))
    run_by: Mapped[str] = mapped_column(Text)
    query: Mapped[str] = mapped_column(Text)
    run_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True), server_default=text('now()'))


class RepoImportTypes(Base):
    __tablename__ = 'repo_import_types'
    __table_args__ = (
        PrimaryKeyConstraint('type', name='repo_import_types_pkey'),
        {'comment': 'Types of repo imports', 'schema': 'mergestat'}
    )

    type: Mapped[str] = mapped_column(Text, primary_key=True)
    description: Mapped[str] = mapped_column(Text)


class RepoSyncLogTypes(Base):
    __tablename__ = 'repo_sync_log_types'
    __table_args__ = (
        PrimaryKeyConstraint('type', name='repo_sync_log_types_pkey'),
        {'schema': 'mergestat'}
    )

    type: Mapped[str] = mapped_column(Text, primary_key=True)
    description: Mapped[Optional[str]] = mapped_column(Text)

    repo_sync_logs: Mapped[List['RepoSyncLogs']] = relationship('RepoSyncLogs', back_populates='repo_sync_log_types')


class RepoSyncQueue(Base):
    __tablename__ = 'repo_sync_queue'
    __table_args__ = (
        ForeignKeyConstraint(['repo_sync_id'], ['mergestat.repo_syncs.id'], ondelete='CASCADE', onupdate='RESTRICT', name='repo_sync_queue_repo_sync_id_fkey'),
        ForeignKeyConstraint(['status'], ['mergestat.repo_sync_queue_status_types.type'], ondelete='RESTRICT', onupdate='RESTRICT', name='repo_sync_queue_status_fkey'),
        ForeignKeyConstraint(['type_group'], ['mergestat.repo_sync_type_groups.group'], ondelete='RESTRICT', onupdate='RESTRICT', name='repo_sync_queue_type_group_fkey'),
        PrimaryKeyConstraint('id', name='repo_sync_queue_pkey'),
        Index('idx_repo_sync_queue_created_at', 'created_at'),
        Index('idx_repo_sync_queue_done_at', 'done_at'),
        Index('idx_repo_sync_queue_repo_sync_id_fkey', 'repo_sync_id'),
        Index('idx_repo_sync_queue_status', 'status'),
        {'schema': 'mergestat'}
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    repo_sync_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    status: Mapped[str] = mapped_column(Text)
    priority: Mapped[int] = mapped_column(Integer, server_default=text('0'))
    type_group: Mapped[str] = mapped_column(Text, server_default=text("'DEFAULT'::text"))
    started_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))
    done_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))
    last_keep_alive: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))

    repo_sync: Mapped['RepoSyncs'] = relationship('RepoSyncs', foreign_keys=[repo_sync_id], back_populates='repo_sync_queue')
    repo_sync_queue_status_types: Mapped['RepoSyncQueueStatusTypes'] = relationship('RepoSyncQueueStatusTypes', back_populates='repo_sync_queue')
    repo_sync_type_groups: Mapped['RepoSyncTypeGroups'] = relationship('RepoSyncTypeGroups', back_populates='repo_sync_queue')
    repo_syncs: Mapped[List['RepoSyncs']] = relationship('RepoSyncs', foreign_keys='[RepoSyncs.last_completed_repo_sync_queue_id]', back_populates='last_completed_repo_sync_queue')
    repo_sync_logs: Mapped[List['RepoSyncLogs']] = relationship('RepoSyncLogs', back_populates='repo_sync_queue')


class RepoSyncQueueStatusTypes(Base):
    __tablename__ = 'repo_sync_queue_status_types'
    __table_args__ = (
        PrimaryKeyConstraint('type', name='repo_sync_queue_status_types_pkey'),
        {'schema': 'mergestat'}
    )

    type: Mapped[str] = mapped_column(Text, primary_key=True)
    description: Mapped[Optional[str]] = mapped_column(Text)

    repo_sync_queue: Mapped[List['RepoSyncQueue']] = relationship('RepoSyncQueue', back_populates='repo_sync_queue_status_types')


class RepoSyncTypeGroups(Base):
    __tablename__ = 'repo_sync_type_groups'
    __table_args__ = (
        PrimaryKeyConstraint('group', name='repo_sync_type_groups_group_pkey'),
        {'schema': 'mergestat'}
    )

    group: Mapped[str] = mapped_column(Text, primary_key=True)
    concurrent_syncs: Mapped[Optional[int]] = mapped_column(Integer)

    repo_sync_queue: Mapped[List['RepoSyncQueue']] = relationship('RepoSyncQueue', back_populates='repo_sync_type_groups')
    repo_sync_types: Mapped[List['RepoSyncTypes']] = relationship('RepoSyncTypes', back_populates='repo_sync_type_groups')


class RepoSyncTypeLabels(Base):
    __tablename__ = 'repo_sync_type_labels'
    __table_args__ = (
        CheckConstraint("color IS NULL OR color ~* '^#[a-f0-9]{2}[a-f0-9]{2}[a-f0-9]{2}$'::text", name='repo_sync_type_labels_color_check'),
        PrimaryKeyConstraint('label', name='repo_sync_type_labels_pkey'),
        {'comment': '@name labels', 'schema': 'mergestat'}
    )

    label: Mapped[str] = mapped_column(Text, primary_key=True)
    color: Mapped[str] = mapped_column(Text, server_default=text("'#dddddd'::text"))
    description: Mapped[Optional[str]] = mapped_column(Text)

    repo_sync_types: Mapped[List['RepoSyncTypes']] = relationship('RepoSyncTypes', secondary='mergestat.repo_sync_type_label_associations', back_populates='repo_sync_type_labels')


class RepoSyncs(Base):
    __tablename__ = 'repo_syncs'
    __table_args__ = (
        ForeignKeyConstraint(['last_completed_repo_sync_queue_id'], ['mergestat.repo_sync_queue.id'], ondelete='SET NULL', name='last_completed_repo_sync_queue_id_fk'),
        ForeignKeyConstraint(['repo_id'], ['repos.id'], ondelete='CASCADE', onupdate='RESTRICT', name='repo_sync_settings_repo_id_fkey'),
        ForeignKeyConstraint(['sync_type'], ['mergestat.repo_sync_types.type'], ondelete='RESTRICT', onupdate='RESTRICT', name='repo_syncs_sync_type_fkey'),
        PrimaryKeyConstraint('id', name='repo_sync_settings_pkey'),
        UniqueConstraint('repo_id', 'sync_type', name='repo_syncs_repo_id_sync_type_key'),
        Index('idx_repo_sync_settings_repo_id_fkey', 'repo_id'),
        {'schema': 'mergestat'}
    )

    repo_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    sync_type: Mapped[str] = mapped_column(Text)
    settings: Mapped[dict] = mapped_column(JSONB, server_default=text('jsonb_build_object()'))
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'))
    schedule_enabled: Mapped[bool] = mapped_column(Boolean, server_default=text('false'))
    priority: Mapped[int] = mapped_column(Integer, server_default=text('0'))
    last_completed_repo_sync_queue_id: Mapped[Optional[int]] = mapped_column(BigInteger)

    repo_sync_queue: Mapped[List['RepoSyncQueue']] = relationship('RepoSyncQueue', foreign_keys='[RepoSyncQueue.repo_sync_id]', back_populates='repo_sync')
    last_completed_repo_sync_queue: Mapped['RepoSyncQueue'] = relationship('RepoSyncQueue', foreign_keys=[last_completed_repo_sync_queue_id], back_populates='repo_syncs')
    repo: Mapped['Repos_'] = relationship('Repos_', back_populates='repo_syncs')
    repo_sync_types: Mapped['RepoSyncTypes'] = relationship('RepoSyncTypes', back_populates='repo_syncs')


class SavedExplores(Base):
    __tablename__ = 'saved_explores'
    __table_args__ = (
        PrimaryKeyConstraint('id', name='saved_explores_pkey'),
        {'comment': 'Table to save explores', 'schema': 'mergestat'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'))
    created_by: Mapped[Optional[str]] = mapped_column(Text, comment='explore creator')
    created_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True), comment='timestamp when explore was created')
    name: Mapped[Optional[str]] = mapped_column(Text, comment='explore name')
    description: Mapped[Optional[str]] = mapped_column(Text, comment='explore description')
    metadata_: Mapped[Optional[dict]] = mapped_column('metadata', JSONB, comment='explore metadata')


class SavedQueries(Base):
    __tablename__ = 'saved_queries'
    __table_args__ = (
        PrimaryKeyConstraint('id', name='saved_queries_pkey'),
        {'comment': 'Table to save queries', 'schema': 'mergestat'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'))
    name: Mapped[str] = mapped_column(Text, comment='query name')
    sql: Mapped[str] = mapped_column(Text, comment='query sql')
    created_by: Mapped[Optional[str]] = mapped_column(Text, comment='query creator')
    created_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True), comment='timestamp when query was created')
    description: Mapped[Optional[str]] = mapped_column(Text, comment='query description')
    metadata_: Mapped[Optional[dict]] = mapped_column('metadata', JSONB, comment='query metadata')


t_schema_introspection = Table(
    'schema_introspection', Base.metadata,
    Column('schema', String),
    Column('table_name', String),
    Column('table_type', String),
    Column('column_name', String),
    Column('ordinal_position', Integer),
    Column('is_nullable', String),
    Column('data_type', String),
    Column('udt_name', String),
    Column('column_description', Text),
    schema='mergestat'
)


class ServiceAuthCredentialTypes(Base):
    __tablename__ = 'service_auth_credential_types'
    __table_args__ = (
        PrimaryKeyConstraint('type', name='service_auth_credential_types_pkey'),
        {'schema': 'mergestat'}
    )

    type: Mapped[str] = mapped_column(Text, primary_key=True)
    description: Mapped[str] = mapped_column(Text)

    service_auth_credentials: Mapped[List['ServiceAuthCredentials']] = relationship('ServiceAuthCredentials', back_populates='service_auth_credential_types')


t_user_mgmt_pg_users = Table(
    'user_mgmt_pg_users', Base.metadata,
    Column('rolname', String),
    Column('rolsuper', Boolean),
    Column('rolinherit', Boolean),
    Column('rolcreaterole', Boolean),
    Column('rolcreatedb', Boolean),
    Column('rolcanlogin', Boolean),
    Column('rolconnlimit', Integer),
    Column('rolvaliduntil', DateTime(True)),
    Column('rolreplication', Boolean),
    Column('rolbypassrls', Boolean),
    Column('memberof', ARRAY(String())),
    schema='mergestat'
)


class VendorTypes(Base):
    __tablename__ = 'vendor_types'
    __table_args__ = (
        PrimaryKeyConstraint('name', name='vendor_types_pkey'),
        {'schema': 'mergestat'}
    )

    name: Mapped[str] = mapped_column(Text, primary_key=True)
    display_name: Mapped[str] = mapped_column(Text)
    description: Mapped[Optional[str]] = mapped_column(Text)

    vendors: Mapped[List['Vendors']] = relationship('Vendors', back_populates='vendor_types')


class SchemaMigrations(Base):
    __tablename__ = 'schema_migrations'
    __table_args__ = (
        PrimaryKeyConstraint('version', name='schema_migrations_pkey'),
        {'comment': 'MergeStat internal table to track schema migrations',
     'schema': 'public'}
    )

    version: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    dirty: Mapped[bool] = mapped_column(Boolean)


class SchemaMigrationsHistory(Base):
    __tablename__ = 'schema_migrations_history'
    __table_args__ = (
        PrimaryKeyConstraint('id', name='schema_migrations_history_pkey'),
        {'comment': 'MergeStat internal table to track schema migrations history',
     'schema': 'public'}
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    version: Mapped[int] = mapped_column(BigInteger)
    applied_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))


class Queues(Base):
    __tablename__ = 'queues'
    __table_args__ = (
        PrimaryKeyConstraint('name', name='queues_pkey'),
        {'schema': 'sqlq'}
    )

    name: Mapped[str] = mapped_column(Text, primary_key=True)
    priority: Mapped[int] = mapped_column(Integer, server_default=text('1'))
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    description: Mapped[Optional[str]] = mapped_column(Text)
    concurrency: Mapped[Optional[int]] = mapped_column(Integer, server_default=text('1'))

    jobs: Mapped[List['Jobs']] = relationship('Jobs', back_populates='queues')


class VendorTypes_(Base):
    __tablename__ = 'vendor_types'
    __table_args__ = (
        PrimaryKeyConstraint('name', name='vendor_types_pkey'),
    )

    name: Mapped[str] = mapped_column(Text, primary_key=True)
    display_name: Mapped[str] = mapped_column(Text)
    description: Mapped[Optional[str]] = mapped_column(Text)

    vendors: Mapped[List['Vendors_']] = relationship('Vendors_', back_populates='vendor_types')


class ContainerImages(Base):
    __tablename__ = 'container_images'
    __table_args__ = (
        ForeignKeyConstraint(['type'], ['mergestat.container_image_types.name'], name='fk_container_image_type'),
        PrimaryKeyConstraint('id', name='container_images_pkey'),
        UniqueConstraint('name', name='unique_container_images_name'),
        UniqueConstraint('url', name='unique_container_images_url'),
        {'schema': 'mergestat'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('gen_random_uuid()'))
    name: Mapped[str] = mapped_column(Text)
    type: Mapped[str] = mapped_column(Text, server_default=text("'docker'::text"))
    url: Mapped[str] = mapped_column(Text)
    version: Mapped[str] = mapped_column(Text, server_default=text("'latest'::text"))
    parameters: Mapped[dict] = mapped_column(JSONB, server_default=text("'{}'::jsonb"))
    queue: Mapped[str] = mapped_column(Text, server_default=text("'default'::text"))
    description: Mapped[Optional[str]] = mapped_column(Text)

    container_image_types: Mapped['ContainerImageTypes'] = relationship('ContainerImageTypes', back_populates='container_images')
    container_syncs: Mapped[List['ContainerSyncs']] = relationship('ContainerSyncs', back_populates='image')


class RepoSyncLogs(Base):
    __tablename__ = 'repo_sync_logs'
    __table_args__ = (
        ForeignKeyConstraint(['log_type'], ['mergestat.repo_sync_log_types.type'], ondelete='RESTRICT', onupdate='RESTRICT', name='repo_sync_logs_log_type_fkey'),
        ForeignKeyConstraint(['repo_sync_queue_id'], ['mergestat.repo_sync_queue.id'], ondelete='CASCADE', onupdate='RESTRICT', name='repo_sync_logs_repo_sync_queue_id_fkey'),
        PrimaryKeyConstraint('id', name='repo_sync_logs_pkey'),
        Index('idx_repo_sync_logs_repo_sync_created_at', 'created_at'),
        Index('idx_repo_sync_logs_repo_sync_queue_id', 'repo_sync_queue_id'),
        Index('idx_repo_sync_logs_repo_sync_queue_id_fkey', 'repo_sync_queue_id'),
        {'schema': 'mergestat'}
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    log_type: Mapped[str] = mapped_column(Text)
    message: Mapped[str] = mapped_column(Text)
    repo_sync_queue_id: Mapped[int] = mapped_column(BigInteger)

    repo_sync_log_types: Mapped['RepoSyncLogTypes'] = relationship('RepoSyncLogTypes', back_populates='repo_sync_logs')
    repo_sync_queue: Mapped['RepoSyncQueue'] = relationship('RepoSyncQueue', back_populates='repo_sync_logs')


class RepoSyncTypes(Base):
    __tablename__ = 'repo_sync_types'
    __table_args__ = (
        ForeignKeyConstraint(['type_group'], ['mergestat.repo_sync_type_groups.group'], ondelete='RESTRICT', onupdate='RESTRICT', name='repo_sync_types_type_group_fkey'),
        PrimaryKeyConstraint('type', name='repo_sync_types_pkey'),
        {'schema': 'mergestat'}
    )

    type: Mapped[str] = mapped_column(Text, primary_key=True)
    short_name: Mapped[str] = mapped_column(Text, server_default=text("''::text"))
    priority: Mapped[int] = mapped_column(Integer, server_default=text('0'))
    type_group: Mapped[str] = mapped_column(Text, server_default=text("'DEFAULT'::text"))
    description: Mapped[Optional[str]] = mapped_column(Text)

    repo_sync_type_labels: Mapped[List['RepoSyncTypeLabels']] = relationship('RepoSyncTypeLabels', secondary='mergestat.repo_sync_type_label_associations', back_populates='repo_sync_types')
    repo_syncs: Mapped[List['RepoSyncs']] = relationship('RepoSyncs', back_populates='repo_sync_types')
    repo_sync_type_groups: Mapped['RepoSyncTypeGroups'] = relationship('RepoSyncTypeGroups', back_populates='repo_sync_types')


class Vendors(Base):
    __tablename__ = 'vendors'
    __table_args__ = (
        ForeignKeyConstraint(['type'], ['mergestat.vendor_types.name'], name='fk_vendors_type'),
        PrimaryKeyConstraint('name', name='vendors_pkey'),
        {'schema': 'mergestat'}
    )

    name: Mapped[str] = mapped_column(Text, primary_key=True)
    display_name: Mapped[str] = mapped_column(Text)
    type: Mapped[str] = mapped_column(Text)
    description: Mapped[Optional[str]] = mapped_column(Text)

    vendor_types: Mapped['VendorTypes'] = relationship('VendorTypes', back_populates='vendors')
    providers: Mapped[List['Providers']] = relationship('Providers', back_populates='vendors')


class Jobs(Base):
    __tablename__ = 'jobs'
    __table_args__ = (
        ForeignKeyConstraint(['queue'], ['sqlq.queues.name'], ondelete='CASCADE', name='jobs_queue_fkey'),
        PrimaryKeyConstraint('id', name='jobs_pkey'),
        Index('ix_jobs_queue_type_status', 'queue', 'typename', 'status'),
        {'schema': 'sqlq'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'))
    queue: Mapped[str] = mapped_column(Text)
    typename: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(ENUM('job_states', 'pending', 'running', 'success', 'errored', 'cancelling', 'cancelled', name='job_states'), server_default=text("'pending'::sqlq.job_states"))
    priority: Mapped[int] = mapped_column(Integer, server_default=text('10'))
    last_queued_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    keepalive_interval: Mapped[int] = mapped_column(BigInteger, server_default=text("((30)::numeric * '1000000000'::numeric)"))
    retention_ttl: Mapped[int] = mapped_column(BigInteger, server_default=text('0'))
    parameters: Mapped[Optional[dict]] = mapped_column(JSONB)
    result: Mapped[Optional[dict]] = mapped_column(JSONB)
    max_retries: Mapped[Optional[int]] = mapped_column(Integer, server_default=text('1'))
    attempt: Mapped[Optional[int]] = mapped_column(Integer, server_default=text('0'))
    started_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))
    completed_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))
    last_keepalive: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))
    run_after: Mapped[Optional[int]] = mapped_column(BigInteger, server_default=text('0'))

    queues: Mapped['Queues'] = relationship('Queues', back_populates='jobs')
    container_sync_executions: Mapped[List['ContainerSyncExecutions']] = relationship('ContainerSyncExecutions', back_populates='job')


class Vendors_(Base):
    __tablename__ = 'vendors'
    __table_args__ = (
        ForeignKeyConstraint(['type'], ['vendor_types.name'], name='fk_vendors_type'),
        PrimaryKeyConstraint('name', name='vendors_pkey')
    )

    name: Mapped[str] = mapped_column(Text, primary_key=True)
    display_name: Mapped[str] = mapped_column(Text)
    type: Mapped[str] = mapped_column(Text)
    description: Mapped[Optional[str]] = mapped_column(Text)

    vendor_types: Mapped['VendorTypes_'] = relationship('VendorTypes_', back_populates='vendors')
    providers: Mapped[List['Providers_']] = relationship('Providers_', back_populates='vendors')


class Providers(Base):
    __tablename__ = 'providers'
    __table_args__ = (
        ForeignKeyConstraint(['vendor'], ['mergestat.vendors.name'], name='fk_vendors_providers_vendor'),
        PrimaryKeyConstraint('id', name='providers_pkey'),
        UniqueConstraint('name', name='uq_providers_name'),
        {'schema': 'mergestat'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('gen_random_uuid()'))
    name: Mapped[str] = mapped_column(Text)
    vendor: Mapped[str] = mapped_column(Text)
    settings: Mapped[dict] = mapped_column(JSONB)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    description: Mapped[Optional[str]] = mapped_column(Text)

    vendors: Mapped['Vendors'] = relationship('Vendors', back_populates='providers')
    repo_imports: Mapped[List['RepoImports']] = relationship('RepoImports', back_populates='providers')
    service_auth_credentials: Mapped[List['ServiceAuthCredentials']] = relationship('ServiceAuthCredentials', back_populates='providers')


t_repo_sync_type_label_associations = Table(
    'repo_sync_type_label_associations', Base.metadata,
    Column('label', Text, nullable=False),
    Column('repo_sync_type', Text, nullable=False),
    ForeignKeyConstraint(['label'], ['mergestat.repo_sync_type_labels.label'], ondelete='CASCADE', name='repo_sync_type_label_associations_label_fkey'),
    ForeignKeyConstraint(['repo_sync_type'], ['mergestat.repo_sync_types.type'], ondelete='CASCADE', name='repo_sync_type_label_associations_repo_sync_type_fkey'),
    UniqueConstraint('label', 'repo_sync_type', name='repo_sync_type_label_associations_label_repo_sync_type_key'),
    schema='mergestat',
    comment='@name labelAssociations'
)


class Providers_(Base):
    __tablename__ = 'providers'
    __table_args__ = (
        ForeignKeyConstraint(['vendor'], ['vendors.name'], name='fk_vendors_providers_vendor'),
        PrimaryKeyConstraint('id', name='providers_pkey'),
        UniqueConstraint('name', name='uq_providers_name')
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('gen_random_uuid()'))
    name: Mapped[str] = mapped_column(Text)
    vendor: Mapped[str] = mapped_column(Text)
    settings: Mapped[dict] = mapped_column(JSONB)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    description: Mapped[Optional[str]] = mapped_column(Text)

    vendors: Mapped['Vendors_'] = relationship('Vendors_', back_populates='providers')
    repo_imports: Mapped[List['RepoImports_']] = relationship('RepoImports_', back_populates='providers')
    repos: Mapped[List['Repos']] = relationship('Repos', back_populates='providers')
    repos_: Mapped[List['Repos_']] = relationship('Repos_', back_populates='providers')


class RepoImports(Base):
    __tablename__ = 'repo_imports'
    __table_args__ = (
        CheckConstraint("import_interval > '00:00:30'::interval", name='repo_imports_import_interval_check'),
        ForeignKeyConstraint(['provider'], ['mergestat.providers.id'], ondelete='CASCADE', name='fk_providers_repo_imports_provider'),
        PrimaryKeyConstraint('id', name='repo_imports_pkey'),
        {'comment': 'Table for "dynamic" repo imports - regularly loading from a '
                'GitHub org for example',
     'schema': 'mergestat'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'))
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    settings: Mapped[dict] = mapped_column(JSONB, server_default=text('jsonb_build_object()'))
    provider: Mapped[uuid.UUID] = mapped_column(Uuid)
    last_import: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))
    import_interval: Mapped[Optional[datetime.timedelta]] = mapped_column(INTERVAL, server_default=text("'00:30:00'::interval"))
    last_import_started_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))
    import_status: Mapped[Optional[str]] = mapped_column(Text)
    import_error: Mapped[Optional[str]] = mapped_column(Text)

    providers: Mapped['Providers'] = relationship('Providers', back_populates='repo_imports')


class ServiceAuthCredentials(Base):
    __tablename__ = 'service_auth_credentials'
    __table_args__ = (
        ForeignKeyConstraint(['provider'], ['mergestat.providers.id'], ondelete='CASCADE', name='fk_providers_credentials_provider'),
        ForeignKeyConstraint(['type'], ['mergestat.service_auth_credential_types.type'], ondelete='RESTRICT', onupdate='RESTRICT', name='service_auth_credentials_type_fkey'),
        PrimaryKeyConstraint('id', name='service_auth_credentials_pkey'),
        Index('ix_single_default_per_provider', 'provider', 'is_default', unique=True),
        {'schema': 'mergestat'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'))
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    type: Mapped[str] = mapped_column(Text)
    provider: Mapped[uuid.UUID] = mapped_column(Uuid)
    credentials: Mapped[Optional[bytes]] = mapped_column(LargeBinary)
    is_default: Mapped[Optional[bool]] = mapped_column(Boolean, server_default=text('false'))
    username: Mapped[Optional[bytes]] = mapped_column(LargeBinary)

    providers: Mapped['Providers'] = relationship('Providers', back_populates='service_auth_credentials')
    service_auth_credential_types: Mapped['ServiceAuthCredentialTypes'] = relationship('ServiceAuthCredentialTypes', back_populates='service_auth_credentials')


class RepoImports_(Base):
    __tablename__ = 'repo_imports'
    __table_args__ = (
        CheckConstraint("import_interval > '00:00:30'::interval", name='repo_imports_import_interval_check'),
        ForeignKeyConstraint(['provider'], ['providers.id'], ondelete='CASCADE', name='fk_providers_repo_imports_provider'),
        PrimaryKeyConstraint('id', name='repo_imports_pkey'),
        {'comment': 'Table for "dynamic" repo imports - regularly loading from a '
                'GitHub org for example'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'))
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'))
    settings: Mapped[dict] = mapped_column(JSONB, server_default=text('jsonb_build_object()'))
    provider: Mapped[uuid.UUID] = mapped_column(Uuid)
    last_import: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))
    import_interval: Mapped[Optional[datetime.timedelta]] = mapped_column(INTERVAL, server_default=text("'00:30:00'::interval"))
    last_import_started_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True))
    import_status: Mapped[Optional[str]] = mapped_column(Text)
    import_error: Mapped[Optional[str]] = mapped_column(Text)

    providers: Mapped['Providers_'] = relationship('Providers_', back_populates='repo_imports')
    repos: Mapped[List['Repos']] = relationship('Repos', back_populates='repo_import')
    repos_: Mapped[List['Repos_']] = relationship('Repos_', back_populates='repo_import')


class Repos(Base):
    __tablename__ = 'repos'
    __table_args__ = (
        ForeignKeyConstraint(['provider'], ['providers.id'], ondelete='CASCADE', name='fk_repos_provider'),
        ForeignKeyConstraint(['repo_import_id'], ['repo_imports.id'], ondelete='CASCADE', onupdate='RESTRICT', name='repos_repo_import_id_fkey'),
        PrimaryKeyConstraint('id', name='repos_pkey'),
        Index('idx_repos_repo_import_id_fkey', 'repo_import_id'),
        Index('repos_is_duplicate', 'is_duplicate'),
        Index('repos_repo_gin', 'repo'),
        Index('repos_repo_ref_unique', 'repo', unique=True),
        {'comment': 'git repositories to track', 'schema': 'public'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'), comment='MergeStat identifier for the repo')
    repo: Mapped[str] = mapped_column(Text, comment='URL for the repo')
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'), comment='timestamp of when the MergeStat repo entry was created')
    settings: Mapped[dict] = mapped_column(JSONB, server_default=text('jsonb_build_object()'), comment='JSON settings for the repo')
    tags: Mapped[dict] = mapped_column(JSONB, server_default=text('jsonb_build_array()'), comment='array of tags for the repo for topics in GitHub as well as tags added in MergeStat')
    provider: Mapped[uuid.UUID] = mapped_column(Uuid)
    is_duplicate: Mapped[bool] = mapped_column(Boolean, server_default=text('false'))
    ref: Mapped[Optional[str]] = mapped_column(Text, comment='ref for the repo')
    repo_import_id: Mapped[Optional[uuid.UUID]] = mapped_column(Uuid, comment='foreign key for mergestat.repo_imports.id')

    providers: Mapped['Providers_'] = relationship('Providers_', back_populates='repos')
    repo_import: Mapped['RepoImports_'] = relationship('RepoImports_', back_populates='repos')
    _mergestat_explore_file_metadata: Mapped[List['MergestatExploreFileMetadata']] = relationship('MergestatExploreFileMetadata', back_populates='repo')
    git_commit_stats: Mapped[List['GitCommitStats']] = relationship('GitCommitStats', back_populates='repo')
    git_commits: Mapped[List['GitCommits']] = relationship('GitCommits', back_populates='repo')
    git_files: Mapped[List['GitFiles']] = relationship('GitFiles', back_populates='repo')


class Repos_(Base):
    __tablename__ = 'repos'
    __table_args__ = (
        ForeignKeyConstraint(['provider'], ['providers.id'], ondelete='CASCADE', name='fk_repos_provider'),
        ForeignKeyConstraint(['repo_import_id'], ['repo_imports.id'], ondelete='CASCADE', onupdate='RESTRICT', name='repos_repo_import_id_fkey'),
        PrimaryKeyConstraint('id', name='repos_pkey'),
        Index('idx_repos_repo_import_id_fkey', 'repo_import_id'),
        Index('repos_is_duplicate', 'is_duplicate'),
        Index('repos_repo_gin', 'repo'),
        Index('repos_repo_ref_unique', 'repo', unique=True),
        {'comment': 'git repositories to track'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('public.gen_random_uuid()'), comment='MergeStat identifier for the repo')
    repo: Mapped[str] = mapped_column(Text, comment='URL for the repo')
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'), comment='timestamp of when the MergeStat repo entry was created')
    settings: Mapped[dict] = mapped_column(JSONB, server_default=text('jsonb_build_object()'), comment='JSON settings for the repo')
    tags: Mapped[dict] = mapped_column(JSONB, server_default=text('jsonb_build_array()'), comment='array of tags for the repo for topics in GitHub as well as tags added in MergeStat')
    provider: Mapped[uuid.UUID] = mapped_column(Uuid)
    is_duplicate: Mapped[bool] = mapped_column(Boolean, server_default=text('false'))
    ref: Mapped[Optional[str]] = mapped_column(Text, comment='ref for the repo')
    repo_import_id: Mapped[Optional[uuid.UUID]] = mapped_column(Uuid, comment='foreign key for mergestat.repo_imports.id')

    repo_syncs: Mapped[List['RepoSyncs']] = relationship('RepoSyncs', back_populates='repo')
    providers: Mapped['Providers_'] = relationship('Providers_', back_populates='repos_')
    repo_import: Mapped['RepoImports_'] = relationship('RepoImports_', back_populates='repos_')
    container_syncs: Mapped[List['ContainerSyncs']] = relationship('ContainerSyncs', back_populates='repo')
    sync_variables: Mapped[List['SyncVariables']] = relationship('SyncVariables', back_populates='repo')


class ContainerSyncs(Base):
    __tablename__ = 'container_syncs'
    __table_args__ = (
        ForeignKeyConstraint(['image_id'], ['mergestat.container_images.id'], ondelete='CASCADE', name='fk_sync_container'),
        ForeignKeyConstraint(['repo_id'], ['repos.id'], ondelete='CASCADE', name='fk_sync_repository'),
        PrimaryKeyConstraint('id', name='container_syncs_pkey'),
        UniqueConstraint('repo_id', 'image_id', name='unq_repo_image'),
        {'schema': 'mergestat'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('gen_random_uuid()'))
    repo_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    image_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    parameters: Mapped[dict] = mapped_column(JSONB, server_default=text("'{}'::jsonb"))

    image: Mapped['ContainerImages'] = relationship('ContainerImages', back_populates='container_syncs')
    repo: Mapped['Repos_'] = relationship('Repos_', back_populates='container_syncs')
    container_sync_executions: Mapped[List['ContainerSyncExecutions']] = relationship('ContainerSyncExecutions', back_populates='sync')
    container_sync_schedules: Mapped['ContainerSyncSchedules'] = relationship('ContainerSyncSchedules', uselist=False, back_populates='sync')


class SyncVariables(Base):
    __tablename__ = 'sync_variables'
    __table_args__ = (
        ForeignKeyConstraint(['repo_id'], ['repos.id'], name='sync_variables_repo_id_fkey'),
        PrimaryKeyConstraint('repo_id', 'key', name='sync_variables_pkey'),
        {'schema': 'mergestat'}
    )

    repo_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    key: Mapped[str] = mapped_column(CITEXT, primary_key=True)
    value: Mapped[Optional[bytes]] = mapped_column(LargeBinary)

    repo: Mapped['Repos_'] = relationship('Repos_', back_populates='sync_variables')


class MergestatExploreFileMetadata(Base):
    __tablename__ = '_mergestat_explore_file_metadata'
    __table_args__ = (
        ForeignKeyConstraint(['repo_id'], ['public.repos.id'], ondelete='CASCADE', onupdate='RESTRICT', name='_mergestat_explore_file_metadata_repo_id_fkey'),
        PrimaryKeyConstraint('repo_id', 'path', name='_mergestat_explore_file_metadata_pkey'),
        {'comment': 'file metadata for explore experience', 'schema': 'public'}
    )

    repo_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, comment='foreign key for public.repos.id')
    path: Mapped[str] = mapped_column(Text, primary_key=True, comment='path to the file')
    _mergestat_synced_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'), comment='timestamp when record was synced into the MergeStat database')
    last_commit_hash: Mapped[Optional[str]] = mapped_column(Text, comment='hash based reference to last commit')
    last_commit_message: Mapped[Optional[str]] = mapped_column(Text, comment='message of the commit')
    last_commit_author_name: Mapped[Optional[str]] = mapped_column(Text, comment='name of the author of the the modification')
    last_commit_author_email: Mapped[Optional[str]] = mapped_column(Text, comment='email of the author of the modification')
    last_commit_author_when: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True), comment='timestamp of when the modifcation was authored')
    last_commit_committer_name: Mapped[Optional[str]] = mapped_column(Text, comment='name of the author who committed the modification')
    last_commit_committer_email: Mapped[Optional[str]] = mapped_column(Text, comment='email of the author who committed the modification')
    last_commit_committer_when: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True), comment='timestamp of when the commit was made')
    last_commit_parents: Mapped[Optional[int]] = mapped_column(Integer, comment='the number of parents of the commit')

    repo: Mapped['Repos'] = relationship('Repos', back_populates='_mergestat_explore_file_metadata')


class MergestatExploreRepoMetadata(Repos):
    __tablename__ = '_mergestat_explore_repo_metadata'
    __table_args__ = (
        ForeignKeyConstraint(['repo_id'], ['public.repos.id'], ondelete='CASCADE', onupdate='RESTRICT', name='_mergestat_explore_repo_metadata_repo_id_fkey'),
        PrimaryKeyConstraint('repo_id', name='_mergestat_explore_repo_metadata_pkey'),
        {'comment': 'repo metadata for explore experience', 'schema': 'public'}
    )

    repo_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, comment='foreign key for public.repos.id')
    _mergestat_synced_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'), comment='timestamp when record was synced into the MergeStat database')
    last_commit_hash: Mapped[Optional[str]] = mapped_column(Text, comment='hash based reference to last commit')
    last_commit_message: Mapped[Optional[str]] = mapped_column(Text, comment='message of the commit')
    last_commit_author_name: Mapped[Optional[str]] = mapped_column(Text, comment='name of the author of the the modification')
    last_commit_author_email: Mapped[Optional[str]] = mapped_column(Text, comment='email of the author of the modification')
    last_commit_author_when: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True), comment='timestamp of when the modifcation was authored')
    last_commit_committer_name: Mapped[Optional[str]] = mapped_column(Text, comment='name of the author who committed the modification')
    last_commit_committer_email: Mapped[Optional[str]] = mapped_column(Text, comment='email of the author who committed the modification')
    last_commit_committer_when: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True), comment='timestamp of when the commit was made')
    last_commit_parents: Mapped[Optional[int]] = mapped_column(Integer, comment='the number of parents of the commit')


class GitCommitStats(Base):
    __tablename__ = 'git_commit_stats'
    __table_args__ = (
        ForeignKeyConstraint(['repo_id'], ['public.repos.id'], ondelete='CASCADE', onupdate='RESTRICT', name='git_commit_stats_repo_id_fkey'),
        PrimaryKeyConstraint('repo_id', 'file_path', 'commit_hash', name='commit_stats_pkey'),
        Index('idx_commit_stats_repo_id_fkey', 'repo_id'),
        Index('idx_git_commit_stats_repo_id_hash_file_path', 'repo_id', 'commit_hash', 'file_path'),
        {'comment': 'git commit stats of a repo', 'schema': 'public'}
    )

    repo_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, comment='foreign key for public.repos.id')
    commit_hash: Mapped[str] = mapped_column(Text, primary_key=True, comment='hash of the commit')
    file_path: Mapped[str] = mapped_column(Text, primary_key=True, comment='path of the file the modification was made in')
    additions: Mapped[int] = mapped_column(Integer, comment='the number of additions in this path of the commit')
    deletions: Mapped[int] = mapped_column(Integer, comment='the number of deletions in this path of the commit')
    _mergestat_synced_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'), comment='timestamp when record was synced into the MergeStat database')
    old_file_mode: Mapped[Optional[str]] = mapped_column(Text, comment='old file mode derived from git mode. possible values (unknown, none, regular_file, symbolic_link, git_link)')
    new_file_mode: Mapped[Optional[str]] = mapped_column(Text, comment='new file mode derived from git mode. possible values (unknown, none, regular_file, symbolic_link, git_link)')

    repo: Mapped['Repos'] = relationship('Repos', back_populates='git_commit_stats')


class GitCommits(Base):
    __tablename__ = 'git_commits'
    __table_args__ = (
        ForeignKeyConstraint(['repo_id'], ['public.repos.id'], ondelete='CASCADE', onupdate='RESTRICT', name='git_commits_repo_id_fkey'),
        PrimaryKeyConstraint('repo_id', 'hash', name='commits_pkey'),
        Index('commits_author_when_idx', 'repo_id', 'author_when'),
        Index('git_commits_author_email_gin', 'author_email'),
        Index('git_commits_author_name_gin', 'author_name'),
        Index('idx_commits_repo_id_fkey', 'repo_id'),
        Index('idx_git_commits_repo_id_hash_parents', 'repo_id', 'hash', 'parents'),
        {'comment': 'git commit history of a repo', 'schema': 'public'}
    )

    repo_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, comment='foreign key for public.repos.id')
    hash: Mapped[str] = mapped_column(Text, primary_key=True, comment='hash of the commit')
    author_when: Mapped[datetime.datetime] = mapped_column(DateTime(True), comment='timestamp of when the modifcation was authored')
    committer_when: Mapped[datetime.datetime] = mapped_column(DateTime(True), comment='timestamp of when the commit was made')
    parents: Mapped[int] = mapped_column(Integer, comment='the number of parents of the commit')
    _mergestat_synced_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'), comment='timestamp when record was synced into the MergeStat database')
    message: Mapped[Optional[str]] = mapped_column(Text, comment='message of the commit')
    author_name: Mapped[Optional[str]] = mapped_column(Text, comment='name of the author of the the modification')
    author_email: Mapped[Optional[str]] = mapped_column(Text, comment='email of the author of the modification')
    committer_name: Mapped[Optional[str]] = mapped_column(Text, comment='name of the author who committed the modification')
    committer_email: Mapped[Optional[str]] = mapped_column(Text, comment='email of the author who committed the modification')
    additions: Mapped[Optional[int]] = mapped_column(Integer)
    deletions: Mapped[Optional[int]] = mapped_column(Integer)

    repo: Mapped['Repos'] = relationship('Repos', back_populates='git_commits')


class GitFiles(Base):
    __tablename__ = 'git_files'
    __table_args__ = (
        ForeignKeyConstraint(['repo_id'], ['public.repos.id'], ondelete='CASCADE', onupdate='RESTRICT', name='git_files_repo_id_fkey'),
        PrimaryKeyConstraint('repo_id', 'path', name='files_pkey'),
        Index('idx_files_repo_id_fkey', 'repo_id'),
        Index('idx_gist_git_files_path', 'path'),
        {'comment': 'git files (content and paths) of a repo', 'schema': 'public'}
    )

    repo_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, comment='foreign key for public.repos.id')
    path: Mapped[str] = mapped_column(Text, primary_key=True, comment='path of the file')
    executable: Mapped[bool] = mapped_column(Boolean, comment='boolean to determine if the file is an executable')
    _mergestat_synced_at: Mapped[datetime.datetime] = mapped_column(DateTime(True), server_default=text('now()'), comment='timestamp when record was synced into the MergeStat database')
    contents: Mapped[Optional[str]] = mapped_column(Text, comment='contents of the file')
    size: Mapped[Optional[int]] = mapped_column(Integer)
    ext: Mapped[Optional[str]] = mapped_column(Text)

    repo: Mapped['Repos'] = relationship('Repos', back_populates='git_files')


class ContainerSyncExecutions(Base):
    __tablename__ = 'container_sync_executions'
    __table_args__ = (
        ForeignKeyConstraint(['job_id'], ['sqlq.jobs.id'], ondelete='CASCADE', name='fk_execution_job'),
        ForeignKeyConstraint(['sync_id'], ['mergestat.container_syncs.id'], ondelete='CASCADE', name='fk_execution_sync'),
        PrimaryKeyConstraint('sync_id', 'job_id', name='container_sync_executions_pkey'),
        {'schema': 'mergestat'}
    )

    sync_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    job_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    created_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True), server_default=text('now()'))

    job: Mapped['Jobs'] = relationship('Jobs', back_populates='container_sync_executions')
    sync: Mapped['ContainerSyncs'] = relationship('ContainerSyncs', back_populates='container_sync_executions')


class ContainerSyncSchedules(Base):
    __tablename__ = 'container_sync_schedules'
    __table_args__ = (
        ForeignKeyConstraint(['sync_id'], ['mergestat.container_syncs.id'], ondelete='CASCADE', name='fk_schedule_sync'),
        PrimaryKeyConstraint('id', name='container_sync_schedules_pkey'),
        UniqueConstraint('sync_id', name='unique_container_sync_schedule'),
        {'schema': 'mergestat'}
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, server_default=text('gen_random_uuid()'))
    sync_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    created_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime(True), server_default=text('now()'))

    sync: Mapped['ContainerSyncs'] = relationship('ContainerSyncs', back_populates='container_sync_schedules')
