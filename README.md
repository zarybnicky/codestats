# Codestats

## Getting started

1. update your .ssh config - I use this config for multiplexing
2. create an `.env.local` in this directory
3. I use Nix + direnv + devenv, meaning that to start the service, run:
  - `poetry install`
  - `direnv allow`
  - `devenv up`
  - `streamlit run main.py`

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

``` sh
export GITLAB_HOST=gitlab.mgmtprod
export GITLAB_USER=<username>
export GITLAB_TOKEN=<personal access token>

export GITOLITE_HOST="redmine-git"

export GITLAB_ROOT="~/repos-gitlab"
export GITOLITE_ROOT="~/repos-gitolite"
# OR, to put them in a neighborghing directories
export GITLAB_ROOT="$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")/repos-gitlab"
export GITOLITE_ROOT="$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")/repos-gitolite"
```
