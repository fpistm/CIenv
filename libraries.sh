#!/bin/bash -
#===============================================================================
#
#         USAGE: ./updateLibraries.sh
#
#   DESCRIPTION: Update all stm32duino libraries from all git repositories found
#                on the STM32duino GitHub organization to the master
#
#        AUTHOR: Frederic Pillon
#  ORGANIZATION: STMicroelectronics
#     COPYRIGHT: Copyright (C) 2020, STMicroelectronics - All Rights Reserved
#===============================================================================

set -o nounset # Treat unset variables as an error
# set -x
# Path
local_lib_repo_path="$HOME/repo/libraries"

# Config
repoListFile="listOfRepo.txt"
gh_api="https://api.github.com/users/stm32duino/repos?per_page=100"

# Get list of repo
curl -s "$gh_api" | jq '.[]|.html_url' | grep -v -f excludeList.txt | sed -e "s/\"//g" >$repoListFile
ret="${PIPESTATUS[0]}"
if [ "$ret" -ne 0 ]; then
  echo "[$0] Could not retrieve repository list. Abort."
  exit "$ret"
fi
readarray -t git_list <$repoListFile

if [ ${#git_list[@]} -eq 0 ]; then
  echo "[$0] No library found. Abort."
  exit 1
else
  echo "Number of libraries found: ${#git_list[@]}"
fi

if [ ! -d "$local_lib_repo_path" ]; then
  mkdir "$local_lib_repo_path"
fi

for git_repo in "${git_list[@]}"; do
  git_name=$(basename "$git_repo")
  git_dir=$local_lib_repo_path/$git_name
  if [ -d "$git_dir/.git" ]; then
    rname=$(git -C "$git_dir" remote -v | grep stm32duino | awk '{print $1}' | sort -u)
    if [ ! -z "$rname" ]; then
      echo "Updating remote $rname of $git_name..."
      if output=$(git -C "$git_dir" fetch "$rname" 2>&1) && [ ! -z "$output" ]; then
        # Fetch some commits
        if output=$(git -C "$git_dir" status --porcelain) && [ -z "$output" ]; then
          # Working directory clean
          if output=$(git -C "$git_dir" log "${rname}/master..master") && [ -z "$output" ]; then
            # No local commit
            git -C "$git_dir" checkout -B master "${rname}/master"
          else
            echo "Not updated --> local commit(s) not pushed"
            echo "$output"
          fi
        else
          echo "Not updated --> uncommitted change(s) or untracked file(s)"
          echo "$output"
        fi
        echo "done"
      else
        echo "Nothing to update"
      fi
      echo ""
    fi
    cd ..
  else
    git -C "$local_lib_repo_path" clone "$git_repo"
  fi
done
