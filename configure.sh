#!/bin/bash -
#===============================================================================
#
#          FILE: configure.sh
#
#         USAGE: ./configure.sh
#
#   DESCRIPTION: Install or update the CI environnement
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Frederic Pillon (), frederic.pillon@st.com
#  ORGANIZATION: MCU Embedded Software
#     COPYRIGHT: Copyright (c) 2020, Frederic Pillon
#       CREATED: 04/10/2020 10:20:09 AM
#      REVISION:  ---
#===============================================================================

set -o nounset # Treat unset variables as an error

# env
bin_path="$HOME/bin"
lib_repo_path="$HOME/repo/libraries"
arduino_lib_path="$HOME/Arduino/libraries"

repoListFile="listOfRepo.txt"
libListFile="libraries.txt"

gh_api="https://api.github.com/users/stm32duino/repos?per_page=100"
gh_cli="https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh"
gh_stm32="https://github.com/stm32duino/BoardManagerFiles/raw/master/STM32/package_stm_index.json"

cli="arduino-cli"
cli_path="$bin_path/$cli"

IDE_version="1.8.12"
IDE_name="arduino-$IDE_version"
IDE_path="$HOME/IDE/$IDE_name"
IDE_archive="arduino-$IDE_version-linux64.tar.xz"
IDE_url="http://downloads.arduino.cc/$IDE_archive"

doCli=0
doUpdate=0

me=$(basename "$0")

###############################################################################
## Help function
usage() {
  echo "############################################################"
  echo "##"
  echo "## $me"
  echo "## [-a] [-u]"
  echo "##"
  echo "## Launch this script at the top of Arduino IDE directory."
  echo "##"
  echo "## Mandatory options:"
  echo "##"
  echo "## None"
  echo "##"
  echo "## Optionnal:"
  echo "##"
  echo "## -a: install all requirements and configure all environnement."
  echo "## -u: update the environnement"
  echo "##"
  echo "############################################################"
  exit 0
}

installCli() {
  echo "Install/update arduino-cli..."
  if [ ! -d "$bin_path" ]; then
    mkdir -p "$bin_path"
  elif [ -f "$cli_path" ]; then
    rm "$cli_path"
  fi
  curl -fsSL "$gh_cli" | BINDIR="$bin_path" sh
  ret="${PIPESTATUS[0]}"
  if [ "$ret" -ne 0 ]; then
    echo "[$me] Could not retrieve arduino-cli. Abort."
    exit "$ret"
  fi
  if ! command -v $cli > /dev/null 2>&1; then
    echo "[$me] $cli not found."
    echo "Please ensure that $bin_path is in your PATH environment:"
    echo "Aborting!"
    exit 1
  fi
  # Reference the STM32 core
  arduino-cli config init --additional-urls "$gh_stm32"
  arduino-cli core update-index
  arduino-cli lib update-index
  echo "done"
}

installIDE() {
  echo "Install/update Arduino IDE..."
  if [ -d "$IDE_path" ]; then
    rm -fr "$IDE_path"
  fi
  mkdir -p "$IDE_path"

  if [ ! -f "$IDE_archive" ]; then
    wget "$IDE_url" > /dev/null 2>&1
    ret=$?
    if [ "$ret" -ne 0 ]; then
      echo "[$me] Could not download $IDE_name."
      echo "Aborting!"
      exit "$ret"
    fi
  fi
  tar xf "$IDE_archive" --strip-components=1 -C "$IDE_path"
  ret=$?
  if [ "$ret" -ne 0 ]; then
    echo "[$me] $IDE_name could not be extrated."
    echo "Aborting!"
    exit "$ret"
  fi
  # rm "$IDE_archive"
  echo "done"
}

