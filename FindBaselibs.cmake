
# Set BASEDIR to non-existant path if it is not already set
#set (BASEDIR /does-not-exist CACHE PATH "Path to installed baselibs _including_ OS subdirectory (Linux or Darwin).")
set (BASEDIR "" CACHE PATH "Path to installed baselibs _including_ OS subdirectory (Linux or Darwin).")
set (Baselibs_FOUND FALSE)

if (BASEDIR)
  if (IS_DIRECTORY ${BASEDIR}/lib)
    set (Baselibs_FOUND TRUE)
    message (STATUS "BASEDIR: ${BASEDIR}")
  endif ()
else ()
  message (STATUS "WARNING: BASEDIR not specified. Please use cmake ... -DBASEDIR=<path>.")
endif ()

if (ESMA_SDF)
   message (FATAL_ERROR "ERROR: -hdf option was thought to be obsolete when CMake was crafted.")
endif ()

if (Baselibs_FOUND)

  link_directories (${BASEDIR}/lib)

  # Add path to GFE packages
  list (APPEND CMAKE_PREFIX_PATH ${BASEDIR})

  #------------------------------------------------------------------
  # netcdf
  # The following command provides the list of libraries that netcdf
  # uses.  Unfortunately it also includes the library path and "-l"
  # prefixes, which CMake handles in a different manner. So we need so
  # strip off that item from the list
  execute_process (
    COMMAND ${BASEDIR}/bin/nf-config --flibs
    OUTPUT_VARIABLE LIB_NETCDF
    )

  string(REGEX MATCHALL " -l[^ ]*" _full_libs "${LIB_NETCDF}")
  set (NETCDF_LIBRARIES_OLD)
  foreach (lib ${_full_libs})
    string (REPLACE "-l" "" _tmp ${lib})
    string (STRIP ${_tmp} _tmp)
    list (APPEND NETCDF_LIBRARIES_OLD ${_tmp})
  endforeach()

  list (REVERSE NETCDF_LIBRARIES_OLD)
  list (REMOVE_DUPLICATES NETCDF_LIBRARIES_OLD)
  list (REVERSE NETCDF_LIBRARIES_OLD)

  add_definitions(-DHAS_NETCDF4)
  add_definitions(-DHAS_NETCDF3)
  add_definitions(-DH5_HAVE_PARALLEL)
  add_definitions(-DNETCDF_NEED_NF_MPIIO)
  add_definitions(-DHAS_NETCDF3)
  #------------------------------------------------------------------

  set (INC_HDF5 ${BASEDIR}/include/hdf5)
  set (INC_NETCDF ${BASEDIR}/include/netcdf)
  set (INC_HDF ${BASEDIR}/include/hdf)
  set (INC_ESMF ${BASEDIR}/include/esmf)

  find_package(GFTL REQUIRED)
  find_package(GFTL_SHARED REQUIRED)
  find_package(FARGPARSE QUIET)
  find_package(YAFYAML REQUIRED)
  find_package(PFLOGGER REQUIRED)

  # Need to do a bit of kludgy stuff here to allow Fortran linker to
  # find standard C and C++ libraries used by ESMF.
  # _And_ ESMF uses libc++ on some configs and libstdc++ on others.
  if (APPLE)
    if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
       set (stdcxx libc++.dylib)
    else () # assume gcc
      execute_process (COMMAND ${CMAKE_CXX_COMPILER} --print-file-name=libstdc++.dylib OUTPUT_VARIABLE stdcxx OUTPUT_STRIP_TRAILING_WHITESPACE)
      execute_process (COMMAND ${CMAKE_C_COMPILER} --print-file-name=libgcc.a OUTPUT_VARIABLE libgcc OUTPUT_STRIP_TRAILING_WHITESPACE)
    endif()
  else ()
    execute_process (COMMAND ${CMAKE_CXX_COMPILER} --print-file-name=libstdc++.so OUTPUT_VARIABLE stdcxx OUTPUT_STRIP_TRAILING_WHITESPACE)
  endif ()

  # We must statically link ESMF on Apple due mainly to an issue with how Baselibs is built.
  # Namely, the esmf dylib libraries end up with the full *build* path on Darwin (which is in
  # src/esmf/lib/libO...) But we copy the dylib to $BASEDIR/lib. Thus, DYLD_LIBRARY_PATH gets
  # hosed. yay.
  if (APPLE)
     set (ESMF_LIBRARY ${BASEDIR}/lib/libesmf.a)
     set (ESMF_LIBRARY_PATH ${ESMF_LIBRARY})
  else ()
     set (ESMF_LIBRARY esmf_fullylinked)
     set (ESMF_LIBRARY_PATH ${ESMF_ROOT}/lib/lib${ESMF_LIBRARY}.so)
  endif ()

  set (NETCDF_LIBRARIES ${NETCDF_LIBRARIES_OLD})
  set (ESMF_LIBRARIES ${ESMF_LIBRARY} ${NETCDF_LIBRARIES} ${MPI_Fortran_LIBRARIES} ${MPI_CXX_LIBRARIES} ${stdcxx} ${libgcc})

  # Create targets
  # - NetCDF Fortran
  add_library(NetCDF::NetCDF_Fortran STATIC IMPORTED)
  set_target_properties(NetCDF::NetCDF_Fortran PROPERTIES
    IMPORTED_LOCATION ${BASEDIR}/lib/libnetcdff.a
    INTERFACE_INCLUDE_DIRECTORIES "${INC_NETCDF}"
    INTERFACE_LINK_LIBRARIES  "${NETCDF_LIBRARIES}"
    INTERFACE_LINK_DIRECTORIES "${BASEDIR}/lib"
    )
  set(NetCDF_Fortran_FOUND TRUE CACHE BOOL "NetCDF Fortran Found" FORCE)

  # - ESMF
  add_library(esmf STATIC IMPORTED)
  set_target_properties(esmf PROPERTIES
    IMPORTED_LOCATION ${ESMF_LIBRARY_PATH}
    INTERFACE_INCLUDE_DIRECTORIES "${INC_ESMF}"
    INTERFACE_LINK_LIBRARIES  "${ESMF_LIBRARIES}"
    INTERFACE_LINK_DIRECTORIES "${BASEDIR}/lib"
    )
  set(esmf_FOUND TRUE CACHE BOOL "ESMF Found" FORCE)

  # BASEDIR.rc file does not have the arch
  string(REPLACE "/${CMAKE_SYSTEM_NAME}" "" BASEDIR_WITHOUT_ARCH ${BASEDIR})
  set(BASEDIR_WITHOUT_ARCH ${BASEDIR_WITHOUT_ARCH} CACHE STRING "BASEDIR without arch")
  mark_as_advanced(BASEDIR_WITHOUT_ARCH)
