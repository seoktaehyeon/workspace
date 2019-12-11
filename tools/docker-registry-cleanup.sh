#!/bin/bash
# Author: v.stone@163.com
# ./docker-registry-cleanup.sh http://127.0.0.1 admin:password
#set -ex

REGISTRY_HOST=${1?"Please provide registry host url, e.g. http://127.0.0.1"}
REGISTRY_AUTH=${2?"Please provide registry authorization, e.g. admin:password"}
TAG_POLICY=${3-"count=5"}
DEBUG=${4-""}
TEMP_FILE='.gc-registry.tmp'

OS_TYPE=$(uname)

if [[ -n $(echo "${TAG_POLICY}" | grep -i 'count=') ]]; then
    TAG_COUNT=$(echo "${TAG_POLICY}" | awk -F '=' '{print $2}')
elif [[ -n $(echo "${TAG_POLICY}" | grep -i 'days=') ]]; then
    TAG_DAYS=$(echo "${TAG_POLICY}" | awk -F '=' '{print $2}')
    if [[ "${OS_TYPE}" == "Linux" ]]; then
        TAG_TIME=$(date -d "-${TAG_DAYS}days" +%Y-%m-%d-%H-%M)
    elif [[ "${OS_TYPE}" == "Darwin" ]]; then
        TAG_TIME=$(date -v -${TAG_DAYS}d +%Y-%m-%d-%H-%M)
    else
        echo "OS is not support"
        exit 1
    fi
else
    echo "Please provide tag policy, e.g. count=5 or days=7"
    exit 1
fi

CURL='curl -s'
echo "${REGISTRY_HOST}" | grep -q 'https://' && CURL='curl -s -k'

function log_debug
{
    if [[ "${DEBUG}" == "debug" ]]; then
        echo -e "$@" 1>&2
    fi
    return 0
}

function log_note
{
    echo -e "$@" 1>&2
    return 0
}

# Usage: format_output <output>
# Output: formated_text
function format_output
{
    output=$1
    if [[ "${OS_TYPE}" == "Linux" ]]; then
        echo "${output}" | sed 's/,/\n/g'
    elif [[ "${OS_TYPE}" == "Darwin" ]]; then
        echo "${output}" | sed 's/,/\'$'\n/g'
    else
        exit 1
    fi
    return 0
}

# Usage: _get_token_url <url> <method>
# Output: token_url
function _get_token_url
{
    url=${1?}
    method=${2-'GET'}
    log_debug "${CURL} -X ${method} --head ${url}"
    output=$(${CURL} -X ${method} --head "${url}")
    echo "${output}" | head -1 | grep -q '401' || {
        echo "${output}"
        exit 1
    }
    bearer=$(echo "${output}" | grep -i 'www-authenticate' | grep -i 'bearer' | awk '{print $NF}')
    bearer_realm=$(format_output "${bearer}" | grep 'realm=' | awk -F '"' '{print $2}')
    bearer_service=$(format_output "${bearer}" | grep 'service=' | awk -F '"' '{print $2}')
    bearer_scope=$(format_output "${bearer}" | grep 'scope=' | awk -F '"' '{print $2}')
    log_debug "REALM: ${bearer_realm}"
    log_debug "SERVICE: ${bearer_service}"
    log_debug "SCOPE: ${bearer_scope}"
    echo "${bearer_realm}?service=${bearer_service}&scope=${bearer_scope}"
    log_debug "Succeed to get bearer info"
    return 0
}

# Usage: _get_token <url> <method>
# Output: auth_token
function _get_token
{
    url=${1?}
    method=${2-'GET'}
    token_url=$(_get_token_url "${url}" "${method}")
    log_debug "${CURL} -X -u '${REGISTRY_AUTH}' '${token_url}'"
    output=$(${CURL} -u ${REGISTRY_AUTH} "${token_url}")
    echo "${output}" | grep -q 'token' || {
        echo "${output}"
        exit 1
    }
    log_debug "200 OK"
    auth_token=$(echo ${output} | grep 'token' | awk -F '"' '{print $4}')
    if [[ "${auth_token}" == "" ]]; then
        echo "Cannot Get Authorization Token"
        exit 1
    else
        log_debug "Succeed to get authorization token"
        echo "${auth_token}"
        return 0
    fi
}

