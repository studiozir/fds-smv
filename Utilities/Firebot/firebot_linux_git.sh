#!/bin/bash

# Firebot
# FDS Automatic Verification and Validation Test Bot
# Kristopher Overholt
# 6/22/2012

# The Firebot script is part of an automated continuous integration system.
# Please consult the Utilities/Firebot/README.txt file and the
# FDS Configuration Management Plan for more information.

#  ===================
#  = Input variables =
#  ===================

# Firebot mode (verification or validation); default mode: verification
FIREBOT_MODE="verification"

# Change to home directory
cd
FIREBOT_HOME_DIR="`pwd`"

platform="linux"
if [ "`uname`" == "Darwin" ] ; then
  platform="osx"
fi

export platform

# Set unlimited stack size
if [ "$platform" == "linux" ] ; then
  ulimit -s unlimited
fi

# Additional definitions
FIREBOT_DIR="$FIREBOT_HOME_DIR/firebotgit"
FDS_GITBASE=FDS-SMVgitclean
fdsroot="$FIREBOT_HOME_DIR/$FDS_GITBASE"
OUTPUT_DIR="$FIREBOT_DIR/output"
HISTORY_DIR="$FIREBOT_DIR/history"
TIME_LOG=$OUTPUT_DIR/timings
ERROR_LOG=$OUTPUT_DIR/errors
WARNING_LOG=$OUTPUT_DIR/warnings
NEWGUIDE_DIR=$OUTPUT_DIR/Newest_Guides
UPLOADGUIDES=./fds_guides2GD.sh

DB=_db
IB=
if [ "$FDSNETWORK" == "infiniband" ] ; then
IB=ib
fi

# Load mailing list for status report
source $FIREBOT_DIR/firebot_email_list_git.sh

function usage {
echo "firebot.sh [ -q queue_name -r revision_string -s -v max_validation_processes -y ]"
echo "Runs Firebot V&V testing script"
echo ""
echo "Options"
echo "-q - queue_name - run cases using the queue queue_name"
echo "     default: firebot"
echo ""
echo "-r - revision_string - run cases using a specific GIT revision string"
echo "     default: (none, latest GIT HEAD)"
echo ""
echo "-s - skip fixing GIT properties and GIT bump of manuals"
echo "     default: SKIP_GIT_PROPS_AND_GIT_BUMP is undefined (false)"
echo ""
echo "-u - specify GIT username to use"
echo "     default: fds.firebot"
echo ""
echo "-v n - run Firebot in validation mode with a specified number of maximum processes dedicated to validation"
echo "     default: (none)"
echo ""
exit
}

QUEUE=firebot
GIT_REVISION=
while getopts 'hq:r:sv:' OPTION
do
case $OPTION in
  h)
   usage;
   ;;
  q)
   QUEUE="$OPTARG"
   ;;
  r)
   GIT_REVISION="$OPTARG"
   ;;
  s)
   SKIP_GIT_PROPS_AND_GIT_BUMP=true
   ;;
  v)
   FIREBOT_MODE="validation"
   QUEUE=batch
   MAX_VALIDATION_PROCESSES="$OPTARG"
   LAUNCH_MORE_CASES=1
   # Set Validationbot email list
   mailToFDS="$mailToFDS_verbose"
   ;;
esac
done
shift $(($OPTIND-1))

#  ====================
#  = End user warning =
#  ====================

if [[ "$FDS_GITBASE" == "FDS-SMVgitclean" ]];
   then
      # Continue along
      :
   else
      echo "Error: You are running the Firebot script with the"
      echo "repo $FDS_GITBASE, not FDS-SMVgitclean."
      echo "Terminating script."
      exit
fi

#  =============================================
#  = Firebot timing and notification mechanism =
#  =============================================

# This routine checks the elapsed time of Firebot.
# If Firebot runs more than 12 hours, an email notification is sent.
# This is a notification only and does not terminate Firebot.
# This check runs during Stages 3 and 5.

# Start firebot timer
START_TIME=$(date +%s)

# Set time limit (43,200 seconds = 12 hours)
TIME_LIMIT=43200

if [ $FIREBOT_MODE == "verification" ] ; then
   TIME_LIMIT_EMAIL_NOTIFICATION="unsent"
elif [ $FIREBOT_MODE == "validation" ] ; then
   # Disable time limit email
   TIME_LIMIT_EMAIL_NOTIFICATION="sent"
fi

MKDIR ()
{
  DIR=$1
  if [ ! -d $DIR ]
  then
    echo Creating directory $DIR
    mkdir $DIR
  fi
}

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
         echo -e "Firebot has been running for more than 12 hours in Stage ${TIME_LIMIT_STAGE}. \n\nPlease ensure that there are no problems. \n\nThis is a notification only and does not terminate Firebot." | mail -s "[Firebot@$hostname] Notice: Firebot has been running for more than 12 hours." $mailToFDS > /dev/null
         TIME_LIMIT_EMAIL_NOTIFICATION="sent"
      fi
   fi
}

#  ========================
#  = Additional functions =
#  ========================

set_files_world_readable()
{
   cd $fdsroot
   chmod -R go+r *
}

