# Codestats

## With an existing DuckDB:

1. Extract the database to `data/git.duckdb`
   ``` sh
   mkdir data/
   mv ~/Downloads/git.duckdb.gz data/
   gunzip data/git.duckdb.gz
   ```
2. Install dependencies
   ```sh
   poetry install
   ```
3. Start Streamlit
   ```sh
   poetry run streamlit run Recent.py
   ```

## Without an existing DB

1. Update your .ssh config - I use this config for multiplexing to speed up cloning

   ``` makefile
   Host redmine-git
     User git
     HostName redmine.mgmtprod
     Port 2223
     IdentityFile ~/.ssh/id_rsa
     ControlPath ~/.ssh/connections/%r@%h.ctl
     ControlMaster auto
     ControlPersist 10m
     IdentitiesOnly yes
   ```

2. Create an `.env` in this directory
   ``` sh
   export GITLAB_HOST=gitlab.mgmtprod
   export GITLAB_USER=<username>
   export GITLAB_TOKEN=<personal access token>
   export GITLAB_ROOT="${HOME}/repos/gitlab"

   export GITOLITE_HOST="redmine-git"
   export GITOLITE_ROOT="${HOME}/repos/gitolite"
   ```

   If necessary, create the GitLab personal access token first.
   
3. The indexing process happens in four steps:
   - repository discovery (`poetry run python discover_gitlab.py` and `discover_gitolite.py`)
     - this produces `data/repos-*.csv`
   - cloning (or fetching) the repositories (`fetch_known_repos.py`)
     - this produces bare repositories in `GITLAB_ROOT` and `GITOLITE_ROOT`
     - I have, in the past, used `git worktree` to work with bare repos locally too
       - `git -C ~/repos/gitlab/odoo/odoo.git worktree add ~/work/odoo main`
       - `git -C ~/work/odoo commit`
       - `rm -rf ~/work/odoo`
       - `git -C ~/repos/gitlab/odoo/odoo.git worktree prune`
   - indexing the repositories by parsing the output of `git ls-tree` and `git log --numstat`
     - produces `data/git_*.csv`
   - and lastly loading the CSVs into a DuckDB database
     - produces `data/git.duckdb`
     - to be compressed into `data/git.duckdb.gz` using `gzip -k data/git.duckdb`
     - originally, this project ran on PostgreSQL
     - but DuckDB is useful for a workshop format, and for sharing the DB index in general