# Usage: get_repositories
# Output: repositories_list
function get_repositories
{
    url="${REGISTRY_HOST}/v2/_catalog"
    log_note "\nGet Repositories: ${url}"
    token=$(_get_token "${url}")
    log_debug "${CURL} -H 'Authorization: Bearer ${token}' ${url}"
    output=$(${CURL} -H "Authorization: Bearer ${token}" "${url}")
    echo "${output}" | grep -q 'repositories' || {
        echo "${output}"
        exit 1
    }
    log_note "200 OK"
    repo_str=$(echo "${output}" | grep 'repositories' | awk -F '[' '{print $2}' | awk -F ']' '{print $1}')
    repos=$(format_output "${repo_str}" | sed 's/"//g')
    log_note "${repos}"
    echo "${repos}"
    return 0
}

# Usage: get_tags <repo_name>
# Output: tags_list
function get_tags
{
    repo_name=${1?}
    url="${REGISTRY_HOST}/v2/${repo_name}/tags/list"
    log_note "\nGet Tags: ${url}"
    token=$(_get_token "${url}")
    log_debug "${CURL} -H 'Authorization: Bearer ${token}' ${url}"
    output=$(${CURL} -H "Authorization: Bearer ${token}" "${url}")
    echo "${output}" | grep -q 'tags' || {
        echo "${output}"
        exit 1
    }
    log_note "200 OK"
    tags_str=$(echo "${output}" | grep 'tags' | awk -F '[' '{print $2}' | awk -F ']' '{print $1}')
    tags=$(format_output "${tags_str}" | sed 's/"//g')
    log_debug "Total: $(echo "${tags}" | wc -l)"
    log_note "${tags}"
    echo "${tags}"
    return 0
}

# Usage: get_digest <repo_name> <tag>
# Output: digest
function get_digest
{
    repo_name=${1?}
    tag=${2?}
    url="${REGISTRY_HOST}/v2/${repo_name}/manifests/${tag}"
    log_note "\nGet Digest: ${url}"
    token=$(_get_token "${url}")
    log_debug "${CURL} --head -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -H 'Authorization: Bearer ${token}' '${url}'"
    output=$(${CURL} --head -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -H "Authorization: Bearer ${token}" "${url}" 2>&1)
    echo "${output}" | grep -qi 'docker-content-digest' || {
        echo "${output}"
        exit 1
    }
    log_note "200 OK"
    digest=$(echo "${output}" | grep -i 'docker-content-digest' | awk '{print $NF}' | awk -F '\r' '{print $1}')
    log_debug "DIGEST: ${digest}"
    log_note "${digest}"
    echo "${digest}"
    return 0
}

# Usage: get_created_time <repo_name> <tag>
# Output: created_time
function get_created_time
{
    repo_name=${1?}
    tag=${2?}
    url="${REGISTRY_HOST}/v2/${repo_name}/manifests/${tag}"
    log_note "\nGet Created Date: ${url}"
    token=$(_get_token "${url}")
    log_debug "${CURL} -H 'Authorization: Bearer ${token}' '${url}'"
    output=$(${CURL} -H "Authorization: Bearer ${token}" "${url}" 2>&1)
    echo "${output}" | grep -qi '"history"' || {
        echo "${output}"
        exit 1
    }
    log_note "200 OK"
    created_time_str=$(echo "${output}" | grep -i '"history"' -A 2 | tail -1 | sed 's/.*created//' | awk -F '[".]' '{print $3}')
    if [[ "${OS_TYPE}" == "Linux" ]]; then
        created_time=$(date -d "${created_time_str}" +%Y-%m-%d-%H-%M)
    elif [[ "${OS_TYPE}" == "Darwin" ]]; then
        created_time=$(date -j -f %Y-%m-%dT%H:%M "${created_time_str}" +%Y-%m-%d-%H-%M)
    fi
    log_debug "CREATED DATE: ${created_time}"
    log_note "${created_time}"
    echo "${created_time}"
    return 0
}

