!> @brief Submodule file parallel_errors_mpi.smod
!
!> @build mpi
!
!> @details Implementation (using MPI) of parallel 
!!          error handling

submodule (parallel) parallel_errors_mpi

  use mpi_f08
  use parallel_types_mpi, only: parallel_environment_mpi
  use kinds, only: accs_int

  implicit none

  contains

  !> @brief Error handling for parallel environment that uses MPI only
  !
  !> @param[in] integer error_code - Variable the holds the error code
  !> @param[in] string error_cat - String description of the error category
  !> @param[in] parallel_environment_mpi par_env
  module subroutine error_handling(error_code, error_cat, par_env)

    integer, intent(in) :: error_code
    character (len=*), intent (in) :: error_cat
    class(parallel_environment), intent(in) :: par_env
    integer(accs_int) :: length
    integer :: ierr 
    character(len = MPI_MAX_ERROR_STRING) :: error_message 

    select type (par_env)

      type is (parallel_environment_mpi)

        if(error_cat == "mpi") then
      
          if (error_code /= MPI_SUCCESS ) then
            call mpi_error_string(error_code, error_message, length, ierr)
            write(*,*) error_message
            call mpi_abort(par_env%comm, error_code, ierr)
          end if

        else 
          write(*,*) "Unsupported error categroy" 
        end if

      class default
        write(*,*) "Unsupported parallel environment"

    end select

  end subroutine

end submodule parallel_errors_mpi