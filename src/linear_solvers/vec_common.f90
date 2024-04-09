submodule(vec) vec_common
#include "ccs_macros.inc"

  use utils, only: exit_print, str
  use constants, only: cell
  use error_codes
  implicit none

contains

  !> Constructor for default vector values
  pure module subroutine initialise_vector(vec_properties)
    type(vector_spec), intent(inout) :: vec_properties !< the initialised vector values
    vec_properties%par_env => null()
    vec_properties%mesh => null()
    vec_properties%storage_location = cell ! Default to cell-centre values (so as not to break previous work)
  end subroutine initialise_vector

  !> Setter for vector size
  module subroutine set_vector_size(par_env, mesh, vec_properties)
    class(parallel_environment), allocatable, target, intent(in) :: par_env !< the parallel environment where the vector resides
    class(ccs_mesh), target, intent(in) :: mesh                             !< the mesh - contains the information to set the vector size
    type(vector_spec), intent(inout) :: vec_properties                      !< the vector data object

    vec_properties%par_env => par_env
    vec_properties%mesh => mesh
  end subroutine set_vector_size

  !> Set vector values to be located at either cell-centre or face
  pure module subroutine set_vector_location(loc, vec_properties)
    integer(ccs_int), intent(in) :: loc
    type(vector_spec), intent(inout) :: vec_properties

    vec_properties%storage_location = loc
  end subroutine set_vector_location

  pure module subroutine create_vector_values(nrows, val_dat)
    integer(ccs_int), intent(in) :: nrows
    type(vector_values), intent(out) :: val_dat
    allocate (val_dat%global_indices(nrows))
    allocate (val_dat%values(nrows))

    val_dat%global_indices(:) = -1_ccs_int
    val_dat%values(:) = 0.0_ccs_real
  end subroutine create_vector_values

  pure module subroutine set_vector_values_mode(mode, val_dat)
    integer(ccs_int), intent(in) :: mode
    type(vector_values), intent(inout) :: val_dat

    val_dat%setter_mode = mode
  end subroutine set_vector_values_mode

  pure module subroutine set_vector_values_entry(val, val_dat)

    use constants, only: add_mode, insert_mode

    real(ccs_real), intent(in) :: val
    type(vector_values), intent(inout) :: val_dat

    associate (x => val_dat%values(val_dat%current_entry), &
               mode => val_dat%setter_mode)
      if (mode == insert_mode) then
        x = val
      else if (mode == add_mode) then
        x = x + val
      else
        error stop unknown_mode ! Unrecognised entry mode
      end if
    end associate

  end subroutine set_vector_values_entry

  !> Generic implementation to get vector data in natural ordering
  module subroutine get_natural_data_vec(par_env, mesh, v, data)

    class(parallel_environment), intent(in) :: par_env
    type(ccs_mesh), intent(in) :: mesh
    class(ccs_vector), intent(inout) :: v
    real(ccs_real), dimension(:), allocatable, intent(out) :: data !< The returned vector data in
                                                                   !< natural ordering. Note the use
                                                                   !< of allocatable + intent(out),
                                                                   !< this ensures it will be
                                                                   !< de/reallocated by this subroutine.

    real(ccs_real), dimension(:), pointer :: vec_data ! The data stored in the vector

    associate (topo => mesh%topo, &
               local_num_cells => mesh%topo%local_num_cells)

      if (allocated(data)) then ! Shouldn't really happen...
        deallocate(data)
      end if
      allocate(data(local_num_cells))
      
      call get_vector_data(v, vec_data)
      call reorder_data_vec(par_env, vec_data(1:local_num_cells), topo%natural_indices(1:local_num_cells), &
                            data(1:local_num_cells))
      call restore_vector_data(v, vec_data)

    end associate

  end subroutine get_natural_data_vec

end submodule
