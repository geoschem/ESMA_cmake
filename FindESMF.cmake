find_file(ESMF_MK
	esmf.mk
	DOC "The path to \"esmf.mk\" in your ESMF installation."
	PATH_SUFFIXES "lib"
)

if (EXISTS ${ESMF_MK})
    # Read esmf.mk
    file(READ ${ESMF_MK} ESMF_MK_CONTENTS)

    # Extract include directories from ESMF_F90COMPILEPATHS
    string(REGEX MATCH "ESMF_F90COMPILEPATHS=[^\n]*" ESMF_F90COMPILEPATHS "${ESMF_MK_CONTENTS}")    # get the ESMF_F90COMPILEPATHS= line in esmf.mk
    string(REGEX MATCHALL "-I[^ ]*" ESMF_INCLUDE_DIRS "${ESMF_F90COMPILEPATHS}")                    # extract list of -I/include/directories
    string(REPLACE "-I" "" ESMF_INCLUDE_DIRS "${ESMF_INCLUDE_DIRS}")                                # remove -I prefixes

    # Extract the directory with the esmf library from ESMF_F90ESMFLINKPATHS
    string(REGEX MATCH "ESMF_F90ESMFLINKPATHS=[^\n]*" ESMF_F90ESMFLINKPATHS "${ESMF_MK_CONTENTS}")  # get the ESMF_F90ESMFLINKPATHS= line in esmf.mk
    string(REGEX MATCHALL "-L[^ ]*" ESMF_LIBRARY_DIRECTORY "${ESMF_F90ESMFLINKPATHS}")              # extract -L/ESMF/library/directory
    string(REPLACE "-L" "" ESMF_LIBRARY_DIRECTORY "${ESMF_LIBRARY_DIRECTORY}")                      # remove -L prefixes
    find_library(ESMF_LIBRARY
        esmf
        PATHS ${ESMF_LIBRARY_DIRECTORY}
        NO_DEFAULT_PATH
    )

    # Save internal cache variables for troubleshooting
    set(ESMF_F90COMPILEPATHS   "${ESMF_F90COMPILEPATHS}"   CACHE INTERNAL "ESMF_F90COMPILEPATHS from esmf.mk")
    set(ESMF_F90ESMFLINKPATHS  "${ESMF_F90ESMFLINKPATHS}"  CACHE INTERNAL "ESMF_F90ESMFLINKPATHS from esmf.mk")
    set(ESMF_INCLUDE_DIRS      "${ESMF_INCLUDE_DIRS}"      CACHE INTERNAL "ESMF link libraries from ESMF_F90LINKLIBS")
    set(ESMF_LIBRARY_DIRECTORY "${ESMF_LIBRARY_DIRECTORY}" CACHE INTERNAL "ESMF library directory from ESMF_F90ESMFLINKPATHS")

    # Find ESMC_Macros.h in one of the ESMF_INCLUDE_DIRS
    find_file(ESMC_MACROS
        ESMC_Macros.h
        PATHS ${ESMF_INCLUDE_DIRS}
        NO_DEFAULT_PATH
    )
    # Determine ESMF version from ESMC_Macros.h
    if(EXISTS ${ESMC_MACROS})
        file(READ ${ESMC_MACROS} ESMC_MACROS_CONTENTS)
        if("${ESMC_MACROS_CONTENTS}" MATCHES "#define[ \t]+ESMF_VERSION_MAJOR[ \t]+([0-9]+)")
            set(ESMF_VERSION_MAJOR "${CMAKE_MATCH_1}")
        endif()
        if("${ESMC_MACROS_CONTENTS}" MATCHES "#define[ \t]+ESMF_VERSION_MINOR[ \t]+([0-9]+)")
            set(ESMF_VERSION_MINOR "${CMAKE_MATCH_1}")
        endif()
        if("${ESMC_MACROS_CONTENTS}" MATCHES "#define[ \t]+ESMF_VERSION_REVISION[ \t]+([0-9]+)")
            set(ESMF_VERSION_REVISION "${CMAKE_MATCH_1}")
        endif()
        set(ESMF_VERSION "${ESMF_VERSION_MAJOR}.${ESMF_VERSION_MINOR}.${ESMF_VERSION_REVISION}")
    else()
        set(ESMF_VERSION "NOTFOUND")
    endif()
