#!/bin/bash
# ./docker-registry-tool.sh http://127.0.0.1 admin:password
#set -ex

REGISTRY_HOST=${1?"Please provide registry host url, e.g. http://127.0.0.1"}
REGISTRY_AUTH=${2?"Please provide registry authorization, e.g. admin:password"}
DEBUG=${3-""}

CURL='curl -s'
echo "${REGISTRY_HOST}" | grep -q 'https://' && CURL='curl -s -k'
BEARER=""
BEARER_REALM=""
BEARER_SERVICE=""
BEARER_SCOPE=""
REPOS=""
TAGS=""

function log_debug
{
    if [[ "${DEBUG}" == "debug" ]]; then
        echo "$@" 1>&2
    fi
    return 0
}

# Usage: format_output <output>
function format_output
{
    output=$1
    if [[ "$(uname)" == "Linux" ]]; then
        echo "${output}" | sed 's/,/\n/g'
    else
        echo "${output}" | sed 's/,/\'$'\n/g'
    fi
    return 0
}

# Usage: _get_token_url <url>
function _get_token_url
{
    url=${1?}
    log_debug "${CURL} --head ${url}"
    output=$(${CURL} --head "${url}" 2>&1)
    echo "${output}" | grep -q '401' || {
        echo "${output}"
        exit 1
    }
    bearer=$(echo "${output}" | grep 'Bearer' | awk '{print $NF}')
    bearer_realm=$(echo "${bearer}" | awk -F 'realm=' '{print $2}' | awk -F '"' '{print $2}')
    bearer_service=$(echo "${bearer}" | awk -F 'service=' '{print $2}' | awk -F '"' '{print $2}')
    bearer_scope=$(echo "${bearer}" | awk -F 'scope=' '{print $2}' | awk -F '"' '{print $2}')
    log_debug "REALM: ${bearer_realm}"
    log_debug "SERVICE: ${bearer_service}"
    log_debug "SCOPE: ${bearer_scope}"
    echo "${bearer_realm}?service=${bearer_service}&scope=${bearer_scope}"
    log_debug "Succeed to get bearer info"
    return 0
}

# Usage: _get_token <url>
function _get_token
{
    url=${1?}
    token_url=$(_get_token_url "${url}")
    log_debug "${CURL} -u '${REGISTRY_AUTH}' '${token_url}'"
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

function get_repositories
{
    url="${REGISTRY_HOST}/v2/_catalog"
    echo -e "\nGet Repositories: ${url}"
    token=$(_get_token "${url}")
    log_debug "${CURL} -H 'Authorization: Bearer ${token}' ${url}"
    output=$(${CURL} -H "Authorization: Bearer ${token}" "${url}")
    echo "${output}" | grep -q 'repositories' || {
        echo "${output}"
        exit 1
    }
    log_debug "200 OK"
    repo_str=$(echo "${output}" | grep 'repositories' | awk -F '[' '{print $2}' | awk -F ']' '{print $1}')
    REPOS=$(format_output "${repo_str}" | sed 's/"//g')
    echo "${REPOS}"
    return 0
}

# Usage: get_tags <repo_name>
function get_tags
{
    repo_name=${1?}
    url="${REGISTRY_HOST}/v2/${repo_name}/tags/list"
    echo -e "\nGet Tags: ${url}"
    token=$(_get_token "${url}")
    log_debug "${CURL} -H 'Authorization: Bearer ${token}' ${url}"
    output=$(${CURL} -H "Authorization: Bearer ${token}" "${url}")
    echo "${output}" | grep -q 'tags' || {
        echo "${output}"
        exit 1
    }
    log_debug "200 OK"
    tags_str=$(echo "${output}" | grep 'tags' | awk -F '[' '{print $2}' | awk -F ']' '{print $1}')
    TAGS=$(format_output "${tags_str}" | sed 's/"//g')
    echo "${TAGS}"
    return 0
}

# Usage: get_digest <repo_name> <tag>
function get_digest
{
    repo_name=${1?}
    tag=${2?}
    url="${REGISTRY_HOST}/v2/${repo_name}/manifests/${tag}"
    token=$(_get_token "${url}")
    log_debug "${CURL} -v -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -H 'Authorization: Bearer ${token}' '${url}'"
    output=$(${CURL} -v -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -H "Authorization: Bearer ${token}" "${url}" 2>&1)
    echo "${output}" | grep -qi 'Docker-Content-Digest' || {
        echo "${output}"
        exit 1
    }
    log_debug "200 OK"
    digest=$(echo "${output}" | grep -i 'Docker-Content-Digest' | awk '{print $NF}' | awk -F '\r' '{print $1}')
    log_debug "DIGEST: ${digest}"
    echo "${digest}"
    return 0
}

# Usage: delete_tag <digest>
function delete_tag
{
    url="${REGISTRY_HOST}/v2/${repo_name}/manifests/${1}"
    token=$(_get_token "${url}")
    log_debug "${CURL} -v -X DELETE -H 'Authorization: Bearer ${token}' '${url}'"
    exit 0
    output=$(${CURL} -v -X DELETE -H "Authorization: Bearer ${token}" "${url}" 2>&1)
    echo "${output}" | grep -q '202' || {
        echo "${output}"
        exit 1
    }
    log_debug "202 DELETED"
    return 0
}


## Main
get_repositories
for repo in ${REPOS}
do
    get_tags ${repo}
    tag_count=0
    for tag in ${TAGS}
    do
        tag_count=$(( $tag_count + 1 ))
        (( $tag_count < 6 )) && continue
        echo "more than 5"
        digest=$(get_digest "${repo}" "${tag}")
        echo "Fake delete it" && continue
        delete_tag "${digest}"
    done
done