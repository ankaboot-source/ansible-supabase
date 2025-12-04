#!/bin/bash

[[ ! $USE_SUDO ]] && export USE_SUDO=""
[[ ! $DRY_RUN ]] && export DRY_RUN=0
[[ ! $VERBOSE ]] && export VERBOSE=""
[[ ! $VAR_OPTS ]] && export VAR_OPTS=""
[[ ! $PLAYBOOK ]] && export PLAYBOOK="playbook"
[[ ! $ACTION_SELECTED ]] && export ACTION_SELECTED=0


environment_set() {
  env="${1:-supabase}"
  export VAR_OPTS="-e \"@env/${env}.yml\""
  export PLAYBOOK="playbook-${env//[0-9]/}.yml"
}

sudo_enable() {
  export USE_SUDO="sudo"
}

help_display() {
  echo "Usage: ./install.sh [options]"
  echo "-s: run steps with sudo"
  echo "-h: print help"
  echo "-d: dry run (no operation)"
  echo "-v: verbose"
  echo "-i: install ansible"
  echo "-a: run ansible-playbook"
  echo "-t: run test on ansible playbook"
  echo "Example: ./install.sh"
}

dry_run_set() {
  export DRY_RUN=1
}

verbose_set() {
  export VERBOSE="-vvvv"
}

install_ansible() {
  install_cmd="${USE_SUDO} apt install -y software-properties-common  && ${USE_SUDO} apt install -y ansible git"

  if ! ansible-playbook --version 2>/dev/null; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "${install_cmd}"
    else
      eval "${install_cmd}"
    fi
  fi
}

ansible_playbook() {
  ansible_cmd="${USE_SUDO} ansible-playbook ${PLAYBOOK} ${VAR_OPTS} ${VERBOSE}"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "${ansible_cmd}"
  else
    eval "${ansible_cmd}"
  fi
}

test_ansible() {
  install_ansible
  ansible_test_cmd="${USE_SUDO} ansible-playbook ${PLAYBOOK} ${VAR_OPTS} ${VERBOSE} --check --diff"
  eval "${ansible_test_cmd}"
}

perform_all() {
  install_ansible
  ansible_playbook
}

error() {
  echo "ERROR: invalid parameters" >&2
  help_display >&2
  exit 1
}

# default environment if -e isn't called
environment_set "supabase"

while getopts ":e:shdviaprt" option; do
  case "$option" in
    :) error ;;
    e) environment_set $OPTARG ;;
    s) sudo_enable ;;
    h) help_display ;;
    d) dry_run_set ;;
    v) verbose_set  ;;
    i) install_ansible ; ACTION_SELECTED=1 ;;
    t) test_ansible ; ACTION_SELECTED=1 ;;
    a) ansible_playbook ; ACTION_SELECTED=1 ;;
    *) error ;;
    esac
done

# Install ansible and run ansible-playbook if no option is given
if [[ $ACTION_SELECTED -eq 0 ]]; then
  perform_all
fi