# Usage: delete_digest <repo_name> <digest>
# Output: None
function delete_digest
{
    url="${REGISTRY_HOST}/v2/${1}/manifests/${2}"
    log_note "\nDelete Digest: ${url}"
    token=$(_get_token "${url}" "DELETE")
    log_debug "${CURL} -X DELETE -H 'Authorization: Bearer ${token}' '${url}'"
    output=$(${CURL} -X DELETE -H "Authorization: Bearer ${token}" "${url}")
    [[ -z "${output}" ]] && {
        log_note "202 DELETED"
        return 0
    }
    echo "${output}"
    exit 1
}


## Main
for repo in $(get_repositories)
do
    # Recreate temp file
    [[ -f ${TEMP_FILE} ]] && rm -rf ${TEMP_FILE}
    # Get all tags of the repo
    tags=$(get_tags ${repo})
    if [[ -n "${TAG_COUNT}" ]]; then
        # If tags less than $TAG_COUNT, no need to do anything
        (( $(echo "${tags}" | wc -l) <= ${TAG_COUNT} )) && continue
        for tag in ${tags}
        do
            # Get digest
            digest=$(get_digest ${repo} ${tag})
            # Get create time
            created_time=$(get_created_time ${repo} ${tag})
            # Append created time and digest into temp file
            echo ${created_time} ${digest} >> ${TEMP_FILE}
        done
        all_digest=$(cat ${TEMP_FILE} | sort -k 1 -r | uniq)
        # Get latest 5 digests from temp file
        latest_digest=$(echo "${all_digest}" | sed -n "1,${TAG_COUNT}p" | awk '{print $2}')
        # Get overdue digest list from temp file
        overdue_digest=$(echo "${all_digest}" | sed -n "$(( $TAG_COUNT + 1 )),\$p" | awk '{print $2}')
    elif [[ -n "${TAG_DAYS}" ]]; then
        for tag in ${tags}
        do
            # Get digest
            digest=$(get_digest ${repo} ${tag})
            # Get create time
            created_time=$(get_created_time ${repo} ${tag})
            # Append created time and digest into temp file
            echo ${created_time} ${digest} >> ${TEMP_FILE}
        done
        # Append TAG_TIME into temp file and sort digest list
        echo "${TAG_TIME} ==GC-REGISTRY==" >> ${TEMP_FILE}
        # Sort digest list and get gc registry line
        all_digest=$(cat ${TEMP_FILE} | sort -k 1 | uniq)
        gc_registry_line=$(echo "${all_digest}" | grep -n '==GC-REGISTRY==' | awk -F ':' '{print $1}')
        # If all tags within $TAG_DAYS, no need to do anything
        (( ${gc_registry_line} == 1 )) && continue
        # Get latest digests from temp file
        latest_digest=$(echo "${all_digest}" | sed -n "$(( ${gc_registry_line} + 1 )),\$p" | awk '{print $2}')
        # Get overdue digest list from temp file
        overdue_digest=$(echo "${all_digest}" | sed -n "1,$(( ${gc_registry_line} - 1 ))p" | awk '{print $2}')
    else
        echo "There is some mistake during run this scripts"
        exit 1
    fi
    for check_digest in ${overdue_digest}
    do
        # If overdue digest is not in latest digest list, delete it
        echo "${latest_digest}" | grep -q "${check_digest}" || delete_digest "${repo}" "${check_digest}"
    done
    [[ -f ${TEMP_FILE} ]] && rm -rf ${TEMP_FILE}
done