else ()
  # Find NetCDF. Note: CMake FindNetCDF only seems to find NetCDF-C..
  #find_package(NetCDF REQUIRED COMPONENTS C Fortran)
  find_package(NetCDF REQUIRED)
  # Set non-standard expected variables
  set(INC_NETCDF ${NETCDF_INCLUDE_DIRS})
  set(LIB_NETCDF ${NETCDF_LIBRARIES})
  set(INC_HDF5   ${NETCDF_INCLUDE_DIRS})
  set(INC_HDF    ${NETCDF_INCLUDE_DIRS})

  # Find NetCDF-Fortran the hard way
  find_program(NF_CONFIG NAMES "nf-config" DOC "Location of nf-config utility")

  # The following command provides the list of libraries that netcdf
  # uses.  Unfortunately it also includes the library path and "-l"
  # prefixes, which CMake handles in a different manner. So we need so
  # strip off that item from the list
  execute_process (
    COMMAND ${NF_CONFIG} --flibs
    OUTPUT_VARIABLE NETCDFF_LIBRARIES
    )

  string(REGEX MATCHALL " -l[^ ]*" _full_libs "${NETCDFF_LIBRARIES}")
  set (NETCDFF_LIBRARIES_OLD)
  foreach (lib ${_full_libs})
    string (REPLACE "-l" "" _tmp ${lib})
    string (STRIP ${_tmp} _tmp)
    list (APPEND NETCDFF_LIBRARIES_OLD ${_tmp})
  endforeach()

  list (REVERSE NETCDFF_LIBRARIES_OLD)
  list (REMOVE_DUPLICATES NETCDFF_LIBRARIES_OLD)
  list (REVERSE NETCDFF_LIBRARIES_OLD)
  set (NETCDFF_LIBRARIES ${NETCDF_LIBRARIES_OLD})

  add_definitions(-DHAS_NETCDF4)
  add_definitions(-DHAS_NETCDF3)
  add_definitions(-DH5_HAVE_PARALLEL)
  add_definitions(-DNETCDF_NEED_NF_MPIIO)
  add_definitions(-DHAS_NETCDF3)
  #------------------------------------------------------------------

  #find_package(GFTL REQUIRED)
  #find_package(GFTL_SHARED REQUIRED)
  #find_package(FARGPARSE QUIET)
  #find_package(YAFYAML REQUIRED)
  #find_package(PFLOGGER REQUIRED)

  # Need to do a bit of kludgy stuff here to allow Fortran linker to
  # find standard C and C++ libraries used by ESMF.
  # _And_ ESMF uses libc++ on some configs and libstdc++ on others.
  if (APPLE)
    if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
       set (stdcxx libc++.dylib)
    else () # assume gcc
      execute_process (COMMAND ${CMAKE_CXX_COMPILER} --print-file-name=libstdc++.dylib OUTPUT_VARIABLE stdcxx OUTPUT_STRIP_TRAILING_WHITESPACE)
      execute_process (COMMAND ${CMAKE_C_COMPILER} --print-file-name=libgcc.a OUTPUT_VARIABLE libgcc OUTPUT_STRIP_TRAILING_WHITESPACE)
    endif()
  else ()
    execute_process (COMMAND ${CMAKE_CXX_COMPILER} --print-file-name=libstdc++.so OUTPUT_VARIABLE stdcxx OUTPUT_STRIP_TRAILING_WHITESPACE)
  endif ()

  # If BASEDIR exists, set the expected HDF and HDF5 variables
  if(EXISTS ${BASEDIR}/include/hdf5)
    set (INC_HDF5 ${BASEDIR}/include/hdf5)
  endif()
  if(EXISTS ${BASEDIR}/include/hdf)
    set (INC_HDF ${BASEDIR}/include/hdf)
  endif()
  
  # Find GFTL 
  set(GFTL_IS_REQUIRED_ARG "REQUIRED" CACHE STRING "Argument in GFTL's find_package call")
  mark_as_advanced(GFTL_IS_REQUIRED_ARG)
  find_package(GFTL ${GFTL_IS_REQUIRED_ARG} CONFIG)
  
  # Find GFTL_SHARED
  set(GFTL_SHARED_IS_REQUIRED_ARG "REQUIRED" CACHE STRING "Argument in GFTL_SHARED's find_package call")
  mark_as_advanced(GFTL_SHARED_IS_REQUIRED_ARG)
  find_package(GFTL_SHARED ${GFTL_SHARED_IS_REQUIRED_ARG} CONFIG)
  
  # Find YAFYAML
  set(YAFYAML_IS_REQUIRED_ARG "REQUIRED" CACHE STRING "Argument in YAFYAML's find_package call")
  mark_as_advanced(YAFYAML_IS_REQUIRED_ARG)
  find_package(YAFYAML ${YAFYAML_IS_REQUIRED_ARG} CONFIG)
  
  # Find PFLOGGER
  set(PFLOGGER_IS_REQUIRED_ARG "REQUIRED" CACHE STRING "Argument in PFLOGGER's find_package call")
  mark_as_advanced(PFLOGGER_IS_REQUIRED_ARG)
  find_package(PFLOGGER ${PFLOGGER_IS_REQUIRED_ARG} CONFIG)
  
  # Find FARGPARSE
  set(FARGPARSE_IS_REQUIRED_ARG "" CACHE STRING "Argument in FARGPARSE's find_package call")
  mark_as_advanced(FARGPARSE_IS_REQUIRED_ARG)
  find_package(FARGPARSE ${FARGPARSE_IS_REQUIRED_ARG} CONFIG)
  
  # Find FLAP
  set(FLAP_IS_REQUIRED_ARG "REQUIRED" CACHE STRING "Argument in FLAP's find_package call")
  mark_as_advanced(FLAP_IS_REQUIRED_ARG)
  find_package(FLAP ${FLAP_IS_REQUIRED_ARG} CONFIG)
  # Set non-standard expected variables
  set (INC_FLAP ${FLAP_INCLUDE_DIRS})
  set (LIB_FLAP ${FLAP_LIBRARIES})
  
  # Find ESMF
  find_package(ESMF REQUIRED)
  # Set non-standard expected variables
  set(INC_ESMF ${ESMF_INCLUDE_DIRS})
  set(LIB_ESMF ${ESMF_LIBRARIES})
  
  # Find MPI
  find_package(MPI REQUIRED COMPONENTS C CXX Fortran)
  
  # Unit testing
  # option (PFUNIT "Activate pfunit based tests" OFF)
  find_package(PFUNIT QUIET)
  if (PFUNIT_FOUND)
    add_custom_target(tests COMMAND ${CMAKE_CTEST_COMMAND})
  endif ()

  # We must statically link ESMF on Apple due mainly to an issue with how Baselibs is built.
  # Namely, the esmf dylib libraries end up with the full *build* path on Darwin (which is in
  # src/esmf/lib/libO...) But we copy the dylib to $BASEDIR/lib. Thus, DYLD_LIBRARY_PATH gets
  # hosed. yay.
  #if (APPLE)
  #   set (ESMF_LIBRARY ${BASEDIR}/lib/libesmf.a)
  #   set (ESMF_LIBRARY_PATH ${ESMF_LIBRARY})
  #else ()
  #   set (ESMF_LIBRARY esmf_fullylinked)
  #   set (ESMF_LIBRARY_PATH ${ESMF_ROOT}/lib/libO/Linux.intel.64.mpi.default/lib${ESMF_LIBRARY}.so)
  #endif ()

  #set (NETCDF_LIBRARIES ${NETCDF_LIBRARIES_OLD})
  set (ESMF_LIBRARIES ${ESMF_LIBRARY} ${NETCDFF_LIBRARIES} ${MPI_Fortran_LIBRARIES} ${MPI_CXX_LIBRARIES} ${stdcxx} ${libgcc})

  # Find stuff for NetCDF-Fortran
  find_library(NETCDFF_LIBRARY
      libnetcdff.so
      DOC "The path to the directory containing \"libnetcdff.so\"."
      PATH_SUFFIXES "lib"
  )

  find_path(NETCDFF_INC_DIR
      netcdf.inc
      DOC "The path to the directory containing \"netcdf.inc\"."
      PATH_SUFFIXES "include"
  )

  get_filename_component(ESMF_LIB_DIR ${ESMF_LIBRARY} DIRECTORY)
  get_filename_component(NETCDFF_LIB_DIR ${NETCDFF_LIBRARY} DIRECTORY)

  # Create targets
  # - NetCDF Fortran
  add_library(NetCDF::NetCDF_Fortran STATIC IMPORTED)
  set_target_properties(NetCDF::NetCDF_Fortran PROPERTIES
    IMPORTED_LOCATION ${NETCDFF_LIB_DIR}/libnetcdff.so
    INTERFACE_INCLUDE_DIRECTORIES "${NETCDFF_INC_DIR}"
    INTERFACE_LINK_LIBRARIES  "${NETCDFF_LIBRARIES}"
    INTERFACE_LINK_DIRECTORIES "${NETCDFF_LIB_DIR}"
    )
  set(NetCDF_Fortran_FOUND TRUE CACHE BOOL "NetCDF Fortran Found" FORCE)

  # - ESMF
  add_library(esmf STATIC IMPORTED)
  set_target_properties(esmf PROPERTIES
    IMPORTED_LOCATION ${ESMF_LIBRARY}
    INTERFACE_INCLUDE_DIRECTORIES "${ESMF_INCLUDE_DIRS}"
    INTERFACE_LINK_LIBRARIES  "${ESMF_LIBRARIES}"
    INTERFACE_LINK_DIRECTORIES "${ESMF_LIB_DIR}"
    )
  set(esmf_FOUND TRUE CACHE BOOL "ESMF Found" FORCE)

  # BASEDIR.rc file does not have the arch
  string(REPLACE "/${CMAKE_SYSTEM_NAME}" "" BASEDIR_WITHOUT_ARCH ${BASEDIR})
  set(BASEDIR_WITHOUT_ARCH ${BASEDIR_WITHOUT_ARCH} CACHE STRING "BASEDIR without arch")
  mark_as_advanced(BASEDIR_WITHOUT_ARCH)
