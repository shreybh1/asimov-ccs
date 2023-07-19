!
!  Implementation of the parallel environment using MPI and PETSc
!
!  @build mpi petsc
submodule(parallel) parallel_env_mpi_petsc
#include "ccs_macros.inc"

  use utils, only: exit_print
  use mpi
  use petsc, only: PetscInitialize, PetscFinalize, PETSC_NULL_CHARACTER
  use parallel_types_mpi, only: parallel_environment_mpi

  implicit none

contains

  !> Create the MPI and PETSc parallel environments
  module subroutine initialise_parallel_environment(par_env)

    class(parallel_environment), allocatable, intent(out) :: par_env !< parallel_environment_mpi

    integer :: ierr ! Error code

    allocate (parallel_environment_mpi :: par_env)

    select type (par_env)

    type is (parallel_environment_mpi)
      call mpi_init(ierr)
      call error_handling(ierr, "mpi", par_env)

      par_env%comm = MPI_COMM_WORLD

      call initialise_petsc(par_env)

      call mpi_comm_rank(par_env%comm, par_env%proc_id, ierr)
      call error_handling(ierr, "mpi", par_env)

      call mpi_comm_size(par_env%comm, par_env%num_procs, ierr)
      call error_handling(ierr, "mpi", par_env)

      call par_env%set_rop()

      par_env%root = 0

    class default
      call error_abort("Unsupported parallel environment")

    end select

  end subroutine

  !v Creates a new parallel environment by splitting the existing one, splitting
  !  based on provided MPI constants or a provided colouring
  module subroutine create_new_par_env(parent_par_env, split, use_mpi_splitting, par_env)
    class(parallel_environment), intent(in) :: parent_par_env         !< The parent parallel environment
    integer, intent(in) :: split                                      !< The value indicating which type of split is being performed, or the user provided colour
    logical, intent(in) :: use_mpi_splitting                          !< Flag indicating whether to use mpi_comm_split_type
    class(parallel_environment), allocatable, intent(out) :: par_env  !< The resulting parallel environment

    integer :: newcomm
    integer :: colour
    integer :: ierr

    select type (parent_par_env)
    type is (parallel_environment_mpi)
      call set_colour_from_split(parent_par_env, split, colour)
      if (use_mpi_splitting) then
        call mpi_comm_split_type(parent_par_env%comm, colour, 0, MPI_INFO_NULL, newcomm, ierr) 
      else 
        call mpi_comm_split(parent_par_env%comm, colour, 0, newcomm, ierr) 
      end if
      call error_handling(ierr, "mpi", parent_par_env)

      allocate(parallel_environment_mpi :: par_env)
      select type (par_env)
      type is (parallel_environment_mpi)
        call create_parallel_environment_from_comm(newcomm, par_env)
      class default
        call error_abort("Unsupported parallel environment")
      end select

    class default
      call error_abort("Unsupported parallel environment")
    end select
  end subroutine create_new_par_env
	
  !> Creates a parallel environment based on the provided communicator
  subroutine create_parallel_environment_from_comm(comm, par_env)
    integer, intent(in) :: comm                                          !< The communicator with which to make the parallel environment
    type(parallel_environment_mpi), intent(inout) :: par_env   !< The resulting parallel environment

    integer :: ierr

    par_env%comm = comm
    call set_mpi_parameters(par_env)
  end subroutine create_parallel_environment_from_comm

  !> Cleanup the PETSc and MPI parallel environments
  module subroutine cleanup_parallel_environment(par_env)

    class(parallel_environment), intent(in) :: par_env !< parallel_environment_mpi

    integer :: ierr ! Error code

    select type (par_env)

    type is (parallel_environment_mpi)
      call finalise_petsc(par_env)
      call mpi_finalize(ierr)
      call error_handling(ierr, "mpi", par_env)

    class default
      call error_abort("Unsupported parallel environment")

    end select

  end subroutine

  !> Initalise PETSc
  subroutine initialise_petsc(par_env)

    type(parallel_environment_mpi), intent(in) :: par_env !< parallel_environment_mpi

    integer :: ierr ! Error code

    call PetscInitialize(PETSC_NULL_CHARACTER, ierr)

    if (ierr /= 0) then
      call error_handling(ierr, "petsc", par_env)
    end if

  end subroutine

  !> Finalise PETSc
  subroutine finalise_petsc(par_env)

    type(parallel_environment_mpi), intent(in) :: par_env !< parallel_environment_mpi

    integer :: ierr ! Error code

    call PetscFinalize(ierr) ! Finalises MPI

    if (ierr /= 0) then
      call error_handling(ierr, "petsc", par_env)
    end if

  end subroutine

end submodule parallel_env_mpi_petsc
