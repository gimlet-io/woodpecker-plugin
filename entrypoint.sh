#!/usr/bin/env bash

if [[ "$PLUGIN_DEBUG" == "true" ]]; then
    set -eo xtrace
else
    set -e
fi

pwd

git version
git config --global --add safe.directory /github/workspace

echo "Creating artifact.."

COMMIT_MESSAGE=$(git log -1 --pretty=%B)
COMMIT_AUTHOR=$(git log -1 --pretty=format:'%an')
COMMIT_AUTHOR_EMAIL=$(git log -1 --pretty=format:'%ae')
COMMIT_COMITTER=$(git log -1 --pretty=format:'%cn')
COMMIT_COMITTER_EMAIL=$(git log -1 --pretty=format:'%ce')
COMMIT_CREATED=$(git log -1 --format=%cI)

BRANCH=${CI_COMMIT_SOURCE_BRANCH}

EVENT="push"
SHA=$CI_COMMIT_SHA
URL=$CI_COMMIT_LINK

if [[ "$CI_BUILD_EVENT" == "pull_request" ]]; then
    EVENT="pr"
    SHA=$CI_COMMIT_SHA
    SOURCE_BRANCH=$CI_COMMIT_SOURCE_BRANCH
    TARGET_BRANCH=$CI_COMMIT_TARGET_BRANCH
    PR_NUMBER=$CI_COMMIT_PULL_REQUEST
    URL="TODO PR URL"
fi

if [[ "$CI_BUILD_EVENT" == "tag" ]]; then
    TAG=$CI_COMMIT_TAG
    EVENT="tag"
fi

gimlet artifact create \
--repository "$CI_REPO" \
--sha "$SHA" \
--created "$COMMIT_CREATED" \
--branch "$BRANCH" \
--event "$EVENT" \
--sourceBranch "$SOURCE_BRANCH" \
--targetBranch "$TARGET_BRANCH" \
--tag "$TAG" \
--authorName "$COMMIT_AUTHOR" \
--authorEmail "$COMMIT_AUTHOR_EMAIL" \
--committerName "$COMMIT_COMITTER" \
--committerEmail "$COMMIT_COMITTER_EMAIL" \
--message "$COMMIT_MESSAGE" \
--url "$URL" \
> artifact.json

echo "Attaching Gimlet manifests.."
for file in .gimlet/*
do
    if [[ -f $file ]]; then
    gimlet artifact add -f artifact.json --envFile $file
    fi
done

echo "Attaching environment variable context.."
VARS=$(printenv | grep CI_ | grep -v '=$' | awk '$0="--var "$0')
gimlet artifact add -f artifact.json $VARS

echo "Attaching common Gimlet variables.."
gimlet artifact add \
-f artifact.json \
--var "REPO=$CI_REPO" \
--var "OWNER=$CI_REPO_OWNER" \
--var "BRANCH=$BRANCH" \
--var "TAG=$TAG" \
--var "SHA=$CI_COMMIT_SHA" \
--var "ACTOR=" \
--var "EVENT=$CI_BUILD_EVENT" \
--var "JOB=$CI_BUILD_NUMBER"

if [[ "$PLUGIN_DEBUG" == "true" ]]; then
    cat artifact.json
    exit 0
fi

echo "Shipping artifact.."
ARTIFACT_ID=$(gimlet artifact push -f artifact.json --output json | jq -r '.id' )
if [ $? -ne 0 ]; then
    echo $ARTIFACT_ID
    exit 1
fi

echo "Shipped artifact ID is: $ARTIFACT_ID"

if [[ -z "$PLUGIN_TIMEOUT" ]];
then
    PLUGIN_TIMEOUT=10m
fi

if [[ "$PLUGIN_WAIT" == "true" || "$PLUGIN_DEPLOY" == "true" ]]; then
    gimlet artifact track --wait --timeout $PLUGIN_TIMEOUT $ARTIFACT_ID
else
    gimlet artifact track $ARTIFACT_ID
fi

if [[ "$PLUGIN_DEPLOY" == "true" ]]; then
    echo "Deploying.."
    RELEASE_ID=$(gimlet release make --artifact $ARTIFACT_ID --env $PLUGIN_ENV --app $PLUGIN_APP --output json | jq -r '.id')
    echo "Deployment ID is: $RELEASE_ID"
    gimlet release track --wait --timeout $PLUGIN_TIMEOUT $RELEASE_ID
fi