endif()

# Set the site variable
include(DetermineSite)


#=== Rest of this file is GCHP only ===

# Make Baselibs target
add_library(Baselibs INTERFACE)
target_include_directories(Baselibs INTERFACE ${NETCDF_INCLUDE_DIRS})
target_link_libraries(Baselibs INTERFACE 
    $<$<TARGET_EXISTS:gftl-shared>:gftl-shared>
    $<$<TARGET_EXISTS:fargparse>:fargparse>
    $<$<TARGET_EXISTS:FLAP>:FLAP>
    $<$<TARGET_EXISTS:pfunit>:pfunit>
    gftl ESMF
    MPI::MPI_C MPI::MPI_CXX MPI::MPI_Fortran
    $<$<BOOL:${OMP}>:OpenMP::OpenMP_Fortran>
  )
target_compile_options(Baselibs INTERFACE
	$<$<COMPILE_LANGUAGE:Fortran>:
		$<$<OR:$<CONFIG:Release>,$<CONFIG:RelWithDebInfo>,$<CONFIG:MinSizeRel>>:${GEOS_Fortran_FLAGS_RELEASE}>
  		$<$<CONFIG:Debug>:${GEOS_Fortran_FLAGS_DEBUG}>
	>
	""
  )
target_compile_definitions(Baselibs INTERFACE
  HAS_NETCDF4
  HAS_NETCDF3
  H5_HAVE_PARALLEL
  NETCDF_NEED_NF_MPIIO
  HAS_NETCDF3
  )
install(TARGETS Baselibs EXPORT MAPL-targets)
