# @HEADER
# ************************************************************************
#
#            TriBITS: Tribal Build, Integrate, and Test System
#                    Copyright 2013 Sandia Corporation
#
# Under the terms of Contract DE-AC04-94AL85000 with Sandia Corporation,
# the U.S. Government retains certain rights in this software.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# 1. Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# 3. Neither the name of the Corporation nor the names of the
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY SANDIA CORPORATION "AS IS" AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL SANDIA CORPORATION OR THE
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# ************************************************************************
# @HEADER


assert_defined(${PACKAGE_NAME}_ENABLE_MPI)


tribits_add_advanced_test( TestingFunctionMacro_UnitTests
  OVERALL_WORKING_DIRECTORY TEST_NAME
  TEST_0 CMND ${CMAKE_COMMAND}
    ARGS
      -DPROJECT_NAME=${PROJECT_NAME}
      -D${PROJECT_NAME}_TRIBITS_DIR=${${PROJECT_NAME}_TRIBITS_DIR}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/TestingFunctionMacro_UnitTests.cmake"
    PASS_REGULAR_EXPRESSION_ALL
      "Final UnitTests Result: num_run = 675"
      "Final UnitTests Result: PASSED"
  )


tribits_add_advanced_test( CompilerOptions_UnitTests
  OVERALL_WORKING_DIRECTORY TEST_NAME
  TEST_0 CMND ${CMAKE_COMMAND}
    ARGS
      -DPROJECT_NAME=${PROJECT_NAME}
      -D${PROJECT_NAME}_TRIBITS_DIR=${${PROJECT_NAME}_TRIBITS_DIR}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/CompilerOptions_UnitTests.cmake"
    PASS_REGULAR_EXPRESSION_ALL
      "Final UnitTests Result: num_run = 207"
      "Final UnitTests Result: PASSED"
  )


tribits_add_advanced_test( TribitsProcessPackagesAndDirsLists_UnitTests
  OVERALL_WORKING_DIRECTORY TEST_NAME
  TEST_0 CMND ${CMAKE_COMMAND}
    ARGS
      -DPROJECT_NAME=${PROJECT_NAME}
      -D${PROJECT_NAME}_TRIBITS_DIR=${${PROJECT_NAME}_TRIBITS_DIR}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/TribitsProcessPackagesAndDirsLists_UnitTests.cmake"
    PASS_REGULAR_EXPRESSION_ALL
      "Final UnitTests Result: num_run = 34"
      "Final UnitTests Result: PASSED"
  )


tribits_add_advanced_test( TribitsProcessExtraRepositoriesList_UnitTests
  OVERALL_WORKING_DIRECTORY  TEST_NAME
  TEST_0  CMND  ${CMAKE_COMMAND}
    ARGS
      -DPROJECT_NAME=${PROJECT_NAME}
      -D${PROJECT_NAME}_TRIBITS_DIR=${${PROJECT_NAME}_TRIBITS_DIR}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/TribitsProcessExtraRepositoriesList_UnitTests.cmake"
    PASS_REGULAR_EXPRESSION_ALL
      "Final UnitTests Result: num_run = 143"
      "Final UnitTests Result: PASSED"
  )


tribits_add_advanced_test( TribitsReadAllProjectDepsFilesCreateDepsGraph_UnitTests
  OVERALL_WORKING_DIRECTORY TEST_NAME
  TEST_0 CMND ${CMAKE_COMMAND}
    ARGS
      -DPROJECT_NAME=${PROJECT_NAME}
      -D${PROJECT_NAME}_TRIBITS_DIR=${${PROJECT_NAME}_TRIBITS_DIR}
      -DCMAKE_CURRENT_LIST_DIR=${CMAKE_CURRENT_SOURCE_DIR}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/TribitsReadAllProjectDepsFilesCreateDepsGraph_UnitTests.cmake"
    PASS_REGULAR_EXPRESSION_ALL
      "Final UnitTests Result: num_run = 127"
      "Final UnitTests Result: PASSED"
  )


tribits_add_advanced_test( TribitsAdjustPackageEnables_UnitTests
  OVERALL_WORKING_DIRECTORY TEST_NAME
  TEST_0 CMND ${CMAKE_COMMAND}
    ARGS
      -DPROJECT_NAME=${PROJECT_NAME}
      -D${PROJECT_NAME}_TRIBITS_DIR=${${PROJECT_NAME}_TRIBITS_DIR}
      -DCMAKE_CURRENT_LIST_DIR=${CMAKE_CURRENT_SOURCE_DIR}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/TribitsAdjustPackageEnables_UnitTests.cmake"
    PASS_REGULAR_EXPRESSION_ALL
      "Final UnitTests Result: num_run = 97"
      "Final UnitTests Result: PASSED"
  )


tribits_add_advanced_test( TribitsWriteClientExportFiles_UnitTests
  OVERALL_WORKING_DIRECTORY TEST_NAME
  TEST_0 CMND ${CMAKE_COMMAND}
    ARGS
      -DPROJECT_NAME=${PROJECT_NAME}
      -D${PROJECT_NAME}_TRIBITS_DIR=${${PROJECT_NAME}_TRIBITS_DIR}
      -DCURRENT_TEST_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}
      -DCMAKE_CURRENT_LIST_DIR=${CMAKE_CURRENT_SOURCE_DIR}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/TribitsWriteClientExportFiles_UnitTests.cmake"
    PASS_REGULAR_EXPRESSION_ALL
      "Final UnitTests Result: num_run = 30"
      "Final UnitTests Result: PASSED"
  )


tribits_add_advanced_test( TribitsExternalPackageWriteConfigFile_UnitTests
  OVERALL_WORKING_DIRECTORY TEST_NAME
  TEST_0 CMND ${CMAKE_COMMAND}
    ARGS
      -DPROJECT_NAME=${PROJECT_NAME}
      -D${PROJECT_NAME}_TRIBITS_DIR=${${PROJECT_NAME}_TRIBITS_DIR}
      -DCURRENT_TEST_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}
      -P "${CMAKE_CURRENT_SOURCE_DIR}/TribitsExternalPackageWriteConfigFile_UnitTests.cmake"
    PASS_REGULAR_EXPRESSION_ALL
      "Final UnitTests Result: num_run = 39"
      "Final UnitTests Result: PASSED"
  )


add_subdirectory(tribits_get_version_date)
add_subdirectory(CTestScriptsUnitTests)
add_subdirectory(DependencyUnitTests)
add_subdirectory(ProcessEnabledTpls)
add_subdirectory(ExamplesUnitTests)
