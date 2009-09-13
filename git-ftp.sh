#!/bin/bash
# ------------------------------------------------------------
# File        : git-ftp.sh
# Author      : René Moser
# Date        : 2009-09-01
# Description : Deployes git tracked changed files by FTP
# ------------------------------------------------------------

VERSION='0.0.1'
AUTHOR='rene moser <mail@renemoser.net>'

# ------------------------------------------------------------
# Setup Environment
# ------------------------------------------------------------

# General config
VERBOSE=1
GIT_FTP_HOME="`pwd`/.git/git_ftp"
DEPLOYED_FILE="deployed_sha1"
GIT_BIN="/usr/bin/git"
LCK_FILE="`basename $0`.lck"

# ------------------------------------------------------------
# Defaults
# ------------------------------------------------------------
FTP_HOST=""
FTP_USER=""
FTP_PASSWD=""
FTP_REMOTE_DIR=""

# ------------------------------------------------------------
# Pre checks
# ------------------------------------------------------------

# Simple log func
writeLog() {
    if [ $VERBOSE -eq 1 ]; then
        echo "`date`: $1"
    fi
}

# Release lock func
releaseLock() {
    writeLog "Releasing lock"
    rm -f "${LCK_FILE}"
}

# Copy 'n' pasted simple bash ini parser func 
# from http://ajdiaz.wordpress.com/2008/02/09/bash-ini-parser/
cfg.parser () {
    IFS=$'\n' && ini=( $(<$1) )              # convert to line-array
    ini=( ${ini[*]//;*/} )                   # remove comments
    ini=( ${ini[*]/#[/\}$'\n'cfg.section.} ) # set section prefix
    ini=( ${ini[*]/%]/ \(} )                 # convert text2function (1)
    ini=( ${ini[*]/=/=\( } )                 # convert item to array
    ini=( ${ini[*]/%/ \)} )                  # close array parenthesis
    ini=( ${ini[*]/%\( \)/\(\) \{} )         # convert text2function (2)
    ini=( ${ini[*]/%\} \)/\}} )              # remove extra parenthesis
    ini[0]=''                                # remove first element
    ini[${#ini[*]} + 1]='}'                  # add the last brace
    eval "$(echo "${ini[*]}")"               # eval the result
}

# Checks locking, make sure this only run once a time
if [ -f "${LCK_FILE}" ]; then

    # The file exists so read the PID to see if it is still running
    MYPID=`head -n 1 "${LCK_FILE}"`

    TEST_RUNNING=`ps -p ${MYPID} | grep ${MYPID}`

    if [ -z "${TEST_RUNNING}" ]; then
        # The process is not running echo current PID into lock file
        writeLog "Not running"
        echo $$ > "${LCK_FILE}"
    else
        writeLog "`basename $0` is already running [${MYPID}]"
        exit 0
    fi
else
    writeLog "Not running"
    echo $$ > "${LCK_FILE}"
fi

# ------------------------------------------------------------
# Main part
# ------------------------------------------------------------

# Check if this is a git project here
NOT_GIT_DIR=`${GIT_BIN} status > /dev/null 2>&1 | grep -c fatal`
if [ ${NOT_GIT_DIR} -eq 1 ]; then
    writeLog "Not a git project? Exiting..."
    releaseLock
    exit 0
fi 

# Check if the git working dir is dirty
DIRTY_REPO=`${GIT_BIN} update-index --refresh | wc -l ` 
if [ ${DIRTY_REPO} -eq 1 ]; then 
    writeLog "Dirty Repo? Exiting..."
    releaseLock
    exit 0
fi 

# Check if are at master branch (temp solution)
CURRENT_BRANCH="`${GIT_BIN} branch | grep '*' | cut -d ' ' -f 2`" 
if [ "${CURRENT_BRANCH}" != "master" ]; then 
    writeLog "Not master branch? Exiting..."
    releaseLock
    exit 0
fi 

# create home if not exists
mkdir -p ${GIT_FTP_HOME}

# Check if there is a config file containing FTP stuff
if [ ! -f "${GIT_FTP_HOME}/${CFG_FILE}" ]; then
    writeLog "Config file not found. See example config file. Exiting..."
    releaseLock
    exit 0
else 
    writeLog "Config file found."
    cfg.parser "${GIT_FTP_HOME}/${CFG_FILE}"
    cfg.section.FTP
    
    HAS_ERROR=0
    if [ -z ${FTP_HOST} ]; then
        writeLog "FTP host not set in config file"
        HAS_ERROR=1
    fi
    
    if [ -z ${FTP_USER} ]; then
        writeLog "FTP user not set in config file"
        HAS_ERROR=1
    fi
    
    if [ ${HAS_ERROR} != 0 ]; then
        releaseLock
        exit 0
    fi
fi

# Check if we already deployed by FTP
if [ ! -f "${GIT_FTP_HOME}/${DEPLOYED_FILE}" ]; then
    touch ${GIT_FTP_HOME}/${DEPLOYED_FILE}
    writeLog "Created empty file ${GIT_FTP_HOME}/${DEPLOYED_FILE}"
fi 

# Get the last commit (SHA) we deployed
DEPLOYED_SHA1="`head -n 1 ${GIT_FTP_HOME}/${DEPLOYED_FILE} | cut -d ' ' -f 2`"
if [ "${DEPLOYED_SHA1}" != "" ]; then
    writeLog "Last deployed SHA1 is ${DEPLOYED_SHA1}"
else 
    writeLog "No last deployed SHA1 found"
fi

# Get the files changed since then
FILES_CHANGED="`${GIT_BIN} diff --name-only ${DEPLOYED_SHA1}`"
if [ "${FILES_CHANGED}" != "" ]; then 
    writeLog "Having changed files";
else 
    writeLog "No changed files. Giving up..."
    releaseLock
    exit 0
fi

# Upload to ftp
for file in ${FILES_CHANGED}; do 
    
    # File exits?
    if [ -f ${file} ]; then
    
        # Path contains dirs? See Parameter Expansion
        COUNT_DIRS=${file//[!\/]/}        
        writeLog "${file} has ${#COUNT_DIRS} directories"
        
        if [ ${#COUNT_DIRS} -gt 0 ]; then

            # Create dirs on ftp server
            i=1
            MKDIR_PATH=""
            while [ $i -le ${#COUNT_DIRS} ]; do
                
                MKDIR="`echo ${file} | cut -d '/' -f ${i}`"
                writeLog "Making dir if not exists ${FTP_REMOTE_DIR}${MKDIR_PATH}/${MKDIR}"
                
                ftp -in ${FTP_HOST} <<EOFTP
                quote USER ${FTP_USER}
                quote PASS ${FTP_PASSWD}
                cd ${FTP_REMOTE_DIR}${MKDIR_PATH}
                mkdir ${MKDIR}
                quit
EOFTP
            i=$(( $i + 1 ))
            MKDIR_PATH="/${MKDIR}"
            done
        fi
        
        # Uploading file
        writeLog "Uploading ${file}"

        ftp -in ${FTP_HOST} <<EOFTP
        quote USER ${FTP_USER}
        quote PASS ${FTP_PASSWD}
        cd ${FTP_REMOTE_DIR}
        put ${file}
        quit
EOFTP
    else
        writeLog "Not existing file ${file}"
    fi
done
 
# if successful, remember the SHA1 of last commit
${GIT_BIN} log -n 1 > ${GIT_FTP_HOME}/${DEPLOYED_FILE}
writeLog "Last deployment changed to `cat ${GIT_FTP_HOME}/${DEPLOYED_FILE}`";

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------
releaseLock

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------
exit 0