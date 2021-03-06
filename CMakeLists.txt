# cmake version, project name, language
cmake_minimum_required(VERSION 3.5 FATAL_ERROR)
project(matm Fortran)

# set output paths for modules, archives, and executables
set(CMAKE_Fortran_MODULE_DIRECTORY ${PROJECT_BINARY_DIR}/include)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# if build type not specified, default to release
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "Release")
endif()

if (MPIFORT_EXE STREQUAL "MPIFORT_EXE-NOTFOUND")
  message("mpifort not found, searching for MPI libraries" )
  find_package(MPI)
else()
  message("mpifort executable found: " ${MPIFORT_EXE})
  message("Will assume system MPI implementation is sound. Remove mpifort from PATH to automatically configure MPI")
  set(MPI_FORTRAN_COMPILER mpifort)
  set(CMAKE_Fortran_COMPILER mpifort)
endif()

if("${NETCDF_DIR}" STREQUAL "")
  execute_process(COMMAND nf-config --prefix OUTPUT_VARIABLE NETCDF_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE)
endif()
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")
set (NETCDF_F90 "YES")
find_package(NetCDF REQUIRED)
include_directories(${NETCDF_F90_INCLUDE_DIRS})

# compiler flags for gfortran
if(CMAKE_Fortran_COMPILER_ID MATCHES GNU)
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -std=f2008 -Wall -fdefault-real-8 -ffpe-trap=invalid,zero,overflow")
  set(CMAKE_Fortran_FLAGS_DEBUG "-O0 -g -pg -fbounds-check -fbacktrace")
  set(CMAKE_Fortran_FLAGS_RELEASE "-O3")
endif()

# compiler flags for ifort
if(CMAKE_Fortran_COMPILER_ID MATCHES Intel)
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -r8 -fpe0 -fp-model precise")
  set(CMAKE_Fortran_FLAGS_DEBUG "-O0 -g -check all -traceback")
  set(CMAKE_Fortran_FLAGS_RELEASE "-O3")
endif()

# get external projects
include(ExternalProject)

# datetime-fortran external project
# We use a forked version because of this behaviour:
# https://github.com/wavebitscientific/datetime-fortran/issues/51
ExternalProject_Add(datetime-fortran
    GIT_REPOSITORY   https://github.com/nicjhan/datetime-fortran.git
    GIT_TAG          3e7755c585cdc62ed262e91d57e7d54f82046087
    INSTALL_COMMAND cmake -E echo "Skipping datetime-fortran install step."
)
ExternalProject_Get_property(datetime-fortran BINARY_DIR)
include_directories(${BINARY_DIR}/include)
add_library(datetime STATIC IMPORTED)
add_dependencies(datetime datetime-fortran)
set_property(TARGET datetime PROPERTY IMPORTED_LOCATION ${BINARY_DIR}/lib/libdatetime.a)

# json-fortran external project
ExternalProject_Add(json-fortran
    GIT_REPOSITORY    https://github.com/jacobwilliams/json-fortran.git
    GIT_TAG          37de3ade555e84779ebf8a26c23e86a3ae268390
    INSTALL_COMMAND cmake -E echo "Skipping json-fortran install step."
)
ExternalProject_Get_property(json-fortran BINARY_DIR)
include_directories(${BINARY_DIR}/include)
add_library(jsonfortran STATIC IMPORTED)
add_dependencies(jsonfortran json-fortran)
set_property(TARGET jsonfortran PROPERTY IMPORTED_LOCATION ${BINARY_DIR}/lib/libjsonfortran.a)

# oasis external project
# json-fortran external project
ExternalProject_Add(oasis3-mct
    GIT_REPOSITORY    https://github.com/OceansAus/oasis3-mct.git
    GIT_TAG           6fe5196babeded0d71f319153e937ceb0ab2cb53
    CONFIGURE_COMMAND ""
    BUILD_IN_SOURCE 1
    BUILD_COMMAND make nci
    INSTALL_COMMAND cmake -E echo "Skipping json-fortran install step."
)
ExternalProject_Get_property(oasis3-mct BINARY_DIR)
include_directories(${BINARY_DIR}/Linux/build/lib/psmile.MPI1/)
add_library(mct STATIC IMPORTED)
add_library(mpeu STATIC IMPORTED)
add_library(psmile.MPI1 STATIC IMPORTED)
add_library(scrip STATIC IMPORTED)
add_dependencies(mct oasis3-mct)
add_dependencies(mpeu oasis3-mct)
add_dependencies(psmile.MPI1 oasis3-mct)
add_dependencies(scrip oasis3-mct)
set_property(TARGET mct PROPERTY IMPORTED_LOCATION ${BINARY_DIR}/Linux/lib/libmct.a)
set_property(TARGET mpeu PROPERTY IMPORTED_LOCATION ${BINARY_DIR}/Linux/lib/libmpeu.a)
set_property(TARGET psmile.MPI1 PROPERTY IMPORTED_LOCATION ${BINARY_DIR}/Linux/lib/libpsmile.MPI1.a)
set_property(TARGET scrip PROPERTY IMPORTED_LOCATION ${BINARY_DIR}/Linux/lib/libscrip.a)

# libcouple.a library
file(GLOB LIB_SOURCES libcouple/src/*.F90)
add_library(couple ${LIB_SOURCES})
add_dependencies(couple datetime oasis3-mct)

# Join all of the above together to make libaccesom2
# See https://stackoverflow.com/questions/37924383/combining-several-static-libraries-into-one-using-cmake
set(LIBACCESSOM2 ${CMAKE_BINARY_DIR}/lib/libaccessom2.a)

add_custom_target(combined
        COMMAND ar -x $<TARGET_FILE:datetime>
        COMMAND ar -x $<TARGET_FILE:jsonfortran>
        COMMAND ar -x $<TARGET_FILE:mct>
        COMMAND ar -x $<TARGET_FILE:mpeu>
        COMMAND ar -x $<TARGET_FILE:psmile.MPI1>
        COMMAND ar -x $<TARGET_FILE:scrip>
        COMMAND ar -x $<TARGET_FILE:couple>
        COMMAND ar -qcs ${LIBACCESSOM2} *.o
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        DEPENDS datetime jsonfortran mct mpeu psmile.MPI1 scrip couple
        )

add_library(accessom2 STATIC IMPORTED GLOBAL)
add_dependencies(accessom2 combined)
set_target_properties(accessom2 PROPERTIES IMPORTED_LOCATION ${LIBACCESSOM2})

# yatm executable
file(GLOB ATM_SOURCES atm/src/*.F90)
add_executable(yatm.exe ${ATM_SOURCES})
target_link_libraries(yatm.exe accessom2 ${NETCDF_LIBRARIES} ${MPI_Fortran_LIBRARIES})

# ice stub executable
file(GLOB ICE_STUB_SOURCES ice_stub/src/*.F90)
add_executable(ice_stub.exe ${ICE_STUB_SOURCES})
target_link_libraries(ice_stub.exe accessom2 ${NETCDF_LIBRARIES} ${MPI_Fortran_LIBRARIES})

# ocean stub executable
file(GLOB OCEAN_STUB_SOURCES ocean_stub/src/*.F90)
add_executable(ocean_stub.exe ${OCEAN_STUB_SOURCES})
target_link_libraries(ocean_stub.exe accessom2 ${NETCDF_LIBRARIES} ${MPI_Fortran_LIBRARIES})

