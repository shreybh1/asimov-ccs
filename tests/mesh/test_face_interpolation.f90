!> @brief Test the face interpolation with a 2 cells mesh
!
!> @description Generates a basic mesh geoemtry and topology for a 2 cells mesh and makes sure the face interpolation is 
!!              properly computed and accessed (with get_face_interpolation)
program test_face_interpolation

  use testing_lib

  use mesh_utils, only: compute_face_interpolation
  use meshing, only: get_face_interpolation, set_cell_location

  implicit none

  type(ccs_mesh), target :: mesh
  type(cell_locator) :: loc_p
  integer(ccs_int) :: index_p, j
  real(ccs_real) :: interpol_factor

  call init()

  mesh = generate_mesh(0.3*1.0_ccs_real)

  call compute_face_interpolation(mesh)

  ! Test cell1 interpolation factor
  index_p = 1_ccs_int
  j = 1_ccs_int

  call set_cell_location(mesh, index_p, loc_p)
  call get_face_interpolation(mesh, loc_p, j, interpol_factor)

  if (interpol_factor .lt. 0.5) then
    write (message, *) "FAIL: wrong interpolation for cell ", index_p
    call stop_test(message)
  end if

  ! Test cell2 interpolation factor
  index_p = 2_ccs_int
  j = 1_ccs_int

  call set_cell_location(mesh, index_p, loc_p)
  call get_face_interpolation(mesh, loc_p, j, interpol_factor)

  if (interpol_factor .gt. 0.5) then
    write (message, *) "FAIL: wrong interpolation for cell ", index_p
    call stop_test(message)
  end if

  call fin()
  contains

  function generate_mesh(face_coordinate) result(mesh)

    real(ccs_real), intent(in) :: face_coordinate
    type(ccs_mesh) :: mesh

    ! Build 2 cells mesh topology
    mesh%topo%global_num_cells = 2
    mesh%topo%local_num_cells = 2
    mesh%topo%halo_num_cells = 0
    mesh%topo%total_num_cells = 2
    mesh%topo%global_num_faces = 1
    mesh%topo%num_faces = 1
    mesh%topo%max_faces = 1

    allocate(mesh%topo%global_indices(mesh%topo%global_num_cells))
    mesh%topo%global_indices(1) = 1
    mesh%topo%global_indices(2) = 2

    allocate(mesh%topo%global_face_indices(mesh%topo%max_faces, mesh%topo%global_num_cells))
    mesh%topo%global_face_indices(:, :) = 1

    allocate(mesh%topo%face_indices(mesh%topo%max_faces, mesh%topo%local_num_cells))
    mesh%topo%face_indices(:, :) = 1

    allocate(mesh%topo%nb_indices(mesh%topo%max_faces, mesh%topo%local_num_cells))
    mesh%topo%nb_indices(1, 1) = 2
    mesh%topo%nb_indices(1, 2) = 1

    allocate(mesh%topo%num_nb(mesh%topo%local_num_cells))
    mesh%topo%num_nb(:) = 1

    ! Build 2 cells mesh geometry
    allocate(mesh%geo%x_p(3, mesh%topo%total_num_cells))
    mesh%geo%x_p(:, 1) = (/ 0.0_ccs_real, 0.0_ccs_real, 0.0_ccs_real /)
    mesh%geo%x_p(:, 2) = (/ 1.0_ccs_real, 0.0_ccs_real, 0.0_ccs_real /)

    allocate(mesh%geo%x_f(3, mesh%topo%max_faces, mesh%topo%total_num_cells))
    mesh%geo%x_f(:, 1, 1) = (/ face_coordinate, 0.0_ccs_real, 0.0_ccs_real/)
    mesh%geo%x_f(:, 1, 2) = (/ face_coordinate, 0.0_ccs_real, 0.0_ccs_real/)

  end function

end program test_face_interpolation
