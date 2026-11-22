cmake_minimum_required(VERSION 3.16)
project(HamsterHoard LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(MPI REQUIRED COMPONENTS CXX)
find_package(OpenMP REQUIRED COMPONENTS CXX)

add_executable(hamsterhoard src/main.cpp)
target_link_libraries(hamsterhoard PRIVATE MPI::MPI_CXX OpenMP::OpenMP_CXX)

if(MSVC)
  target_compile_options(hamsterhoard PRIVATE /W4)
else()
  target_compile_options(hamsterhoard PRIVATE -Wall -Wextra -O3)
endif()
