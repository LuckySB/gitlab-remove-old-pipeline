== Remove old pipeline from Gitlab CI

set environment variable GITLAB_URL and GITLAB_TOKEN

    Usage: gitlab-remove-old-pipeline.sh <OPTIONS>

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
    -v, --verbose          Verbose mode
    -h, --help             print help
