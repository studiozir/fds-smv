#!/bin/bash

# $Date: 2015-01-23 00:02:37 -0500 (Fri, 23 Jan 2015) $ 
# $Revision: 21512 $
# $Author: gforney $

# Firebot
# FDS automatIc veRification and validation tEst bot
# Kristopher Overholt
# 6/22/2012

# The Firebot script is part of an automated continuous integration system.
# Please consult the Utilities/Firebot/README.txt file and the
# FDS Configuration Management Plan for more information.

# This version of Firebot runs on Mac OS X.
# This runs nightly on bluesky (Mac Pro) at NIST.

#  ===================
#  = Input variables =
#  ===================

FDS_SVN_BASE=FDS-SMVclean
DEBUG=
FIREBOT_USERNAME=`whoami`
while getopts 'd' OPTION
do
case $OPTION  in
  d)
  DEBUG=1
  ;;
esac
done
shift $(($OPTIND-1))

# Change to home directory
cd
FIREBOT_HOME_DIR="`pwd`"

# Additional definitions
SVN_REVISION=$1
FIREBOT_DIR="/Users/$FIREBOT_USERNAME/firebot"
FDS_SVNROOT="/Users/$FIREBOT_USERNAME/$FDS_SVN_BASE"
TIME_LOG=$FIREBOT_DIR/output/timings
ERROR_LOG=$FIREBOT_DIR/output/errors
WARNING_LOG=$FIREBOT_DIR/output/warnings

# Load mailing list for status report
source $FIREBOT_DIR/firebot_email_list.sh
if [[ "$DEBUG" == "1" ]] ; then
   mailToFDS=$mailToFDS_debug
else
   mailToFDS=$mailToFDS_verbose
fi

#  ====================
#  = End user warning =
#  ====================

# Warn if not using FDS-SMVclean

if [[ "$FDS_SVN_BASE" == "FDS-SMVclean" ]];
   then
      # Continue along
      :
   else
      echo "Warning: You are running the Firebot script with the repo $FDS_SVN_BASE not FDS-SMVclean"
      echo "Terminating script."
      exit
fi

#  =============================================
#  = Firebot timing and notification mechanism =
#  =============================================

# This routine checks the elapsed time of Firebot.
# If Firebot runs more than 12 hours, an email notification is sent.
# This is a notification only and does not terminate Firebot.
# This check runs during Stage 5.

# Start firebot timer
START_TIME=$(date +%s)

# Set time limit (57,600 seconds = 16 hours)
TIME_LIMIT=57600
TIME_LIMIT_EMAIL_NOTIFICATION="unsent"

check_time_limit()
{
   if [ "$TIME_LIMIT_EMAIL_NOTIFICATION" == "sent" ]
   then
      # Continue along
      :
   else
      CURRENT_TIME=$(date +%s)
      ELAPSED_TIME=$(echo "$CURRENT_TIME-$START_TIME"|bc)

      if [ $ELAPSED_TIME -gt $TIME_LIMIT ]
      then
         echo 'Sending email'
         echo -e "Firebot has been running for more than 12 hours in Stage ${TIME_LIMIT_STAGE}. \n\nPlease ensure that there are no problems. \n\nThis is a notification only and does not terminate Firebot." | mail -s "[Firebot@$hostname] Notice: Firebot has been running for more than 12 hours." $mailTo > /dev/null
         TIME_LIMIT_EMAIL_NOTIFICATION="sent"
      fi
   fi
}

#  ========================
#  = Additional functions =
#  ========================

set_files_world_readable()
{
   cd $FDS_SVNROOT
   chmod -R go+r *
}

