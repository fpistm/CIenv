#!/bin/bash - 
#===============================================================================
#
#          FILE: updateLink.sh
# 
#         USAGE: ./updateLink.sh 
# 
#   DESCRIPTION: Update all symbolic links from stm32duino
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: YOUR NAME (), 
#  ORGANIZATION: STMicroelectronics
#     COPYRIGHT: Copyright (C) 2017, STMicroelectronics - All Rights Reserved
#       CREATED: 11/24/17 14:48
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error

# List
libs_list=(`ls -d $HOME/repo/libraries/*/`)

for lib_path in ${libs_list[@]}
do
#${@%/}
  lib_name=`basename ${lib_path%/}`
  if [ ! -L $lib_name ]; then
    ln -s ${lib_path%/} . 
  fi
done
