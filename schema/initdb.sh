#!/usr/bin/env sh

createuser mergestat --superuser
createuser mergestat_admin
createuser mergestat_role_readonly
createuser mergestat_role_user
createuser mergestat_role_admin
createuser mergestat_role_demo
createuser mergestat_role_queries_only
createuser readaccess
createdb mergestat --owner=mergestat
createdb mergestat-shadow --owner=mergestat