clean_firebot_metafiles()
{
   cd $FIREBOT_DIR
   MKDIR guides
   MKDIR $HISTORY_DIR
   MKDIR $OUTPUT_DIR
   rm -rf $OUTPUT_DIR/* > /dev/null
   MKDIR $NEWGUIDE_DIR
   chmod 775 $NEWGUIDE_DIR
}

#  ========================
#  ========================
#  = Firebot Build Stages =
#  ========================
#  ========================

#  ============================
#  = Stage 1 - GIT operations =
#  ============================

clean_git_repo()
{
   # Check to see if FDS repository exists
   if [ -e "$fdsroot" ]
   # If yes, clean FDS repository
   then
      # Revert and clean up temporary unversioned and modified versioned repository files
      cd $fdsroot
# remove unversioned files
      git clean -dxf &> /dev/null
# revert to last revision
      git add . &> /dev/null
      git reset --hard HEAD &> /dev/null
   # If not, create FDS repository and checkout
   else
      echo "Downloading FDS repository:" >> $OUTPUT_DIR/stage1 2>&1
      cd $FIREBOT_HOME_DIR
      git clone git@github.com:firemodels/fds-smv.git $FDS_GITBASE >> $OUTPUT_DIR/stage1 2>&1
   fi
}

do_git_checkout()
{
   cd $fdsroot
   # If an GIT revision string is specified, then get that revision
   if [[ $GIT_REVISION != "" ]]; then
      echo "Checking out revision ${GIT_REVISION}" >> $OUTPUT_DIR/stage1 2>&1
      git checkout $GIT_REVISION . >> $OUTPUT_DIR/stage1 2>&1
      echo "At revision ${GIT_REVISION}." >> $OUTPUT_DIR/stage1 2>&1
   # If no revision string is specified, then get the latest revision
   else
      echo "Checking out latest revision." >> $OUTPUT_DIR/stage1 2>&1
      git pull >> $OUTPUT_DIR/stage1 2>&1

      # Only run if firebot is in "verification" mode and SKIP_GIT_PROPS_AND_GIT_BUMP is not set
      if [[ $FIREBOT_MODE == "verification" && ! $SKIP_GIT_PROPS_AND_GIT_BUMP ]] ; then
         # Bump GIT revision string of all guides (so that the GIT revision keyword gets updated)
         echo "Bump GIT revision string of all guides." >> $OUTPUT_DIR/stage1 2>&1
         CURRENT_TIMESTAMP=`date`
#         sed -i "s/.*% dummy comment to force git change.*/% dummy comment to force git change - ${CURRENT_TIMESTAMP}/" $fdsroot/Manuals/FDS_User_Guide/FDS_User_Guide.tex
#         sed -i "s/.*% dummy comment to force git change.*/% dummy comment to force git change - ${CURRENT_TIMESTAMP}/" $fdsroot/Manuals/FDS_Technical_Reference_Guide/FDS_Technical_Reference_Guide.tex
#         sed -i "s/.*% dummy comment to force git change.*/% dummy comment to force git change - ${CURRENT_TIMESTAMP}/" $fdsroot/Manuals/FDS_Verification_Guide/FDS_Verification_Guide.tex
#         sed -i "s/.*% dummy comment to force git change.*/% dummy comment to force git change - ${CURRENT_TIMESTAMP}/" $fdsroot/Manuals/FDS_Validation_Guide/FDS_Validation_Guide.tex
#         sed -i "s/.*% dummy comment to force git change.*/% dummy comment to force git change - ${CURRENT_TIMESTAMP}/" $fdsroot/Manuals/FDS_Configuration_Management_Plan/FDS_Configuration_Management_Plan.tex
#         sed -i "s/.*! dummy comment to force git change.*/! dummy comment to force git change - ${CURRENT_TIMESTAMP}/" $fdsroot/FDS_Source/main.f90

         # Commit back results
#         git add $fdsroot/Manuals/FDS_User_Guide/FDS_User_Guide.tex
#         git add $fdsroot/Manuals/FDS_Technical_Reference_Guide/FDS_Technical_Reference_Guide.tex
#         git add $fdsroot/Manuals/FDS_Verification_Guide/FDS_Verification_Guide.tex
#         git add $fdsroot/Manuals/FDS_Validation_Guide/FDS_Validation_Guide.tex
#         git add $fdsroot/Manuals/FDS_Configuration_Management_Plan/FDS_Configuration_Management_Plan.tex
#         git add $fdsroot/FDS_Source/main.f90
#         git commit -m 'Firebot: Bump GIT revision of FDS guides and FDS source' &> /dev/null
#         git push &> /dev/null
      fi
      
      echo "Re-checking out latest revision." >> $OUTPUT_DIR/stage1 2>&1
      git pull >> $OUTPUT_DIR/stage1 2>&1
      GIT_REVISION=`git log --abbrev-commit . | head -1 | awk '{print $2}'`
   fi
}

check_git_checkout()
{
   cd $fdsroot
   # Check for GIT errors
   stage1_success=true
}

fix_git_properties()
{
#*** need to port this to git
#*** note: it is not called now
   # This function fixes GIT properties
   # (e.g., svn:executable, svn:keywords, svn:eol-style, and svn:mime-type)
   # throughout the FDS-SMV repository.

   # cd to GIT root
   cd $fdsroot

   # Delete all svn:executable properties
   svn propdel svn:executable --recursive &> /dev/null

   # Restore local executable property to svn-fix-props.py
   chmod +x $fdsroot/Utilities/Subversion/svn-fix-props.py &> /dev/null

   # Run svn-fix-props.py script (fixes all GIT properties)
   $fdsroot/Utilities/Subversion/svn-fix-props.py --config $fdsroot/Utilities/Subversion/config &> /dev/null

   # Commit back results
   svn commit -m 'Firebot: Fix GIT properties throughout repository' &> /dev/null
}

archive_compiler_version()
{
   ifort -V &> "$HISTORY_DIR/${GIT_REVISION}_compiler_info.txt"
}

#  ============================================
#  = Stage 2a - Compile and inspect FDS debug =
#  ============================================

compile_fds_db()
{
   # Clean and compile FDS debug
   cd $fdsroot/FDS_Compilation/intel_${platform}_64_db
   make -f ../makefile clean &> /dev/null
   ./make_fds.sh &> $OUTPUT_DIR/stage2a
}

