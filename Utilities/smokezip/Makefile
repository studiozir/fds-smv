SOURCE_DIR = ../../../SMV/source/
BUILD_DIR = ../../../SMV/Build
LIB_DIR = ../../../SMV/Build/LIBS
INC2_DIR = -I $(SOURCE_DIR)/include2  -I $(SOURCE_DIR)/shared -I $(SOURCE_DIR)/smokezip 
INC_DIR =  -I $(SOURCE_DIR)/include -I $(SOURCE_DIR)/shared -I $(SOURCE_DIR)/smokezip 
FILTERC =
FILTERF =

VPATH = $(SOURCE_DIR)/smokezip ../../../FDS_Source $(SOURCE_DIR)/shared $(SOURCE_DIR)/smokeview 
bin = .

FORTLIBDIR = /opt/intel/composerxe/lib

# Definition of the object variables

obj =    main.o CNV3dsmoke.o CNVboundary.o CNVpart.o CNVplot3d.o CNVslice.o assert.o csphere.o dmalloc.o lightsmoke.o smv_endian.o histogram.o readfiles.o utilities.o isobox.o file_util.o string_util.o threader.o compress.o fdsmodules.o gsmv.o getdata.o getsizes.o 
objwin = $(obj:.o=.obj)

# main has to be compiled without optimization (on a Windows PC) otherwise errors occcur
main.obj: CFLAGS = -Od /nologo -D WIN32 -D pp_WIN_INTEL

#*** General Purpose Rules ***

no_target:
	@echo \******** You did not specify a make target \********
	@echo Use one of targets found in the Makefile

.SUFFIXES: .F90 .c .obj .o .f90 .cpp

.c.obj:
	$(CC) -c $(CFLAGS) $(FILTERC) $(INC_DIR) $<
.c.o:
	$(CC) -c $(CFLAGS) $(FILTERC) $(INC2_DIR) $<
.F90.o:
	$(FC) -c $(FFLAGS) $(FILTERF) $<
.f90.obj:
	$(FC) -c $(FFLAGS) $(FILTERF) $<
.f90.o:
	$(FC) -c $(FFLAGS) $(FILTERF) $<



# ********  rules for each platform supported *************

intel_win_64 : CFLAGS    = -Od /nologo -D WIN32 -D PTW32_STATIC_LIB -D X64 -D pp_WIN_INTEL
intel_win_64 : FFLAGS    = -Od /nologo -fpp -D pp_cvf -D X64 /iface:stdref /fpscomp:general
intel_win_64 : CC        = icl
intel_win_64 : CPP       = icl
intel_win_64 : FC        = ifort
intel_win_64 : exe       = smokezip_win_64.exe

intel_win_64 : $(objwin)
	$(CPP) -o $(bin)/$(exe) $(objwin) $(LIB_DIR)/lib_win_intel_64/pthreads.lib $(LIB_DIR)/lib_win_intel_64/zlib.lib

# ------------- gcc Linux ----------------
#  gcc linux

gcc_linux_64 : FFLAGS    = -O0 -m64 -x f95-cpp-input -D pp_GCC -D pp_noappend -ffree-form -frecord-marker=4
gcc_linux_64 : CFLAGS    = -O0 -m64 -D pp_LINUX64
gcc_linux_64 : LFLAGS    = -m64
gcc_linux_64 : CC        = gcc
gcc_linux_64 : CPP       = g++
gcc_linux_64 : FC        = gfortran
gcc_linux_64 : exe       = smokezip_linux_64

gcc_linux_64 : $(obj)
	$(CPP) -o $(bin)/$(exe) $(obj) $(LFLAGS) -lgfortran -L $(LIB_DIR)/lib_linux_gcc_64 -lz -lpthread

# ------------- Linux 64 ----------------
#  64 bit linux
LINUXFORTLIBS_64=$(FORTLIBDIR)/intel64/libifcore.a

intel_linux_64 : FFLAGS    = -O2 -m64 -fpp -D pp_noappend -D pp_LINUX64
intel_linux_64 : CFLAGS    = -O2 -m64 -D pp_LINUX64
intel_linux_64 : CC        = icc
intel_linux_64 : CPP       = icc
intel_linux_64 : FC        = ifort
intel_linux_64 : exe       = smokezip_linux_64

intel_linux_64 : $(obj)
	$(CPP) -o $(bin)/$(exe) -static-intel $(obj) $(LINUXFORTLIBS_64) -L $(LIB_DIR)/lib_linux_intel_64 -lz -lpthread

	
OSXFORTLIBS=$(FORTLIBDIR)/libifcoremt.a $(FORTLIBDIR)/libimf.a $(FORTLIBDIR)/libirc.a $(FORTLIBDIR)/libsvml.a

# ------------- OSX 64 ----------------
#  64 bit OSX

intel_osx_64 : FFLAGS    = -O2 -m64 -fpp -D pp_OSX64
intel_osx_64 : CFLAGS    = -O2 -m64 -D pp_OSX64
intel_osx_64 : CC        = icc
intel_osx_64 : CPP       = icc
intel_osx_64 : FC        = ifort
intel_osx_64 : exe       = smokezip_osx_64

intel_osx_64 : $(obj)
	$(CPP) -o $(bin)/$(exe) -m64 -static-intel $(obj)  -mmacosx-version-min=10.4 $(OSXFORTLIBS) -L $(LIB_DIR)/lib_osx_intel_64 -lz -lpthread
