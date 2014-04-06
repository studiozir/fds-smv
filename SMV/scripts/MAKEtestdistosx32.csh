#!/bin/csh -f
set revision=$1
set SVNROOT=~/FDS-SMV
set REMOTESVNROOT=FDS-SMV
set OSXHOST=$2

set BACKGROUNDDIR=$REMOTESVNROOT/Utilities/background/intel_osx_32
set SMVDIR=$REMOTESVNROOT/SMV/Build/intel_osx_32
set SMZDIR=$REMOTESVNROOT/Utilities/smokezip/intel_osx_32
set SMDDIR=$REMOTESVNROOT/Utilities/smokediff/intel_osx_32
set WINDDIR=$REMOTESVNROOT/Utilities/wind2fds/intel_osx_32
set FORBUNDLE=$SVNROOT/SMV/for_bundle
set OSXDIR=smv_test\_$revision\_osx32
set UPDATER=$SVNROOT/Utilities/Scripts/make_updater.sh

cd $FORBUNDLE/uploads

rm -rf $OSXDIR
mkdir -p $OSXDIR
mkdir -p $OSXDIR/bin
mkdir -p $OSXDIR/Documentation

cp $FORBUNDLE/objects.svo $OSXDIR/bin/.
cp $FORBUNDLE/*.po $OSXDIR/bin/.
scp $OSXHOST\:$BACKGROUNDDIR/background $OSXDIR/bin/.
scp $OSXHOST\:$SMVDIR/smokeview_osx_test_32 $OSXDIR/bin/smokeview
scp $OSXHOST\:$SMZDIR/smokezip_osx_32 $OSXDIR/bin/smokezip
scp $OSXHOST\:$SMDDIR/smokediff_osx_32 $OSXDIR/bin/smokediff
scp $OSXHOST\:$SMDDIR/wind2fds_osx_32 $OSXDIR/bin/wind2fds
rm -f $OSXDIR.tar $OSXDIR.tar.gz
cd $OSXDIR
tar cvf ../$OSXDIR.tar .
cd ..
gzip $OSXDIR.tar
$UPDATER OSX 32 $revision $OSXDIR.tar.gz $OSXDIR.sh FDS/FDS6 test
