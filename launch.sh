#!/bin/bash
set -o nounset # Treat unset variables as an error
set +x

# env
gh_url="https://github.com/stm32duino/Arduino_Core_STM32.git"
git_name=$(basename "$gh_url")
repo_root_path="$HOME/repo"
repo_name=${git_name%.git}
repo_path="$repo_root_path/$repo_name"
cli_core_path="$HOME/.arduino15/packages/STMicroelectronics/hardware/stm32"
core_build_path="$repo_path/CI/build"
json_path="$core_build_path/path_config.json"
builder_name="arduino-cli.py"
build_param=()

# Exported environment variables set to default value if unset
BUILD_ALL_SKETCHES=${BUILD_ALL_SKETCHES:-false}
BOARD_PATTERN=${BOARD_PATTERN:-""}
SKETCH_FILEPATH=${SKETCH_FILEPATH:-""}
SKETCH_LIST_FILEPATH=${SKETCH_LIST_FILEPATH:-""}
SKETCH_PATTERN=${SKETCH_PATTERN:-""}
PR_NUMBER=${PR_NUMBER:-""}

# Fetch GitHub repo
if [ ! -d "$repo_root_path" ]; then
  mkdir -p "$repo_root_path"
fi
if [ -z "$repo_path" ]; then
  echo "Error unknown repository path."
  exit 1
fi
if [ -d "$repo_path" ] && [ ! -d "$repo_path/.git" ]; then
  rm -fr "${repo_path:?}"
fi
if [ ! -d "$repo_path/.git" ]; then
  # Clone
  echo "Cloning $git_name..."
  git -C "$repo_root_path" clone "$gh_url"
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "Could not clone $gh_url."
    exit $status
  fi
else
  # Update and clean
  rname=$(git -C "$repo_path" remote -v | grep stm32duino | awk '{print $1}' | sort -u)
  if [ ! -z "$rname" ]; then
    echo "Updating remote $rname of $git_name..."
    # Clean up repo
    echo "Clean up $repo_path"
    if git -C "$repo_path" clean -fdx > /dev/null 2>&1; then
      if git -C "$repo_path" fetch "$rname" > /dev/null 2>&1; then
        if git -C "$repo_path" reset --hard "$rname/main" > /dev/null 2>&1; then
          if git -C "$repo_path" checkout -B main "${rname}/main" > /dev/null 2>&1; then
            # Delete all local branch if any
            nb_local=$(git -C "$repo_path" branch -l | wc -l)
            if [ "$nb_local" -gt 1 ]; then
              git -C "$repo_path" branch -l | grep -v "main" | xargs git -C "$repo_path" branch -D
            fi
            echo "done"
          else
            echo "Failed to checkout main $git_name"
            exit 4
          fi
        else
          echo "Could not reset hard $git_name."
          exit 3
        fi
      else
        echo "Could not fetch $rname."
        exit 2
      fi
    else
      echo "Could not clean $git_name."
      exit 1
    fi
  fi
fi

# Fetch Pull Request if any
if [ ! -z "${PR_NUMBER}" ]; then
  rname=$(git -C "$repo_path" remote -v | grep stm32duino | awk '{print $1}' | sort -u)
  echo "Fetch Pull Request #$PR_NUMBER"
  if git -C "$repo_path" fetch -fu "$rname" refs/pull/"${PR_NUMBER}"/head:pr/"${PR_NUMBER}" > /dev/null 2>&1; then
    if git -C "$repo_path" checkout pr/"${PR_NUMBER}" > /dev/null 2>&1; then
      echo "done"
    else
      echo "Failed to checkout pr/${PR_NUMBER}"
      exit 7
    fi
  else
    echo"Could not fetch Pull Request #$PR_NUMBER"
    exit 8
  fi
fi

# Link the repo to the arduino-cli
if ! arduino-cli core list | grep "STMicroelectronics" > /dev/null 2>&1; then
  echo "STM32 core is not installed."
  exit 5
fi
core_version=$(arduino-cli core list | grep "STMicroelectronics" | cut -d ' ' -f2)
if [ -z "$core_version" ]; then
  echo "Undefined STM32 core version."
  exit 6
fi
# Handle core vesion link in arduino-cli
if [ -L "$cli_core_path/$core_version" ]; then
  rm "$cli_core_path/$core_version"
elif [ -e "$cli_core_path/$core_version" ]; then
  rm -fr "${cli_core_path:?}/${core_version:?}"
fi
ln -s "$repo_path" "$cli_core_path/$core_version"

# Handle path_config for build script
# Call the script once to create it
if [ ! -f "$json_path" ]; then
  python "$core_build_path/$builder_name" -l > /dev/null 2>&1
fi

# Parameters
if [ "${BUILD_ALL_SKETCHES}" = true ]; then
  build_param=(-a)
fi

if [ ! -z "${BOARD_PATTERN}" ]; then
  build_param+=(-b "${BOARD_PATTERN}")
fi

if [ ! -z "${SKETCH_FILEPATH}" ]; then
  build_param+=(-i "${SKETCH_FILEPATH}")
fi

if [ ! -z "${SKETCH_LIST_FILEPATH}" ]; then
  build_param+=(-f "${SKETCH_LIST_FILEPATH}")
fi

if [ ! -z "${SKETCH_PATTERN}" ]; then
  build_param+=(-s "${SKETCH_PATTERN}")
fi

if [ ${#build_param[@]} -eq 0 ]; then
  echo "BUILD starts without any paramater."
else
  echo "BUILD starts with the following parameters:"
  echo "${build_param[*]}"
fi
python "$core_build_path/$builder_name" "${build_param[@]}"
