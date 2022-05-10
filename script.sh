#!/bin/bash -x

set -e

fn_mergefail() {
  echo "--- Git Merge Operation has failed. Please Investigate. ---"
  exit 1
}

fn_create_pr() {
  export TITLE="Merge remote-tracking branch 'origin/"$SOURCE"' into $DESTINATION"
  export BODY="Merge remote-tracking branch 'origin/"$SOURCE"' into $DESTINATION"
  export HEAD="$SOURCE"
  export DEFAULT_REVIEWERS='"akatamreddy-cs", "clkelly", "rsaintcyr-creditshop", "atati-cs", "rsrinivasan-cs"'

  echo "--- Checking if a PR is required ---"

  if [[ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]]; then
    echo "--- Remote and Checked out branch are different. Creating a PR ---"

    curl -X POST -u "builduser-creditshop:${BUILDUSER_TOKEN}" \
    -H "Content-Type: application/json" -H "Accept: application/vnd.github.v3+json" \
    -d "{ \"title\": \"${TITLE}\", \"body\": \"${BODY}\", \"head\": \"${HEAD}\", \"base\": \"${DESTINATION}\" }" \
    "https://api.github.com/repos/CreditShop/lendingplatform/pulls" | tee "/tmp/lendingplatform_pr"

    # Handle the case where PR already exists for a branch but needs updates with new commits
    if [[ $(jq .message /tmp/lendingplatform_pr) == '"Validation Failed"' ]]; then
      if [[ $(jq '.errors | .[].message' /tmp/lendingplatform_pr) == *"A pull request already exists for"* ]]; then
        echo "--- Issuing another API call to update the Pull Request ---"
        # Get the PR number for the branch by searching the current pulls
        curl -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/Creditshop/lendingplatform/pulls" -u "builduser-creditshop:${BUILDUSER_TOKEN}" > "/tmp/lendingplatform_plist"
        # The JSON response contains just the base branch name, without the "origin/" part
        J_SOURCE=$(echo ${SOURCE} | cut -d "/" -f 2)
        OPEN_PR_NUM=$(jq --arg J_SOURCE $J_SOURCE '.[] | select (.head.ref == $J_SOURCE) | .number' "/tmp/lendingplatform_plist")
        EXPECTED_SHA=$(jq --arg J_SOURCE $J_SOURCE '.[] | select (.head.ref == $J_SOURCE) | .head.sha' "/tmp/lendingplatform_plist")
        curl -u "builduser-creditshop:${BUILDUSER_TOKEN}" -X PUT -H "Accept: application/vnd.github.lydian-preview+json" \
        "https://api.github.com/repos/Creditshop/lendingplatform/pulls/${OPEN_PR_NUM}/update-branch" -d "{ \"expected_head_sha\":\"${EXPECTED_SHA}\" }"
      fi

    # Regular case of creating a new PR
    else
      export PR_NUM=$(jq .number "/tmp/lendingplatform_pr")
      echo "--- Setting default reviewers for the PR #${PR_NUM} created ---"
      curl -X POST -v -u "builduser-creditshop:${BUILDUSER_TOKEN}" \
      -H "Content-Type: application/json" -H "Accept: application/vnd.github.v3+json" \
      -d "{ \"reviewers\":[$DEFAULT_REVIEWERS] }" \
      "https://api.github.com/repos/CreditShop/lendingplatform/pulls/${PR_NUM}/requested_reviewers"
    fi

  else
    echo "--- Remote and checked out branch are the same. No PR is required ---"

  fi
}

echo "--- List of release branches ---"
git ls-remote --heads origin "release-*-CM*" | awk -F "/" '{print $NF}' | tee "/tmp/lp_rel_branches"

next_release_branch=$(cat "/tmp/lp_rel_branches" | tail -1)
current_release_branch=$(cat "/tmp/lp_rel_branches" | tail -2 | head -1)
previous_release_branch=$(cat "/tmp/lp_rel_branches" | tail -3 | head -1)
penultimate_release_branch=$(cat "/tmp/lp_rel_branches" | tail -4 | head -1)

echo "----------------------------------------------------------------------"
echo "next_release_branch is: $next_release_branch"
echo "current_release_branch is: $current_release_branch"
echo "previous_release_branch is: $previous_release_branch"
echo "penultimate_release_branch is: $penultimate_release_branch"
echo "----------------------------------------------------------------------"

echo "--- Starting Merge ---"

echo "--- Merging $penultimate_release_branch to $previous_release_branch ---"
export SOURCE=$penultimate_release_branch
export DESTINATION=$previous_release_branch
git checkout $previous_release_branch
git pull
git merge --no-edit "origin/$penultimate_release_branch" || fn_mergefail
fn_create_pr

echo "--- Merging $previous_release_branch to $current_release_branch ---"
export SOURCE=$previous_release_branch
export DESTINATION=$current_release_branch
git checkout $current_release_branch
git pull
git merge --no-edit "origin/$previous_release_branch" || fn_mergefail
fn_create_pr

echo "--- Merging $current_release_branch to $next_release_branch ---"
export SOURCE=$current_release_branch
export DESTINATION=$next_release_branch
git checkout $next_release_branch
git pull
git merge --no-edit "origin/$current_release_branch" || fn_mergefail
fn_create_pr

echo "--- Merging $next_release_branch to develop ---"
export SOURCE=$next_release_branch
export DESTINATION="develop"
git checkout develop
git pull
git merge --no-edit "origin/$next_release_branch" || fn_mergefail
fn_create_pr