clean_firebot_history()
{
   # Clean Firebot metafiles
   cd $FIREBOT_DIR
   rm output/* > /dev/null
}

#  ========================
#  ========================
#  = Firebot Build Stages =
#  ========================
#  ========================

#  ============================
#  = Stage 1 - SVN operations =
#  ============================

clean_svn_repo()
{
   # Check to see if FDS repository exists
   if [ -e "$FDS_SVNROOT" ]
   # If yes, clean FDS repository
   then
      # Revert and clean up temporary unversioned and modified versioned repository files
      cd $FDS_SVNROOT
      svn revert -Rq *
      svn status --no-ignore | grep '^[I?]' | cut -c 9- | while IFS= read -r f; do rm -rf "$f"; done
   # If not, create FDS repository and checkout
   else
      echo "Downloading FDS repository:" >> $FIREBOT_DIR/output/stage1 2>&1
      mkdir -p $FDS_SVNROOT
      cd $FIREBOT_HOME_DIR
      svn co http://fds-smv.googlecode.com/svn/trunk/FDS/trunk/ $FDS_SVN_BASE >> $FIREBOT_DIR/output/stage1 2>&1
   fi
}

do_svn_checkout()
{
   cd $FDS_SVNROOT
   # If an SVN revision number is specified, then get that revision
   if [[ $SVN_REVISION != "" ]]; then
      echo "Checking out revision r${SVN_REVISION}." >> $FIREBOT_DIR/output/stage1 2>&1
      svn update -r $SVN_REVISION >> $FIREBOT_DIR/output/stage1 2>&1
   # If no SVN revision number is specified, then get the latest revision
   else
      echo "Checking out latest revision." >> $FIREBOT_DIR/output/stage1 2>&1
      svn update >> $FIREBOT_DIR/output/stage1 2>&1
      SVN_REVISION=`tail -n 1 $FIREBOT_DIR/output/stage1 | sed "s/[^0-9]//g"`
   fi
}

check_svn_checkout()
{
   cd $FDS_SVNROOT
   # Check for SVN errors
   if [[ `grep -E 'Updated|At revision' $FIREBOT_DIR/output/stage1 | wc -l` -ne 1 ]];
   then
      echo "Errors from Stage 1 - SVN operations:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage1 >> $ERROR_LOG
      echo "" >> $ERROR_LOG
      email_build_status
      exit
   else
      stage1_success=true
   fi
}

#  ================================
#  = Stage 2a - Compile FDS debug =
#  ================================

compile_fds_db()
{
   # Clean and compile FDS debug
   cd $FDS_SVNROOT/FDS_Compilation/intel_osx_64_db
   make -f ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage2a
}

check_compile_fds_db()
{
   # Check for errors in FDS debug compilation
   cd $FDS_SVNROOT/FDS_Compilation/intel_osx_64_db
   if [ -e "fds_intel_osx_64_db" ]
   then
      stage2a_success=true
   else
      echo "Errors from Stage 2a - Compile FDS debug:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage2a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2a` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 2a - Compile FDS debug:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2a >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ====================================
#  = Stage 2b - Compile FDS MPI debug =
#  ====================================

compile_fds_mpi_db()
{
   # Clean and compile FDS MPI debug
   cd $FDS_SVNROOT/FDS_Compilation/mpi_intel_osx_64_db
   make -f ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage2b
}

check_compile_fds_mpi_db()
{
   # Check for errors in FDS MPI debug compilation
   cd $FDS_SVNROOT/FDS_Compilation/mpi_intel_osx_64_db
   if [ -e "fds_mpi_intel_osx_64_db" ]
   then
      stage2b_success=true
   else
      echo "Errors from Stage 2b - Compile FDS MPI debug:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage2b >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # grep -v 'feupdateenv ...' ignores a known FDS MPI compiler warning (http://software.intel.com/en-us/forums/showthread.php?t=62806)
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2b | grep -v 'feupdateenv is not implemented'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 2b - Compile FDS MPI debug:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2b | grep -v 'feupdateenv is not implemented' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ===================================================
#  = Stage 3 - Run verification cases (debug mode)   =
#  ===================================================

wait_verification_cases_debug_end()
{
   # Scans processes and waits for verification cases to end
   while [[ `ps x | grep intel_osx_64 | wc -l` -gt 1 ]]; do
      JOBS_RUNNING=`ps x | grep intel_osx_64 | wc -l`
      echo "${JOBS_RUNNING} verification cases currently running." >> $FIREBOT_DIR/output/stage3
      TIME_LIMIT_STAGE="3"
      check_time_limit
      sleep 60
   done
}

run_verification_cases_debug()
{
   # Run FDS verification cases
   cd $FDS_SVNROOT/Verification
   echo 'Running FDS verification cases:' > $FIREBOT_DIR/output/stage3
   ./Run_FDS_Cases.sh -E -d -m 1 -q none >> $FIREBOT_DIR/output/stage3 2>&1
   echo "" >> $FIREBOT_DIR/output/stage3 2>&1

   # Wait for all verification cases to end
   wait_verification_cases_debug_end
}

check_verification_cases_debug()
{
   # Scan and report any errors in FDS verification cases
   cd $FDS_SVNROOT/Verification

   if [[ `grep 'Run aborted' -rI ${FIREBOT_DIR}/output/stage3` == "" ]] && \
      [[ `grep Segmentation -rI *` == "" ]] && \
      [[ `grep ERROR: -rI *` == "" ]] && \
      [[ `grep 'STOP: Numerical' -rI *` == "" ]] && \
      [[ `grep -A 20 forrtl -rI *` == "" ]]
   then
      stage3_success=true
   else
      grep 'Run aborted' -rI $FIREBOT_DIR/output/stage3 > $FIREBOT_DIR/output/stage3_errors
      grep Segmentation -rI * >> $FIREBOT_DIR/output/stage3_errors
      grep ERROR: -rI * >> $FIREBOT_DIR/output/stage3_errors
      grep 'STOP: Numerical' -rI * >> $FIREBOT_DIR/output/stage3_errors
      grep -A 20 forrtl -rI * >> $FIREBOT_DIR/output/stage3_errors
      
      echo "Errors from Stage 3 - Run verification cases (debug mode):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage3_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ==================================
#  = Stage 4a - Compile FDS release =
#  ==================================

compile_fds()
{
   # Clean and compile FDS
   cd $FDS_SVNROOT/FDS_Compilation/intel_osx_64
   make -f ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage4a
}

check_compile_fds()
{
   # Check for errors in FDS compilation
   cd $FDS_SVNROOT/FDS_Compilation/intel_osx_64
   if [ -e "fds_intel_osx_64" ]
   then
      stage4a_success=true
   else
      echo "Errors from Stage 4a - Compile FDS release:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage4a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # 'performing multi-file optimizations' and 'generating object file' are part of a normal compile
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4a | grep -v 'performing multi-file optimizations' | grep -v 'generating object file'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 4a - Compile FDS release:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4a | grep -v 'performing multi-file optimizations' | grep -v 'generating object file' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ======================================
#  = Stage 4b - Compile FDS MPI release =
#  ======================================

compile_fds_mpi()
{
   # Clean and compile FDS MPI
   cd $FDS_SVNROOT/FDS_Compilation/mpi_intel_osx_64
   make -f ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage4b
}

check_compile_fds_mpi()
{
   # Check for errors in FDS MPI compilation
   cd $FDS_SVNROOT/FDS_Compilation/mpi_intel_osx_64
   if [ -e "fds_mpi_intel_osx_64" ]
   then
      stage4b_success=true
   else
      echo "Errors from Stage 4b - Compile FDS MPI release:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage4b >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # 'performing multi-file optimizations' and 'generating object file' are part of a normal compile
   # grep -v 'feupdateenv ...' ignores a known FDS MPI compiler warning (http://software.intel.com/en-us/forums/showthread.php?t=62806)
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4b | grep -v 'feupdateenv is not implemented' | grep -v 'performing multi-file optimizations' | grep -v 'generating object file'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 4b - Compile FDS MPI release:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4b | grep -v 'feupdateenv is not implemented' | grep -v 'performing multi-file optimizations' | grep -v 'generating object file' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ======================================
#  = Stage 5pre - Compile SMV utilities =
#  ======================================

compile_smv_utilities()
{  
   # smokeview libraries
   cd $FDS_SVNROOT/SMV/Build/LIBS/lib_osx_intel_64
   echo 'Building Smokeview libraries:' > $FIREBOT_DIR/output/stage5pre 2>&1
   ./makelibs.sh >> $FIREBOT_DIR/output/stage5pre 2>&1
   echo "" >> $FIREBOT_DIR/output/stage5pre 2>&1

   # background:
   cd $FDS_SVNROOT/Utilities/background/intel_osx_32
   echo 'Compiling background:' >> $FIREBOT_DIR/output/stage5pre 2>&1
   ./make_background.sh >> $FIREBOT_DIR/output/stage5pre 2>&1
   echo "" >> $FIREBOT_DIR/output/stage5pre 2>&1
}

check_smv_utilities()
{
   # Check for errors in SMV utilities compilation
   cd $FDS_SVNROOT
   if [ -e "$FDS_SVNROOT/Utilities/background/intel_osx_32/background" ]
   then
      stage5pre_success=true
   else
      echo "Errors from Stage 5pre - Compile SMV utilities:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage5pre >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ===================================================
#  = Stage 5 - Run verification cases (release mode) =
#  ===================================================

wait_verification_cases_release_end()
{
   # Scans processes and waits for verification cases to end
   while [[ `ps x | grep intel_osx_64 | wc -l` -gt 1 ]]; do
      JOBS_RUNNING=`ps x | grep intel_osx_64 | wc -l`
      echo "${JOBS_RUNNING} verification cases currently running." >> $FIREBOT_DIR/output/stage5
      TIME_LIMIT_STAGE="5"
      check_time_limit
      sleep 60
   done
}

run_verification_cases_release()
{
   # Run FDS verification cases
   cd $FDS_SVNROOT/Verification
   echo 'Running FDS verification cases:' > $FIREBOT_DIR/output/stage5
   ./Run_FDS_Cases.sh -E -q none >> $FIREBOT_DIR/output/stage5 2>&1
   echo "" >> $FIREBOT_DIR/output/stage5 2>&1

   # Wait for all verification cases to end
   wait_verification_cases_release_end
}

check_verification_cases_release()
{
   # Scan and report any errors in FDS verification cases
   cd $FDS_SVNROOT/Verification

   if [[ `grep 'Run aborted' -rI ${FIREBOT_DIR}/output/stage5` == "" ]] && \
      [[ `grep Segmentation -rI *` == "" ]] && \
      [[ `grep ERROR: -rI *` == "" ]] && \
      [[ `grep 'STOP: Numerical' -rI *` == "" ]] && \
      [[ `grep -A 20 forrtl -rI *` == "" ]]
   then
      stage5_success=true
   else
      grep 'Run aborted' -rI $FIREBOT_DIR/output/stage5 > $FIREBOT_DIR/output/stage5_errors
      grep Segmentation -rI * >> $FIREBOT_DIR/output/stage5_errors
      grep ERROR: -rI * >> $FIREBOT_DIR/output/stage5_errors
      grep 'STOP: Numerical' -rI * >> $FIREBOT_DIR/output/stage5_errors
      grep -A 20 forrtl -rI * >> $FIREBOT_DIR/output/stage5_errors
      
      echo "Errors from Stage 5 - Run verification cases (release mode):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage5_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ==================================================
#  = Build status report - email and save functions =
#  ==================================================

save_build_status()
{
   cd $FIREBOT_DIR
   # Save status outcome of build to a text file
   if [[ -e $WARNING_LOG && -e $ERROR_LOG ]]
   then
     echo "" >> $ERROR_LOG
     cat $WARNING_LOG >> $ERROR_LOG
     echo "Build failure and warnings for Revision ${SVN_REVISION}." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
     cat $ERROR_LOG > "$FIREBOT_DIR/history/${SVN_REVISION}_errors.txt"

   # Check for errors only
   elif [ -e $ERROR_LOG ]
   then
      echo "Build failure for Revision ${SVN_REVISION}." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
      cat $ERROR_LOG > "$FIREBOT_DIR/history/${SVN_REVISION}_errors.txt"

   # Check for warnings only
   elif [ -e $WARNING_LOG ]
   then
      echo "Revision ${SVN_REVISION} has warnings." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
      cat $WARNING_LOG > "$FIREBOT_DIR/history/${SVN_REVISION}_warnings.txt"

   # No errors or warnings
   else
      echo "Build success! Revision ${SVN_REVISION} passed all build tests." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
   fi
}

email_build_status()
{
   cd $FIREBOT_DIR
   # Check for warnings and errors
   if [[ -e $WARNING_LOG && -e $ERROR_LOG ]]
   then
     # Send email with failure message and warnings, body of email contains appropriate log file
     mail -s "[Firebot@$hostname] Build failure and warnings for Revision ${SVN_REVISION}." $mailToFDS < $ERROR_LOG > /dev/null

   # Check for errors only
   elif [ -e $ERROR_LOG ]
   then
      # Send email with failure message, body of email contains error log file
      mail -s "[Firebot@$hostname] Build failure for Revision ${SVN_REVISION}." $mailToFDS < $ERROR_LOG > /dev/null

   # Check for warnings only
   elif [ -e $WARNING_LOG ]
   then
      # Send email with success message, include warnings
      mail -s "[Firebot@$hostname] Build success, with warnings. Revision ${SVN_REVISION} passed all build tests." $mailToFDS < $WARNING_LOG > /dev/null

   # No errors or warnings
   else
      # Send success message with links to nightly manuals
      stop_time=`date`
      echo "-------------------------------" >> $TIME_LOG
      echo "Host OS: Mac OS X " >> $TIME_LOG
      echo "Host Name: $hostname " >> $TIME_LOG
      echo "Start Time: $start_time " >> $TIME_LOG
      echo "Stop Time: $stop_time " >> $TIME_LOG
      echo "-------------------------------" >> $TIME_LOG
      mail -s "[Firebot@$hostname] Build success! Revision ${SVN_REVISION} passed all build tests." $mailToFDS < $TIME_LOG > /dev/null
   fi
}

#  ============================
#  = Primary script execution =
#  ============================

hostname=`hostname`
start_time=`date`

### Clean up on start ###
clean_firebot_history

### Stage 1 ###
clean_svn_repo
do_svn_checkout
check_svn_checkout

### Stage 2a ###
compile_fds_db
check_compile_fds_db

### Stage 2b ###
compile_fds_mpi_db
check_compile_fds_mpi_db

### Stage 4a ###
compile_fds
check_compile_fds

### Stage 4b ###
compile_fds_mpi
check_compile_fds_mpi

### Stage 5pre ###
compile_smv_utilities
check_smv_utilities

### Stage 3 ###
if [[ $stage2a_success && $stage2b_success ]] ; then
  run_verification_cases_debug
  check_verification_cases_debug
fi

### Stage 5 ###
if [[ $stage3_success && $stage4a_success && $stage4b_success ]] ; then
   run_verification_cases_release
   check_verification_cases_release
fi

### Wrap up and report results ###
set_files_world_readable
save_build_status
email_build_status