endif()

find_package_handle_standard_args(ESMF 
	REQUIRED_VARS ESMF_MK ESMF_LIBRARY
	VERSION_VAR ESMF_VERSION
	FAIL_MESSAGE "Failed to find esmf.mk! Set CMAKE_PREFIX_PATH to the DIRECTORY containing \"esmf.mk\" (it's in the lib subdirectory of your ESMF install)."
)

# Make an imported target for ESMF
if(NOT TARGET ESMF)
    add_library(ESMF UNKNOWN IMPORTED)
    set_target_properties(ESMF PROPERTIES
        IMPORTED_LOCATION ${ESMF_LIBRARY}
    )

    set_property(TARGET ESMF
        PROPERTY INTERFACE_INCLUDE_DIRECTORIES ${ESMF_INCLUDE_DIRS}
    )

    # Get ESMF_F90LINKOPTS, ESMF_F90LINKPATHS, ESMF_F90LINKRPATHS, and ESMF_F90ESMFLINKLIBS  (these provide non-ESMF linker options and libs)
    string(REGEX MATCH "ESMF_F90LINKOPTS=([^\n]*)" ESMF_F90LINKOPTS_LINE     "${ESMF_MK_CONTENTS}") # match line
    string(STRIP "${CMAKE_MATCH_1}" ESMF_F90LINKOPTS)       # extract value
    string(REGEX MATCH "ESMF_F90LINKPATHS=([^\n]*)" ESMF_F90LINKPATHS_LINE    "${ESMF_MK_CONTENTS}") # match line
    string(STRIP "${CMAKE_MATCH_1}" ESMF_F90LINKPATHS)      # extract value
    string(REGEX MATCH "ESMF_F90LINKRPATHS=([^\n]*)" ESMF_F90LINKRPATHS_LINE   "${ESMF_MK_CONTENTS}") # match line
    string(STRIP "${CMAKE_MATCH_1}" ESMF_F90LINKRPATHS)     # extract value
    string(REGEX MATCH "ESMF_F90ESMFLINKLIBS=([^\n]*)" ESMF_F90ESMFLINKLIBS_LINE "${ESMF_MK_CONTENTS}") # match line
    string(STRIP "${CMAKE_MATCH_1}" ESMF_F90ESMFLINKLIBS)   # extract value

    # Add ESMF_F90LINKOPTS, ESMF_F90LINKPATHS, ESMF_F90LINKRPATHS, and ESMF_F90ESMFLINKLIBS
    target_link_libraries(ESMF INTERFACE "${ESMF_F90LINKOPTS} ${ESMF_F90LINKPATHS} ${ESMF_F90LINKRPATHS} ${ESMF_F90ESMFLINKLIBS}")

    # Save internal cache variables for troubleshooting
    set(ESMF_F90LINKOPTS_LINE "${ESMF_F90LINKOPTS_LINE}" CACHE INTERNAL "ESMF_F90LINKOPTS from esmf.mk")
    set(ESMF_F90LINKPATHS_LINE "${ESMF_F90LINKPATHS_LINE}" CACHE INTERNAL "ESMF_F90LINKPATHS from esmf.mk")
    set(ESMF_F90LINKRPATHS_LINE "${ESMF_F90LINKRPATHS_LINE}" CACHE INTERNAL "ESMF_F90LINKRPATHS from esmf.mk")
    set(ESMF_F90ESMFLINKLIBS_LINE "${ESMF_F90ESMFLINKLIBS_LINE}" CACHE INTERNAL "ESMF_F90ESMFLINKLIBS from esmf.mk")
endif()


