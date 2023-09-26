#!/bin/bash

# Purpose: Bulk-delete GitLab pipelines older than a given date
# Author: Sergey Bondarev
# https://github.com/LuckySB/gitlab-remove-old-pipeline
#
# GitLab API: v4
# Requirements: jq must be instaled ($ sudo yum install jq)
# API example: https://gitlab.example.com/api/v4/projects
# API example: https://gitlab.example.com/api/v4/projects/<projectid>/pipelines

set -o nounset
set -o errtrace
set -o pipefail

# DEFAULTS BEGIN
typeset GITLAB_URL=${GITLAB_URL:-""}
typeset GITLAB_TOKEN=${GITLAB_TOKEN:-""}         # must have API r/w access
typeset GITLAB_GROUP=""
typeset DELETE_BEFORE="" PIPELINE_DELETE_BEFORE=""
typeset PIPELINE_SOURCE=""
typeset PIPELINE_STATUS=""
typeset SELECT_ARCHIVED_PROJECT="archived=false"
typeset -i ARCHIVE_PROJECT=0
typeset -i KEEP_PIPELINES=0
typeset -i VERBOSE=0

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly bn="$(basename "$0")"
readonly BIN_REQUIRED="curl jq"
# CONSTANTS END

########################################################################

function main(){
  local fn=${FUNCNAME[0]}

  trap 'except $LINENO' ERR
  trap _exit EXIT

  checks
  checks var:GITLAB_URL
  checks var:GITLAB_TOKEN
  checks var:GITLAB_GROUP

  local -i pages=0 page=0 pipeline_pages=0 pipeline_page=0 count_pipeline=0 count_pipeline_page=1 keep_pipelines_mod100=0
  local project_id project_namespace
  local pipeline_id pipe_source pipe_date

  # Get total number of pages, 100 projects per page
  pages=$(curl -s --head -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4${GITLAB_GROUP}/projects?${SELECT_ARCHIVED_PROJECT}&include_subgroups=true&per_page=100" | awk '/x-total-pages:/ {printf "%i", $2}')

  for page in $(seq 1 $pages); do
    while IFS=';' read -r project_id project_namespace; do
      (( VERBOSE > 0 )) && echo -e "\r\033[2K$project_id: $project_namespace"
      if (( ARCHIVE_PROJECT == 1 )); then
        curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" --request "POST" "$GITLAB_URL/api/v4/projects/$project_id/unarchive" >/dev/null
      fi
      count_pipeline_page=$(( KEEP_PIPELINES / 100 + 1))
      pipeline_pages=$(curl -s --head -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$project_id/pipelines?per_page=100&sort=desc${PIPELINE_SOURCE}${PIPELINE_STATUS}${PIPELINE_DELETE_BEFORE}" | awk '/x-total-pages:/ {printf "%i", $2}')
      [[ $pipeline_pages == "0" ]] && pipeline_pages=10
      keep_pipelines_mod100=$(( KEEP_PIPELINES % 100 ))
      pipeline_pages=$(( pipeline_pages - count_pipeline_page ))
      pipeline_pages=$(( count_pipeline_page + pipeline_pages * 100 / ( 100 - keep_pipelines_mod100 ) ))
      for pipeline_page in $(seq $count_pipeline_page $pipeline_pages); do
        count_pipeline=$(( KEEP_PIPELINES / 100 * 100))
        while IFS=';' read -r pipeline_id pipe_source pipe_status pipe_date; do
          (( VERBOSE > 1 )) && echo -ne "\r\033[2K$pipeline_id, $pipe_source, $pipe_status, $pipe_date" 
          if (( count_pipeline > KEEP_PIPELINES )) ; then
            curl -H "PRIVATE-TOKEN: $GITLAB_TOKEN" --request "DELETE" "$GITLAB_URL/api/v4/projects/$project_id/pipelines/$pipeline_id"
            (( VERBOSE > 1 )) && echo -n " - deleted"
            (( VERBOSE > 2 )) && echo
          else
            count_pipeline=$(( count_pipeline + 1 ))
            (( VERBOSE > 1 )) && echo -n " - skipped"
            (( VERBOSE > 2 )) && echo
          fi
        done < <(curl -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$project_id/pipelines?per_page=100&page=$count_pipeline_page&sort=desc${PIPELINE_SOURCE}${PIPELINE_STATUS}${PIPELINE_DELETE_BEFORE}" 2> /dev/null | jq -j '.[] | .id, ";", .source, ";", .status, ";", .updated_at, "\n"')
      done
      if (( ARCHIVE_PROJECT == 1 )); then
        curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" --request "POST" "$GITLAB_URL/api/v4/projects/$project_id/archive" >/dev/null
      fi
    done < <(curl -sH "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4${GITLAB_GROUP}/projects?${SELECT_ARCHIVED_PROJECT}&include_subgroups=true&per_page=100&page=$page" 2> /dev/null| jq -j '.[] | .id, ";", .name_with_namespace, "\n"')
  done
}

checks() {
    local fn=${FUNCNAME[0]}
    # Required binaries check
    for i in $BIN_REQUIRED; do
        if ! command -v "$i" >/dev/null
        then
            echo "Required binary '$i' is not installed" >&2
            false
        fi
    done

    local argv0=${1:-nop}

    if [[ ${argv0%%:*} == "var" ]]; then
        local interm=${argv0#*:}

        if [[ ${!interm:-nop} == "nop" ]]; then
            echo_err "Required variable ${interm:-UNKNOWN} is not defined"
            false
        fi
    fi
}

except() {
    local ret=$?
    local no=${1:-no_line}

    echo_fatal "error occured in function '$fn' near line ${no}."
    exit $ret
}

_exit() {
    local ret=$?
    exit $ret
}

usage() {
    echo -e "\\n    Usage: $bn <OPTIONS>\\n
    Options:

    -g, --gitlab-url       gitlab url (requred)
    -t, --token            token with read-write access to gitlab API (requred)
    -G, --gitlab-group     gitlab group where find projects
    -A, --all-projects     delete pipeline in all projects
    -a, --archive          delete pipeline from all archived project
    -S, --pipeline-source  pipeline source: schedule, push, web, trigger, api, external, pipeline,
                                            chat, webide, merge_request_event, external_pull_request_event,
                                            parent_pipeline, ondemand_dast_scan, or ondemand_dast_validation.
    -F, --pipeline-status  pipeline status: created, waiting_for_resource, preparing, pending, running,
                                            success, failed, canceled, skipped, manual, scheduled
    -D, --before-days      keep pipeline for last D days
    -N, --keep-pipelines   keep last N pipeline
    -v, --verbose          Verbose mode, more -v flags bring more details
    -h, --help             print help
"
}
# Getopts
getopt -T; (( $? == 4 )) || { echo "incompatible getopt version" >&2; exit 4; }

if ! TEMP=$(getopt -o g:t:G:S:D:N:F:Aavh --longoptions gitlab-url:,token:,gitlab-group:,pipeline-source:,pipeline-status:,before-days:,keep-pipelines:,all-projects,archive,verbose,help -n "$bn" -- "$@")
then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
    case $1 in
        -g|--gitlab-url)                GITLAB_URL=$2 ;                     shift 2 ;;
        -t|--token)                     GITLAB_TOKEN=$2 ;                   shift 2 ;;
        -G|--gitlab-group)              GITLAB_GROUP="/groups/${2//\//%2f}" ;         shift 2 ;;
        -A|--all-projects)              GITLAB_GROUP="//" ;                 shift ;;
        -a|--archive)                   SELECT_ARCHIVED_PROJECT="archived=true" ;
                                        ARCHIVE_PROJECT=1 ;
                                        GITLAB_GROUP="//" ;                 shift ;;
        -S|--pipeline-source)           PIPELINE_SOURCE="&source=$2" ;      shift 2 ;;
        -F|--pipeline-status)           PIPELINE_STATUS="&status=$2" ;      shift 2 ;;
        -D|--before-days)               DELETE_BEFORE=$(/bin/date --date="$2 days ago" +%Y-%m-%d);
                                        PIPELINE_DELETE_BEFORE="&updated_before=${DELETE_BEFORE}T00:00:00.000Z" ;      shift 2 ;;
        -N|--keep-pipelines)            KEEP_PIPELINES=$2 ;                 shift 2 ;;
        -v|--verbose)                   VERBOSE=$((VERBOSE + 1 )) ;         shift   ;;
        -h|--help)                      usage ;         exit 0  ;;
        --)                             shift ;         break   ;;
        *)                              usage ;         exit 1
    esac
done

echo_err()      { tput setaf 7; echo "* ERROR: $*" ;   tput sgr0;   }
echo_fatal()    { tput setaf 1; echo "* FATAL: $*" ;   tput sgr0;   }
echo_warn()     { tput setaf 3; echo "* WARNING: $*" ; tput sgr0;   }
echo_info()     { tput setaf 6; echo "* INFO: $*" ;    tput sgr0;   }
echo_info_n()   { tput setaf 6; echo -n "* INFO: $*" ; tput sgr0;   }
echo_debug()    { tput setaf 4; echo "* DEBUG: $*" ;   tput sgr0;   }
echo_ok()       { tput setaf 2; echo "* OK" ;          tput sgr0;   }

main