check_compile_fds_db()
{
   # Check for errors in FDS debug compilation
   cd $fdsroot/FDS_Compilation/intel_${platform}_64_db
   if [ -e "fds_intel_${platform}_64_db" ]
   then
      stage2a_success=true
   else
      echo "Errors from Stage 2a - Compile and inspect FDS debug:" >> $ERROR_LOG
      cat $OUTPUT_DIR/stage2a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2a` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 2a - Compile and inspect FDS debug:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2a >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

inspect_fds_db()
{
   # Perform OpenMP thread checking (locate deadlocks and data races)
   cd $fdsroot/Utilities/Scripts
   ./inspect_openmp.sh &> $OUTPUT_DIR/stage2a_inspect
}

check_inspect_fds_db()
{
   # Scan for errors in thread checking results
   cd $fdsroot/Utilities/Scripts
   # grep -v 'Warning: One or more threads in the application accessed ...' ignores a known compiler warning that displays even without errors
      if [[ `grep -i -E 'warning|remark|problem|error' ${FIREBOT_DIR}/output/stage2a_inspect | grep -v '0 new problem(s) found' | grep -v 'Warning: One or more threads in the application accessed the stack of another thread'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Errors from Stage 2a - Compile and inspect FDS debug:" >> $ERROR_LOG
      cat ${FIREBOT_DIR}/output/stage2a_inspect >> $ERROR_LOG
      echo "" >> $ERROR_LOG
      echo "For more details, view the inspector log in the FDS-SMV/Utilities/Scripts folder" >> $ERROR_LOG
      echo "by using the FDS-SMV/Utilities/Scripts/inspect_report.sh script." >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ====================================
#  = Stage 2b - Compile FDS MPI debug =
#  ====================================

compile_fds_mpi_db()
{
   # Clean and compile FDS MPI debug
   cd $fdsroot/FDS_Compilation/mpi_intel_${platform}_64$IB$DB
   make -f ../makefile clean &> /dev/null
   ./make_fds.sh &> $OUTPUT_DIR/stage2b
}

check_compile_fds_mpi_db()
{
   # Check for errors in FDS MPI debug compilation
   cd $fdsroot/FDS_Compilation/mpi_intel_${platform}_64$IB$DB
   if [ -e "fds_mpi_intel_${platform}_64$IB$DB" ]
   then
      stage2b_success=true
   else
      echo "Errors from Stage 2b - Compile FDS MPI debug:" >> $ERROR_LOG
      cat $OUTPUT_DIR/stage2b >> $ERROR_LOG
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

#  ===============================================================
#  = Stage 3 - Run verification or validation cases (debug mode) =
#  ===============================================================

generate_validation_set_list()
{
   cd $fdsroot/Validation

   # List and sort the oldest validation sets in the $fdsroot/Validation/Process_All_Output.sh script
   # based on the modification date of $VDIR/FDS_Output_Files. The result is an array of the validation
   # sets ordered from oldest to newest.
#   VALIDATION_SETS=(`grep '$VDIR' Process_All_Output.sh | grep -v "#" | xargs -n 1 dirname | xargs -n 1 dirname | xargs -n 1 basename | xargs -i svn info {}/FDS_Output_Files | awk '{if($0 != ""){ if(s){s=s"*"$0}else{s=$0}}else{ print s"*";s=""}}END{print s"*"}' | sort -t* -k9 | cut -d '*' -f1 | cut -d ' ' -f2 | xargs -n 1 dirname`)
   VALIDATION_SETS=(`grep '$VDIR' Process_All_Output.sh  | grep -v "#" | xargs -n 1 dirname | xargs -n 1 dirname | xargs -n 1 basename | xargs -i ../Utilities/Scripts/getsvnentry.sh {} | sort | cut -d ' ' -f2`)
}

wait_cases_debug_start()
{
   # Scans qstat and waits for cases to start
   while [[ `qstat | awk '{print $3 $5}' | grep $(whoami) | grep Q` != '' ]]; do
      JOBS_REMAINING=`qstat | awk '{print $3 $5}' | grep $(whoami) | grep Q | wc -l`
      echo "Waiting for ${JOBS_REMAINING} ${1} cases to start." >> $OUTPUT_DIR/stage3
      TIME_LIMIT_STAGE="3"
      check_time_limit
      sleep 30
   done
}

wait_cases_debug_end()
{
   # Scans qstat and waits for cases to end
   while [[ `qstat | awk '{print $3}' | grep $(whoami)` != '' ]]; do
      JOBS_REMAINING=`qstat | awk '{print $3}' | grep $(whoami) | wc -l`
      echo "Waiting for ${JOBS_REMAINING} ${1} cases to complete." >> $OUTPUT_DIR/stage3
      TIME_LIMIT_STAGE="3"
      check_time_limit
      sleep 30
   done
}

check_current_utilization()
{
   # This function is used to determine if the number of current processes currently in use is greater than the
   # number of specified maximum processes. If so, then no more cases are launched (LAUNCH_MORE_CASES=0).

   sleep 60

   # Reports the number of nodes currently in use by current user
   NUM_CURRENT_PROCESSES=`qstat -u $(whoami) | sed 1,5d | awk '{print $7}' | paste -sd+ | bc`

   if [ "$NUM_CURRENT_PROCESSES" -gt "$MAX_VALIDATION_PROCESSES" ]; then
      LAUNCH_MORE_CASES=0
   fi
}

run_verification_cases_debug()
{
   # Start running all FDS verification cases in delayed stop debug mode
   cd $fdsroot/Verification
   # Run FDS with delayed stop files (with 1 OpenMP thread and 1 iteration)
   echo 'Running FDS verification cases:' >> $OUTPUT_DIR/stage3
   ./Run_FDS_Cases.sh -o 1 -d -m 1 -q $QUEUE >> $OUTPUT_DIR/stage3 2>&1
   echo "" >> $OUTPUT_DIR/stage3 2>&1

   # Wait for all verification cases to end
   wait_cases_debug_end 'verification'

   # Remove all .stop files from Verification directories (recursively)
   cd $fdsroot/Verification
   find . -name '*.stop' -exec rm -f {} \;
}

run_validation_cases_debug()
{
   #  =============================================
   #  = Run FDS validation cases for current sets =
   #  =============================================

   # Initialize array of current validation sets to run
   CURRENT_VALIDATION_SETS=()

   for SET in ${VALIDATION_SETS[*]}
   do
      # Check to see if maximum number of validation processes are in use
      if [ $LAUNCH_MORE_CASES -eq 0 ]; then
         break
      fi

      cd $fdsroot/Validation/"$SET"

      # Submit FDS validation cases and wait for them to start
      echo "Running FDS validation cases for ${SET}:" >> $OUTPUT_DIR/stage3
      echo "" >> $OUTPUT_DIR/stage3 2>&1
      ./Run_All.sh -b -q $QUEUE >> $OUTPUT_DIR/stage3 2>&1

      CURRENT_VALIDATION_SETS+=($SET)

      check_current_utilization
   done

   # Wait for validation cases to start
   wait_cases_debug_start 'validation'
   sleep 300

   #  ==================
   #  = Stop all cases =
   #  ==================

   for SET in ${CURRENT_VALIDATION_SETS[*]}
   do
      cd $fdsroot/Validation/"$SET"
      ./Run_All.sh -b -s >> $OUTPUT_DIR/stage3 2>&1
      echo "" >> $OUTPUT_DIR/stage3 2>&1
   done

   # Wait for validation cases to end
   wait_cases_debug_end 'validation'
   sleep 300

   #  ======================
   #  = Remove .stop files =
   #  ======================

   # Remove all .stop files from Validation directories (recursively)
   cd $fdsroot/Validation
   find . -name '*.stop' -exec rm -f {} \;
}

check_cases_debug()
{
   # Scan for and report any errors in FDS cases
   cd $1

   if [[ `grep -rI 'Run aborted' ${FIREBOT_DIR}/output/stage3` == "" ]] && \
      [[ `grep -rI Segmentation *` == "" ]] && \
      [[ `grep -rI ERROR: *` == "" ]] && \
      [[ `grep -rI 'STOP: Numerical' *` == "" ]] && \
      [[ `grep -rI -A 20 forrtl *` == "" ]]
   then
      stage3_success=true
   else
      grep -rI 'Run aborted' $OUTPUT_DIR/stage3 >> $OUTPUT_DIR/stage3_errors
      grep -rI Segmentation * >> $OUTPUT_DIR/stage3_errors
      grep -rI ERROR: * >> $OUTPUT_DIR/stage3_errors
      grep -rI 'STOP: Numerical' * >> $OUTPUT_DIR/stage3_errors
      grep -rI -A 20 forrtl * >> $OUTPUT_DIR/stage3_errors
      
      echo "Errors from Stage 3 - Run ${2} cases (debug mode):" >> $ERROR_LOG
      cat $OUTPUT_DIR/stage3_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG

# copy casename.err to casename.err_stage3 for any cases that had errors
      echo "#/bin/bash" > $OUTPUT_DIR/stage3_filelist
      grep err $OUTPUT_DIR/stage3_errors | awk -F'[-:]' '{ print "cp " $1 " /tmp/."}'  | sort -u >> $OUTPUT_DIR/stage3_filelist
      cd $fdsroot/Verification
      source $OUTPUT_DIR/stage3_filelist

      # If errors encountered in validation mode, then email status and exit
      if [ $FIREBOT_MODE == "validation" ] ; then
         email_build_status 'Validationbot' 'Validation'
         set_files_world_readable
         exit
      fi
   fi
}

#  ==================================
#  = Stage 4a - Compile FDS release =
#  ==================================

compile_fds()
{
   # Clean and compile FDS
   cd $fdsroot/FDS_Compilation/intel_${platform}_64
   make -f ../makefile clean &> /dev/null
   ./make_fds.sh &> $OUTPUT_DIR/stage4a
}

check_compile_fds()
{
   # Check for errors in FDS compilation
   cd $fdsroot/FDS_Compilation/intel_${platform}_64
   if [ -e "fds_intel_${platform}_64" ]
   then
      stage4a_success=true
   else
      echo "Errors from Stage 4a - Compile FDS release:" >> $ERROR_LOG
      cat $OUTPUT_DIR/stage4a >> $ERROR_LOG
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
   cd $fdsroot/FDS_Compilation/mpi_intel_${platform}_64$IB
   make -f ../makefile clean &> /dev/null
   ./make_fds.sh &> $OUTPUT_DIR/stage4b
}

check_compile_fds_mpi()
{
   # Check for errors in FDS MPI compilation
   cd $fdsroot/FDS_Compilation/mpi_intel_${platform}_64$IB
   if [ -e "fds_mpi_intel_${platform}_64$IB" ]
   then
      stage4b_success=true
   else
      echo "Errors from Stage 4b - Compile FDS MPI release:" >> $ERROR_LOG
      cat $OUTPUT_DIR/stage4b >> $ERROR_LOG
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
   cd $fdsroot/SMV/Build/LIBS/lib_${platform}_intel_64
   echo 'Building Smokeview libraries:' >> $OUTPUT_DIR/stage5pre 2>&1
   ./makelibs.sh >> $OUTPUT_DIR/stage5pre 2>&1
   echo "" >> $OUTPUT_DIR/stage5pre 2>&1
}

check_smv_utilities()
{
   # nothing to check
   stage5pre_success=true
}

#  =================================================================
#  = Stage 5 - Run verification or validation cases (release mode) =
#  =================================================================

check_cases_release()
{
   # Scan for and report any errors in FDS cases
   cd $1

   if [[ `grep -rI 'Run aborted' ${FIREBOT_DIR}/output/stage5` == "" ]] && \
      [[ `grep -rI Segmentation *` == "" ]] && \
      [[ `grep -rI ERROR: *` == "" ]] && \
      [[ `grep -rI 'STOP: Numerical' *` == "" ]] && \
      [[ `grep -rI -A 20 forrtl *` == "" ]]
   then
      stage5_success=true
   else
      grep -rI 'Run aborted' $OUTPUT_DIR/stage5 >> $OUTPUT_DIR/stage5_errors
      grep -rI Segmentation * >> $OUTPUT_DIR/stage5_errors
      grep -rI ERROR: * >> $OUTPUT_DIR/stage5_errors
      grep -rI 'STOP: Numerical' * >> $OUTPUT_DIR/stage5_errors
      grep -rI -A 20 forrtl * >> $OUTPUT_DIR/stage5_errors
      
      echo "Errors from Stage 5 - Run ${2} cases (release mode):" >> $ERROR_LOG
      cat $OUTPUT_DIR/stage5_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG

      # If errors encountered in validation mode, then email status and exit
      if [ $FIREBOT_MODE == "validation" ] ; then
         email_build_status 'Validationbot' 'Validation'
         # Stop all Validationbot cases in queue system
         qdel all
         set_files_world_readable
         exit
      fi
   fi
}

wait_cases_release_end()
{
   # Scans qstat and waits for cases to end
   while [[ `qstat | awk '{print $3}' | grep $(whoami) ` != '' ]]; do
      JOBS_REMAINING=`qstat | awk '{print $3}' | grep $(whoami) | wc -l`
      echo "Waiting for ${JOBS_REMAINING} ${1} cases to complete." >> $OUTPUT_DIR/stage5
      TIME_LIMIT_STAGE="5"
      check_time_limit
      if [ $FIREBOT_MODE == "validation" ] ; then
         check_cases_release $fdsroot/Validation 'validation'
         sleep 300
      fi
      sleep 60
   done
}

run_verification_cases_release()
{
   # Start running all FDS verification cases
   cd $fdsroot/Verification
   # Run FDS with 1 OpenMP thread
   echo 'Running FDS verification cases:' >> $OUTPUT_DIR/stage5
   ./Run_FDS_Cases.sh -o 1 -q $QUEUE >> $OUTPUT_DIR/stage5 2>&1
   echo "" >> $OUTPUT_DIR/stage5 2>&1

   # Wait for all verification cases to end
   wait_cases_release_end 'verification'
}

run_validation_cases_release()
{
   #  ===================================
   #  = Run selected FDS validation set =
   #  ===================================

   for SET in ${CURRENT_VALIDATION_SETS[*]}
   do
      cd $fdsroot/Validation/"$SET"

      # Start running FDS validation cases
      echo "Running FDS validation cases:" >> $OUTPUT_DIR/stage5
      echo "Validation Set: ${SET}" >> $OUTPUT_DIR/stage5
      echo "" >> $OUTPUT_DIR/stage5 2>&1
      ./Run_All.sh -q $QUEUE >> $OUTPUT_DIR/stage5 2>&1
      echo "" >> $OUTPUT_DIR/stage5 2>&1
   done

   # Wait for validation cases to end
   wait_cases_release_end 'validation'
}

commit_validation_results()
{
   for SET in ${CURRENT_VALIDATION_SETS[*]}
   do
      # Copy new FDS files from Current_Results to FDS_Output_Files using Process_Output.csh script for the validation set
      cd $fdsroot/Validation/"$SET"/FDS_Output_Files
      ./Process_Output.csh
   done

   # cd to GIT root
   cd $fdsroot

   # Commit new validation results
   svn commit -m "Validationbot: Update validation results for: ${CURRENT_VALIDATION_SETS[*]}" &> /dev/null
}

#  ================================
#  = Stage 6a - Compile SMV debug =
#  ================================

compile_smv_db()
{
   # Clean and compile SMV debug
   cd $fdsroot/SMV/Build/intel_${platform}_64
   ./make_smv_db.sh &> $OUTPUT_DIR/stage6a
}

check_compile_smv_db()
{
   # Check for errors in SMV debug compilation
   cd $fdsroot/SMV/Build/intel_${platform}_64
   if [ -e "smokeview_${platform}_64_db" ]
   then
      stage6a_success=true
   else
      echo "Errors from Stage 6a - Compile SMV debug:" >> $ERROR_LOG
      cat $OUTPUT_DIR/stage6a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # grep -v 'feupdateenv ...' ignores a known FDS MPI compiler warning (http://software.intel.com/en-us/forums/showthread.php?t=62806)
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6a | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 6a - Compile SMV debug:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6a | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ==================================
#  = Stage 6c - Compile SMV release =
#  ==================================

compile_smv()
{
   # Clean and compile SMV
   cd $fdsroot/SMV/Build/intel_${platform}_64
   ./make_smv.sh &> $OUTPUT_DIR/stage6c
}

check_compile_smv()
{
   # Check for errors in SMV release compilation
   cd $fdsroot/SMV/Build/intel_${platform}_64
   if [ -e "smokeview_${platform}_64" ]
   then
      stage6c_success=true
   else
      echo "Errors from Stage 6c - Compile SMV release:" >> $ERROR_LOG
      cat $OUTPUT_DIR/stage6c >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # grep -v 'feupdateenv ...' ignores a known FDS MPI compiler warning (http://software.intel.com/en-us/forums/showthread.php?t=62806)
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6c | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 6c - Compile SMV release:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6c | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ================================
#  = Stage 6e - Make FDS pictures =
#  ================================

make_fds_pictures()
{
   # Run Make FDS Pictures script
   cd $fdsroot/Verification
   ./Make_FDS_Pictures.sh &> $OUTPUT_DIR/stage6e
}

check_fds_pictures()
{
   # Scan for and report any errors in make FDS pictures process
   cd $FIREBOT_DIR
   if [[ `grep -I -E "Segmentation|Error" $OUTPUT_DIR/stage6e` == "" ]]
   then
      stage6e_success=true
   else
      grep -I -E -A 5 -B 5 "Segmentation|Error" $OUTPUT_DIR/stage6e > $OUTPUT_DIR/stage6e_errors
      
      echo "Errors from Stage 6e - Make FDS pictures:" >> $ERROR_LOG
      cat $OUTPUT_DIR/stage6e_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Scan for and report any warnings in make FDS pictures process
   cd $FIREBOT_DIR
   if [[ `grep -I -E "Warning" $OUTPUT_DIR/stage6e` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 6e - Make FDS pictures:" >> $WARNING_LOG
      grep -I -E "Warning" $OUTPUT_DIR/stage6e >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ====================
#  = Stage 7 - Matlab =
#  ====================

# Functions to check for an available Matlab license

run_matlab_license_test()
{
   # Run simple test to see if Matlab license is available
   cd $fdsroot/Utilities/Matlab
   matlab -r "try, disp('Running Matlab License Check'), catch, disp('License Error'), err = lasterror, err.message, err.stack, end, exit" &> $OUTPUT_DIR/stage7_matlab_license
}

scan_matlab_license_test()
{
   # Check for failed license
   if [[ `grep "License checkout failed" $OUTPUT_DIR/stage7_matlab_license` == "" ]]
   then
      # Continue along
      :
   else
      TIME_LIMIT_STAGE="7"
      check_time_limit
      # Wait 5 minutes until retry
      sleep 300
      check_matlab_license_server
   fi
}

check_matlab_license_server()
{
   run_matlab_license_test
   scan_matlab_license_test
}

#  ============================================================
#  = Stage 7a - Matlab plotting and statistics (verification) =
#  ============================================================

run_matlab_verification()
{
   # Run Matlab plotting script
   cd $fdsroot/Utilities/Matlab
   matlab -r "try, disp('Running Matlab Verification script'), FDS_verification_script, catch, disp('Error'), err = lasterror, err.message, err.stack, end, exit" &> $OUTPUT_DIR/stage7a_verification
}

check_matlab_verification()
{
   # Scan for and report any errors in Matlab scripts
   cd $FIREBOT_DIR
   if [[ `grep -A 50 "Error" $OUTPUT_DIR/stage7a_verification` == "" ]]
   then
      stage7a_success=true
   else
      echo "Warnings from Stage 7a - Matlab plotting and statistics (verification):" >> $WARNING_LOG
      grep -A 50 "Error" $OUTPUT_DIR/stage7a_verification >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

check_verification_stats()
{
   # Check for existence of verification statistics output file
   cd $fdsroot/Utilities/Matlab
   if [ -e "FDS_verification_scatterplot_output.csv" ]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 7a - Matlab plotting and statistics (verification):" >> $WARNING_LOG
      echo "Error: The verification statistics output file does not exist." >> $WARNING_LOG
      echo "Expected the file Utilities/Matlab/FDS_verification_scatterplot_output.csv" >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi

   # Scan for and report warnings for any verification cases that are outside of their specified error tolerance
   cd $fdsroot/Utilities/Matlab
   if [[ `grep "Out of Tolerance" FDS_verification_scatterplot_output.csv` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 7a - Matlab plotting and statistics (verification):" >> $WARNING_LOG
      echo "The following cases are outside of their specified error tolerance:" >> $WARNING_LOG
      echo "" >> $WARNING_LOG
      grep "Out of Tolerance" FDS_verification_scatterplot_output.csv | sed G >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi

   # Scan for and report any case warnings in Matlab scripts
   cd $FIREBOT_DIR
   if [[ `grep "Matlab Warning" $OUTPUT_DIR/stage7a_verification` == "" ]]
   then
      # Continue along
      :
   else
      echo "Warnings from Stage 7a - Matlab plotting and statistics (verification):" >> $WARNING_LOG
      grep "Matlab Warning" $OUTPUT_DIR/stage7a_verification >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ==========================================================
#  = Stage 7b - Matlab plotting and statistics (validation) =
#  ==========================================================

run_matlab_validation()
{
   # Run Matlab plotting script
   cd $fdsroot/Utilities/Matlab
   matlab -r "try, disp('Running Matlab Validation script'), FDS_validation_script, catch, disp('Error'), err = lasterror, err.message, err.stack, end, exit" &> $OUTPUT_DIR/stage7b_validation
}

check_matlab_validation()
{
   # Scan for and report any errors in Matlab scripts
   cd $FIREBOT_DIR
   if [[ `grep -A 50 "Error" $OUTPUT_DIR/stage7b_validation` == "" ]]
   then
      stage7b_success=true
   else
      echo "Warnings from Stage 7b - Matlab plotting and statistics (validation):" >> $WARNING_LOG
      grep -A 50 "Error" $OUTPUT_DIR/stage7b_validation >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

archive_validation_stats()
{
   cd $fdsroot/Utilities/Matlab

   STATS_FILE_BASENAME=FDS_validation_scatterplot_output
   CURRENT_STATS_FILE=$fdsroot/Utilities/Matlab/${STATS_FILE_BASENAME}.csv

   if [ -e ${CURRENT_STATS_FILE} ]
   then
      # Archive stats to Firebot history
      cp ${CURRENT_STATS_FILE} "$HISTORY_DIR/${GIT_REVISION}_${STATS_FILE_BASENAME}.csv"

   else
      echo "Warnings from Stage 7b - Matlab plotting and statistics (validation):" >> $WARNING_LOG
      echo "Warning: The validation statistics output file does not exist." >> $WARNING_LOG
      echo "Expected the file Utilities/Matlab/FDS_validation_scatterplot_output.csv" >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

validation_svn_stats()
{
   # Output a LaTeX file with a table of the FDS validation sets and their corresponding GIT information
   cd $fdsroot/Utilities/Scripts
   ./validation_git_stats.sh
}

#  ======================================
#  = Stage 7c - FDS run time statistics =
#  ======================================

generate_timing_stats()
{
   cd $fdsroot/Utilities/Scripts
   ./fds_timing_stats.sh
}

archive_timing_stats()
{
   cd $fdsroot/Utilities/Scripts
   cp fds_timing_stats.csv "$HISTORY_DIR/${GIT_REVISION}_timing.csv"
}

#  ==================================
#  = Stage 8 - Build FDS-SMV guides =
#  ==================================

check_guide()
{
   # Scan for and report any errors or warnings in build process for guides
   cd $FIREBOT_DIR
   if [[ `grep -I "successfully" $1` == "" ]]
   then
      # There were errors/warnings in the guide build process
      echo "Warnings from Stage 8 - Build FDS-SMV Guides:" >> $WARNING_LOG
      echo $3 >> $WARNING_LOG # Name of guide
      cat $1 >> $WARNING_LOG # Contents of log file
      echo "" >> $WARNING_LOG
   else
      # Guide built successfully; there were no errors/warnings
      # Copy guide to Firebot's local website
      cp $2 /var/www/html/firebot/manuals/
      cp $2 $NEWGUIDE_DIR/.
      chmod 664 $NEWGUIDE_DIR/$2
   fi
}

make_fds_user_guide()
{
   cd $fdsroot/Manuals/FDS_User_Guide

   # Build FDS User Guide
   ./make_guide.sh &> $OUTPUT_DIR/stage8_fds_user_guide

   # Check guide for completion and copy to website if successful
   check_guide $OUTPUT_DIR/stage8_fds_user_guide $fdsroot/Manuals/FDS_User_Guide/FDS_User_Guide.pdf 'FDS User Guide'
}

make_fds_technical_guide()
{
   cd $fdsroot/Manuals/FDS_Technical_Reference_Guide

   # Build FDS Technical Guide
   ./make_guide.sh &> $OUTPUT_DIR/stage8_fds_technical_guide

   # Check guide for completion and copy to website if successful
   check_guide $OUTPUT_DIR/stage8_fds_technical_guide $fdsroot/Manuals/FDS_Technical_Reference_Guide/FDS_Technical_Reference_Guide.pdf 'FDS Technical Reference Guide'
}

make_fds_verification_guide()
{
   cd $fdsroot/Manuals/FDS_Verification_Guide

   # Build FDS Verification Guide
   ./make_guide.sh &> $OUTPUT_DIR/stage8_fds_verification_guide

   # Check guide for completion and copy to website if successful
   check_guide $OUTPUT_DIR/stage8_fds_verification_guide $fdsroot/Manuals/FDS_Verification_Guide/FDS_Verification_Guide.pdf 'FDS Verification Guide'
}

make_fds_validation_guide()
{
   cd $fdsroot/Manuals/FDS_Validation_Guide

   # Build FDS Validation Guide
   ./make_guide.sh &> $OUTPUT_DIR/stage8_fds_validation_guide

   # Check guide for completion and copy to website if successful
   check_guide $OUTPUT_DIR/stage8_fds_validation_guide $fdsroot/Manuals/FDS_Validation_Guide/FDS_Validation_Guide.pdf 'FDS Validation Guide'
}

make_fds_configuration_management_plan()
{
   cd $fdsroot/Manuals/FDS_Configuration_Management_Plan

   # Build FDS Configuration Management Plan
   ./make_guide.sh &> $OUTPUT_DIR/stage8_fds_configuration_management_plan

   # Check guide for completion and copy to website if successful
   check_guide $OUTPUT_DIR/stage8_fds_configuration_management_plan $fdsroot/Manuals/FDS_Configuration_Management_Plan/FDS_Configuration_Management_Plan.pdf 'FDS Configuration Management Plan'
}

#  =====================================================
#  = Build status reporting - email and save functions =
#  =====================================================

save_build_status()
{
   cd $FIREBOT_DIR
   # Save status outcome of build to a text file
   if [[ -e $WARNING_LOG && -e $ERROR_LOG ]]
   then
     echo "" >> $ERROR_LOG
     cat $WARNING_LOG >> $ERROR_LOG
     echo "Build failure and warnings for Revision ${GIT_REVISION}." > "$HISTORY_DIR/${GIT_REVISION}.txt"
     cat $ERROR_LOG > "$HISTORY_DIR/${GIT_REVISION}_errors.txt"

   # Check for errors only
   elif [ -e $ERROR_LOG ]
   then
      echo "Build failure for Revision ${GIT_REVISION}." > "$HISTORY_DIR/${GIT_REVISION}.txt"
      cat $ERROR_LOG > "$HISTORY_DIR/${GIT_REVISION}_errors.txt"

   # Check for warnings only
   elif [ -e $WARNING_LOG ]
   then
      echo "Revision ${GIT_REVISION} has warnings." > "$HISTORY_DIR/${GIT_REVISION}.txt"
      cat $WARNING_LOG > "$HISTORY_DIR/${GIT_REVISION}_warnings.txt"

   # No errors or warnings
   else
      echo "Build success! Revision ${GIT_REVISION} passed all build tests." > "$HISTORY_DIR/${GIT_REVISION}.txt"
   fi
}

email_build_status()
{
   cd $FIREBOT_DIR
   # Check for warnings and errors
   if [[ -e $WARNING_LOG && -e $ERROR_LOG ]]
   then
     # Send email with failure message and warnings, body of email contains appropriate log file
     mail -s "[${1}@$hostname] ${2} failure and warnings for Revision ${GIT_REVISION}." $mailToFDS < $ERROR_LOG > /dev/null

   # Check for errors only
   elif [ -e $ERROR_LOG ]
   then
      # Send email with failure message, body of email contains error log file
      mail -s "[${1}@$hostname] ${2} failure for Revision ${GIT_REVISION}." $mailToFDS < $ERROR_LOG > /dev/null

   # Check for warnings only
   elif [ -e $WARNING_LOG ]
   then
      # Send email with success message, include warnings
      mail -s "[${1}@$hostname] ${2} success, with warnings. Revision ${GIT_REVISION} passed all build tests." $mailToFDS < $WARNING_LOG > /dev/null

   # No errors or warnings
   else
#  upload guides to a google drive directory
      cd $FIREBOT_DIR
      $UPLOADGUIDES > /dev/null

      # Send success message with links to nightly manuals
      stop_time=`date`
      echo "-------------------------------" >> $TIME_LOG
      echo "Host OS: Linux " >> $TIME_LOG
      echo "Host Name: $hostname " >> $TIME_LOG
      if [ $FIREBOT_MODE == "validation" ] ; then
         echo "Validation Set(s): ${CURRENT_VALIDATION_SETS[*]} " >> $TIME_LOG
      fi
      echo "Start Time: $start_time " >> $TIME_LOG
      echo "Stop Time: $stop_time " >> $TIME_LOG
      echo "-------------------------------" >> $TIME_LOG
      echo "Nightly Manuals (private):  http://blaze.nist.gov/firebot" >> $TIME_LOG
      echo "Nightly Manuals  (public):  http://goo.gl/n1Q3WH" >> $TIME_LOG
      echo "-------------------------------" >> $TIME_LOG
      mail -s "[${1}@$hostname] ${2} success! Revision ${GIT_REVISION} passed all build tests." $mailToFDS < $TIME_LOG > /dev/null
   fi
}

#  ============================
#  = Primary script execution =
#  ============================

hostname=`hostname`
start_time=`date`

### Clean up on start ###
clean_firebot_metafiles

### Stage 1 ###
clean_git_repo
do_git_checkout
check_git_checkout
# Only run if -s option (skip GIT properties) is not used
#*** need to port following to git
#if [[ ! $SKIP_GIT_PROPS_AND_GIT_BUMP ]] ; then
#   fix_git_properties
#fi
archive_compiler_version

### Stage 2a ###
compile_fds_db
check_compile_fds_db
#inspect_fds_db
#check_inspect_fds_db

### Stage 2b ###
compile_fds_mpi_db
check_compile_fds_mpi_db

### Stage 3 ###
# Only run if firebot is in "validation" mode
if [ $FIREBOT_MODE == "validation" ] ; then
   generate_validation_set_list
fi

# Depends on successful FDS debug compile
if [[ $stage2a_success && $stage2b_success && $FIREBOT_MODE == "verification" ]] ; then
   run_verification_cases_debug
   check_cases_debug $fdsroot/Verification 'verification'

elif [[ $stage2a_success && $stage2b_success && $FIREBOT_MODE == "validation" ]] ; then
   run_validation_cases_debug
   check_cases_debug $fdsroot/Validation 'validation'
fi

# clean debug stage
cd $fdsroot
git clean -dxf &> /dev/null

### Stage 4a ###
compile_fds
check_compile_fds

### Stage 4b ###
compile_fds_mpi
check_compile_fds_mpi

### Stage 5pre ###
# Only run if firebot is in "verification" mode
if [ $FIREBOT_MODE == "verification" ] ; then
   compile_smv_utilities
   check_smv_utilities
fi

### Stage 5 ###
# Depends on successful FDS compile
if [[ $stage4a_success && $stage4b_success && $FIREBOT_MODE == "verification" ]] ; then
   run_verification_cases_release
   check_cases_release $fdsroot/Verification 'verification'

elif [[ $stage4a_success && $stage4b_success && $FIREBOT_MODE == "validation" ]] ; then
   run_validation_cases_release
   check_cases_release $fdsroot/Validation 'validation'
fi

# Depends on successful run of validation cases in debug and release mode
if [[ $stage3_success && $stage5_success && $FIREBOT_MODE == "validation" ]] ; then
   commit_validation_results
fi

#  ======================================================================
#  = Only run the following stages if firebot is in "verification" mode =
#  ======================================================================

if [ $FIREBOT_MODE == "verification" ] ; then
   ### Stage 6a ###
   compile_smv_db
   check_compile_smv_db

   ### Stage 6c ###
   compile_smv
   check_compile_smv

   ### Stage 6e ###
   # Depends on successful SMV compile
   if [[ $stage6c_success ]] ; then
      make_fds_pictures
      check_fds_pictures
   fi

   if [ $platform == "linux" ] ; then
   ### Stage 7a ###
      check_matlab_license_server
      run_matlab_verification
      check_matlab_verification
      check_verification_stats

   ### Stage 7b ###
      check_matlab_license_server
      run_matlab_validation
      check_matlab_validation
      archive_validation_stats
      validation_svn_stats

   ### Stage 7c ###
      generate_timing_stats
      archive_timing_stats

   ### Stage 8 ###
      make_fds_user_guide
      make_fds_verification_guide
      make_fds_technical_guide
      make_fds_validation_guide
      make_fds_configuration_management_plan
   fi
fi

### Wrap up and report results ###
set_files_world_readable
if [ $FIREBOT_MODE == "verification" ] ; then
   save_build_status
   email_build_status 'Firebot' 'Build'
elif [ $FIREBOT_MODE == "validation" ] ; then
   email_build_status 'Validationbot' 'Validation'
fi

