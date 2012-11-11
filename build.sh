#!/usr/bin/env bash

export DATE=$(date +%h-%d-%y)

function check_result {
  if [ "0" -ne "$?" ]
  then
    echo $1
    exit 1
  fi
}

if [ -z "$HOME" ]
then
  echo HOME not in environment, guessing...
  export HOME=$(awk -F: -v v="$USER" '{if ($1==v) print $6}' /etc/passwd)
fi

if [ -z "$WORKSPACE" ]
then
  echo WORKSPACE not specified
  exit 1
fi

if [ -z "$CLEAN_TYPE" ]
then
  echo CLEAN_TYPE not specified
  exit 1
fi

if [ -z "$REPO_BRANCH" ]
then
  echo REPO_BRANCH not specified
  exit 1
fi

if [ -z "$LUNCH" ]
then
  echo LUNCH not specified
  exit 1
fi

if [ -z "$SYNC_PROTO" ]
then
  SYNC_PROTO=git
fi

# colorization fix in Jenkins
export CL_RED="\"\033[31m\""
export CL_GRN="\"\033[32m\""
export CL_YLW="\"\033[33m\""
export CL_BLU="\"\033[34m\""
export CL_MAG="\"\033[35m\""
export CL_CYN="\"\033[36m\""
export CL_RST="\"\033[0m\""


cd $WORKSPACE
mkdir -p archive
export BUILD_NO=$BUILD_NUMBER
unset BUILD_NUMBER

export PATH=~/bin:$PATH
export BUILD_WITH_COLORS=1
export CCACHE_COMPILERCHECK=none
export USE_CCACHE=1
export FAST_BUILD=1
export CUSTOM_CCACHE_PATH=/usr/local/bin
REPO=$(which repo)
if [ -z "$REPO" ]
then
  mkdir -p ~/bin
  curl https://dl-ssl.google.com/dl/googlesource/git-repo/repo > ~/bin/repo
  chmod a+x ~/bin/repo
fi

git config --global user.name KAsp3rd
git config --global user.email casper200519@gmail.com

mkdir -p $REPO_BRANCH
cd $REPO_BRANCH

# always force a fresh repo init since we can build off different branches
# and the "default" upstream branch can get stuck on whatever was init first.
if [ -z "$CORE_BRANCH" ]
then
  CORE_BRANCH=$REPO_BRANCH
fi
rm -rf .repo/manifests*
repo init -u https://github.com/KAsp3rd/platform_manifest.git -b $CORE_BRANCH
check_result "repo init failed."

# make sure ccache is in PATH
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilt/$(uname|awk '{print tolower($0)}')-x86/ccache"

if [ -f ~/.jenkins_profile ]
then
  . ~/.jenkins_profile
fi

cp $WORKSPACE/hudson/$REPO_BRANCH.xml .repo/local_manifest.xml

echo Core Manifest:
cat .repo/manifests/default.xml

echo Local Manifest:
cat .repo/local_manifest.xml

#echo Syncing...
repo sync -d #> /dev/null
check_result "repo sync failed."
echo Sync complete.

if [ -f $WORKSPACE/hudson/$REPO_BRANCH-setup.sh ]
then
  $WORKSPACE/hudson/$REPO_BRANCH-setup.sh
fi

. build/envsetup.sh
lunch $LUNCH
check_result "lunch failed."

rm -f $OUT/aokp*.zip*

UNAME=$(uname)

if [ ! -z "$GERRIT_CHANGES" ]
then
  IS_HTTP=$(echo $GERRIT_CHANGES | grep http)
  if [ -z "$IS_HTTP" ]
  then
    python $WORKSPACE/hudson/repopick.py $GERRIT_CHANGES
    check_result "gerrit picks failed."
  else
    python $WORKSPACE/hudson/repopick.py $(curl $GERRIT_CHANGES)
    check_result "gerrit picks failed."
  fi
fi

make $CLEAN_TYPE
# mka bacon recoveryzip recoveryimage checkapi
time brunch $LUNCH
check_result "Build failed."

cp $OUT/aokp*${DATE}*.zip $WORKSPACE/archive
# chmod the files in case UMASK blocks permissions
chmod -R ugo+r $WORKSPACE/archive

# changelog gen
. $WORKSPACE/hudson/changelog_gen.sh $LASTBUILDDATE