installLib() {
  echo "Install/update Arduino libraries..."
  if [ ! -d "$arduino_lib_path" ]; then
    mkdir -p "$arduino_lib_path"
  fi

  if [ ! -f "$libListFile" ]; then
    echo "No library to install"
    return
  fi

  readarray -t lib_list < $libListFile

  if [ ${#lib_list[@]} -eq 0 ]; then
    echo "No library to install"
    return
  else
    echo "Number of libraries found: ${#lib_list[@]}"
  fi

  for lib_name in "${lib_list[@]}"; do
    if [[ "$lib_name" == *"http"* ]]; then
      lib_url="$(cut -d' ' -f2 <<<"$lib_name")"
      lib_name="$(cut -d' ' -f1 <<<"$lib_name")"
      lib_archive=$(basename "$lib_url")

      echo "lib name is $lib_name and lib url is $lib_url"

      if [ -f "$lib_archive" ]; then
        rm "$lib_archive"
      fi
      wget "$lib_url" > /dev/null 2>&1
      ret=$?
      if [ "$ret" -ne 0 ]; then
        echo "Could not download $lib_name."
        continue
      fi
    else
      echo "lib name is $lib_name"
    fi
  done
  # Reference the STM32 core
#  arduino-cli config init --additional-urls "$gh_stm32"
#  arduino-cli core update-index
#  arduino-cli lib update-index
  echo "done"
}

updateCore() {
  echo "Install/update the STM32 core.."
  arduino-cli core update-index
  if ! arduino-cli core list | grep "STM32" > /dev/null 2>&1; then
    arduino-cli core install STM32:stm32
  fi
  arduino-cli core upgrade
  echo "done"
}

updateSTM32Lib() {
  # Get list of repo
  curl -s "$gh_api" | jq '.[]|.html_url' | grep -v -f excludeList.txt | sed -e "s/\"//g" > $repoListFile
  ret="${PIPESTATUS[0]}"
  if [ "$ret" -ne 0 ]; then
    echo "[$0] Could not retrieve repository list. Abort."
    exit "$ret"
  fi
  readarray -t git_list < $repoListFile

  if [ ${#git_list[@]} -eq 0 ]; then
    echo "[$0] No library found. Abort."
    exit 1
  else
    echo "Number of libraries found: ${#git_list[@]}"
  fi

  if [ ! -d "$lib_repo_path" ]; then
    mkdir "$lib_repo_path"
  fi

  for git_repo in "${git_list[@]}"; do
    git_name=$(basename "$git_repo")
    git_dir=$lib_repo_path/$git_name
    if [ -z "$git_dir" ]; then
      continue
    fi
    if [ -d "$git_dir" ] && [ ! -d "$git_dir/.git" ]; then
      rm -fr "$git_dir"
    fi
    if [ -d "$git_dir/.git" ]; then
      rname=$(git -C "$git_dir" remote -v | grep stm32duino | awk '{print $1}' | sort -u)
      if [ ! -z "$rname" ]; then
        echo "Updating remote $rname of $git_name..."
        # Check if the repository is cleaned
        # First is there any uncommited change(s) or untracked file(s)?
        if output=$(git -C "$git_dir" status --porcelain) && [ -z "$output" ]; then
          # Is there any local commit?
          if output=$(git -C "$git_dir" log "${rname}/master..master") && [ -z "$output" ]; then
            # Fetch repo
            if output=$(git -C "$git_dir" fetch "$rname" 2>&1) && [ ! -z "$output" ]; then
              git -C "$git_dir" checkout -B master "${rname}/master"
              echo "done"
            else
              echo "Nothing to update"
            fi
          else
            echo "Not updated --> local commit(s) not pushed"
            echo "$output"
          fi
        else
          echo "Not updated --> uncommitted change(s) or untracked file(s)"
          echo "$output"
        fi
      else
        echo "Not updated --> no remote"
      fi
    else
      git -C "$lib_repo_path" clone "$git_repo"
    fi
  done
}

# parse command line arguments
# options may be followed by one colon to indicate they have a required arg
if ! options=$(getopt -o ahu -- "$@"); then
  echo "Terminating..." >&2
  exit 1
fi

eval set -- "$options"

while true; do
  case "$1" in
    -a)
      echo "Install and configure all"
      doCli=1
      doUpdate=1
      shift
      ;;
    -h | -\?)
      usage
      shift
      ;;
    -u)
      echo "Update all"
      doUpdate=1
      shift
      ;;
      #    -s) echo "Sketch pattern to build: $2"
      #        sketch_pattern=$2
      #        shift 2;;
    --)
      shift
      break
      ;;
    *) break ;;
  esac
done

if [ "$doCli" -eq 1 ]; then
  # installCli
  # installIDE
  installLib
fi
if [ "$doUpdate" -eq 1 ]; then
  # updateCore
  # updateSTM32Lib
  echo ""
fi
