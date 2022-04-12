!> @brief Submodule file fv_CDS.smod
!> @build CDS
!
!> @details An implementation of the finite volume method using the CDS scheme

submodule (fv) fv_common

  use constants, only: add_mode, insert_mode, ndim
  use types, only: vector_values, matrix_values, cell_locator, face_locator, &
                   neighbour_locator
  use vec, only: get_vector_data, restore_vector_data
  use utils, only: pack_entries, set_values, update
  use meshing, only: count_neighbours, get_boundary_status, set_neighbour_location, &
                      get_local_index, get_global_index, get_volume, get_distance, &
                      set_face_location, get_face_area, get_face_normal, set_cell_location

  implicit none

contains

  !> @brief Computes fluxes and assign to matrix and RHS
  !
  !> @param[in] phi       - scalar field structure
  !> @param[in] mf        - mass flux field structure
  !> @param[in] cell_mesh - the mesh being used
  !> @param[in] bcs       - the boundary conditions structure being used
  !> @param[in] cps       - the number of cells per side in the (square) mesh
  !> @param[in,out] M     - Data structure containing matrix to be filled
  !> @param[in,out] vec   - Data structure containing RHS vector to be filled
  module subroutine compute_fluxes(phi, mf, cell_mesh, bcs, cps, M, vec)
    class(field), intent(in) :: phi
    class(field), intent(in) :: mf
    type(ccs_mesh), intent(in) :: cell_mesh
    type(bc_config), intent(in) :: bcs
    integer(ccs_int), intent(in) :: cps  
    class(ccs_matrix), intent(inout) :: M   
    class(ccs_vector), intent(inout) :: vec   

    integer(ccs_int) :: n_int_cells
    real(ccs_real), dimension(:), pointer :: mf_data

    associate (mf_values => mf%values)
      print *, "CF: get mf"
      call get_vector_data(mf_values, mf_data)

      ! Loop over cells computing advection and diffusion fluxes
      n_int_cells = calc_matrix_nnz()
      print *, "CF: interior"
      call compute_interior_coeffs(phi, mf_data, cell_mesh, n_int_cells, M)

      ! Loop over boundaries
      print *, "CF: boundaries"
      call compute_boundary_coeffs(phi, mf_data, cell_mesh, bcs, cps, M, vec)

      print *, "CF: restore mf"
      call restore_vector_data(mf_values, mf_data)
    end associate

  end subroutine compute_fluxes

  !> @brief Returns the number of entries per row that are non-zero
  !
  !> @details Note: this assumes a square 2d grid
  !
  !> @param[out] nnz - number of non-zero entries per row
  pure function calc_matrix_nnz() result(nnz)
    integer(ccs_int) :: nnz

    nnz = 5_ccs_int
  end function calc_matrix_nnz

  !> @brief Computes the matrix coefficient for cells in the interior of the mesh
  !
  !> @param[in] phi         - scalar field structure
  !> @param[in] mf          - mass flux array defined at faces
  !> @param[in] cell_mesh   - Mesh structure
  !> @param[in] n_int_cells - number of cells in the interior of the mesh
  !> @param[in,out] M       - Matrix structure being assigned
  subroutine compute_interior_coeffs(phi, mf, cell_mesh, n_int_cells, M)
    class(field), intent(in) :: phi
    real(ccs_real), dimension(:), intent(in) :: mf
    type(ccs_mesh), intent(in) :: cell_mesh
    integer(ccs_int), intent(in) :: n_int_cells
    class(ccs_matrix), intent(inout) :: M

    type(matrix_values) :: mat_coeffs
    type(cell_locator) :: self_loc
    type(neighbour_locator) :: loc_nb
    type(face_locator) :: face_loc
    integer(ccs_int) :: self_idx, global_index_nb, local_idx, index_nb
    integer(ccs_int) :: j
    integer(ccs_int) :: mat_counter
    integer(ccs_int) :: nnb
    real(ccs_real) :: face_area
    real(ccs_real) :: diff_coeff, diff_coeff_total
    real(ccs_real) :: adv_coeff, adv_coeff_total
    real(ccs_real), dimension(ndim) :: face_normal
    logical :: is_boundary

    integer(ccs_int) :: idxf

    real(ccs_real) :: sgn !< Sign indicating face orientation

    mat_coeffs%setter_mode = add_mode

    allocate(mat_coeffs%row_indices(1))
    allocate(mat_coeffs%col_indices(n_int_cells))
    allocate(mat_coeffs%values(n_int_cells))

    do local_idx = 1, cell_mesh%nlocal
      ! Calculate contribution from neighbours
      call set_cell_location(cell_mesh, local_idx, self_loc)
      call get_global_index(self_loc, self_idx)
      call count_neighbours(self_loc, nnb)
      mat_counter = 1
      adv_coeff_total = 0.0_ccs_real
      diff_coeff_total = 0.0_ccs_real
      do j = 1, nnb
        call set_neighbour_location(self_loc, j, loc_nb)
        call get_boundary_status(loc_nb, is_boundary)

        if (.not. is_boundary) then
          diff_coeff = calc_diffusion_coeff(local_idx, j, cell_mesh)

          call get_global_index(loc_nb, global_index_nb)
          call get_local_index(loc_nb, index_nb)

          call set_face_location(cell_mesh, local_idx, j, face_loc)
          call get_face_area(face_loc, face_area)
          call get_face_normal(face_loc, face_normal)
          call get_local_index(face_loc, idxf)

          ! XXX: Why won't Fortran interfaces distinguish on extended types...
          ! TODO: This will be expensive (in a tight loop) - investigate moving to a type-bound
          !       procedure (should also eliminate the type check).
          if (index_nb < local_idx) then
            sgn = -1.0_ccs_real
          else
            sgn = 1.0_ccs_real
          end if
          select type(phi)
            type is(central_field)
              call calc_advection_coeff(phi, sgn * mf(idxf), 0, adv_coeff)
            type is(upwind_field)
              call calc_advection_coeff(phi, sgn * mf(idxf), 0, adv_coeff)
            class default
              print *, 'invalid velocity field discretisation'
              stop
          end select

          ! XXX: we are relying on div(u)=0 => a_P = -sum_nb a_nb
          adv_coeff = adv_coeff * (sgn * mf(idxf) * face_area)
          
          call pack_entries(1, mat_counter, self_idx, global_index_nb, adv_coeff + diff_coeff, mat_coeffs)
          mat_counter = mat_counter + 1
          adv_coeff_total = adv_coeff_total + adv_coeff
          diff_coeff_total = diff_coeff_total + diff_coeff
        else
          call pack_entries(1, mat_counter, self_idx, -1, 0.0_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
        end if
      end do
      call pack_entries(1, mat_counter, self_idx, self_idx, -(adv_coeff_total + diff_coeff_total), mat_coeffs)
      mat_counter = mat_counter + 1
      call set_values(mat_coeffs, M)
    end do

    deallocate(mat_coeffs%row_indices)
    deallocate(mat_coeffs%col_indices)
    deallocate(mat_coeffs%values)
  end subroutine compute_interior_coeffs

  !> @brief Computes the value of the scalar field on the boundary based on linear interpolation between 
  !  values provided on box corners
  !
  !> @param[in] index_nb - index of neighbour with respect to CV (i.e. range 1-4 in square mesh)
  !> @param[in] row       - global row of cell within square mesh
  !> @param[in] col       - global column of cell within square mesh
  !> @param[in] cps       - number of cells per side in square mesh
  !> @param[in] bcs       - BC configuration data structure
  !> @param[out] bc_value - the value of the scalar field at the specified boundary
  subroutine compute_boundary_values(index_nb, row, col, cps, bcs, bc_value)
    integer, intent(in) :: index_nb  ! This is the index wrt the CV, not the nb's cell index (i.e. range 1-4 for a square mesh)
    integer, intent(in) :: row
    integer, intent(in) :: col
    integer, intent(in) :: cps
    type(bc_config), intent(in) :: bcs
    real(ccs_real), intent(out) :: bc_value
    real(ccs_real) :: row_cps, col_cps

    row_cps = real(row, ccs_real)/real(cps, ccs_real)
    col_cps = real(col, ccs_real)/real(cps, ccs_real)

    bc_value = 0.0_ccs_real
    ! if (bcs%bc_type(index_nb) == bc_type_dirichlet .and. &
    !    (bcs%region(index_nb) == bc_region_left .or. &
    !    bcs%region(index_nb) == bc_region_right)) then
    !   bc_value = -((1.0_ccs_real - row_cps) * bcs%endpoints(index_nb, 1) + row_cps * bcs%endpoints(index_nb, 2))
    ! else if (bcs%bc_type(index_nb) == bc_type_dirichlet .and. &
    !         (bcs%region(index_nb) == bc_region_top .or. &
    !         bcs%region(index_nb) == bc_region_bottom)) then
    !   bc_value = -((1.0_ccs_real - col_cps) * bcs%endpoints(index_nb, 1) + col_cps * bcs%endpoints(index_nb, 2))
    ! end if

    if (bcs%bc_type(index_nb) == 0) then
      bc_value = 0.0_ccs_real
    else if (bcs%bc_type(index_nb) == 1) then
      bc_value = 1.0_ccs_real ! XXX: might not be correct
    else
      print *, "ERROR: Unknown boundary type ", bcs%bc_type(index_nb)
    end if
    
  end subroutine compute_boundary_values

  !> @brief Computes the matrix coefficient for cells on the boundary of the mesh
  !
  !> @param[in] phi         - scalar field structure
  !> @param[in] mf          - mass flux array defined at faces
  !> @param[in] cell_mesh   - Mesh structure
  !> @param[in] bcs         - boundary conditions structure
  !> @param[in] cps         - number of cells per side
  !> @param[in,out] M       - Matrix structure being assigned
  !> @param[in,out] b       - vector structure being assigned
  subroutine compute_boundary_coeffs(phi, mf, cell_mesh, bcs, cps, M, b)
    class(field), intent(in) :: phi
    real(ccs_real), dimension(:), intent(in) :: mf
    type(ccs_mesh), intent(in) :: cell_mesh
    type(bc_config), intent(in) :: bcs
    integer(ccs_int), intent(in) :: cps
    class(ccs_matrix), intent(inout) :: M
    class(ccs_vector), intent(inout) :: b

    type(matrix_values) :: mat_coeffs
    type(vector_values) :: b_coeffs
    type(cell_locator) :: self_loc
    type(neighbour_locator) :: loc_nb
    type(face_locator) :: face_loc
    integer(ccs_int) :: self_idx, local_idx
    integer(ccs_int) :: j
    integer(ccs_int) :: bc_counter
    integer(ccs_int) :: row, col
    integer(ccs_int) :: nnb, index_nb
    real(ccs_real) :: face_area
    real(ccs_real) :: diff_coeff
    real(ccs_real) :: adv_coeff
    real(ccs_real) :: bc_value
    real(ccs_real), dimension(ndim) :: face_normal
    logical :: is_boundary

    integer(ccs_int) :: idxf
    
    mat_coeffs%setter_mode = add_mode
    b_coeffs%setter_mode = add_mode

    allocate(mat_coeffs%row_indices(1))
    allocate(mat_coeffs%col_indices(1))
    allocate(mat_coeffs%values(1))
    allocate(b_coeffs%indices(1))
    allocate(b_coeffs%values(1))

    bc_counter = 1
    do local_idx = 1, cell_mesh%nlocal
      call set_cell_location(cell_mesh, local_idx, self_loc)
      call get_global_index(self_loc, self_idx)
      call count_neighbours(self_loc, nnb)
      ! Calculate contribution from neighbours
      do j = 1, nnb
        call set_neighbour_location(self_loc, j, loc_nb)
        call get_boundary_status(loc_nb, is_boundary)
        if (is_boundary) then
          ! call get_global_index(loc_nb, global_index_nb)
          call get_local_index(loc_nb, index_nb)

          call set_face_location(cell_mesh, local_idx, j, face_loc)
          call get_face_area(face_loc, face_area)
          call get_face_normal(face_loc, face_normal)
          call get_local_index(face_loc, idxf)
          
          diff_coeff = calc_diffusion_coeff(local_idx, j, cell_mesh)
          select type(phi)
            type is(central_field)
              call calc_advection_coeff(phi, mf(idxf), index_nb, adv_coeff)
            type is(upwind_field)
              call calc_advection_coeff(phi, mf(idxf), index_nb, adv_coeff)
            class default
              print *, 'invalid velocity field discretisation'
              stop
          end select
          adv_coeff = adv_coeff * (mf(idxf) * face_area)

          call calc_cell_coords(self_idx, cps, row, col)
          call compute_boundary_values(j, row, col, cps, bcs, bc_value)
          call pack_entries(1, self_idx, -(adv_coeff + diff_coeff)*bc_value, b_coeffs)
          call pack_entries(1, 1, self_idx, self_idx, -(adv_coeff + diff_coeff), mat_coeffs)
          call set_values(b_coeffs, b)
          call set_values(mat_coeffs, M)
          bc_counter = bc_counter + 1
        end if
      end do
    end do
    deallocate(mat_coeffs%row_indices)
    deallocate(mat_coeffs%col_indices)
    deallocate(mat_coeffs%values)
    deallocate(b_coeffs%indices)
    deallocate(b_coeffs%values)

  end subroutine compute_boundary_coeffs

  !> @brief Sets the diffusion coefficient
  !
  !> @param[in] local_self_idx - the local cell index
  !> @param[in] index_nb  - the local neigbouring cell index
  !> @param[in] cell_mesh      - the mesh structure
  !> @param[out] coeff         - the diffusion coefficient
  module function calc_diffusion_coeff(local_self_idx, index_nb, cell_mesh) result(coeff)
    integer(ccs_int), intent(in) :: local_self_idx
    integer(ccs_int), intent(in) :: index_nb
    type(ccs_mesh), intent(in) :: cell_mesh
    real(ccs_real) :: coeff

    type(face_locator) :: face_location
    real(ccs_real) :: face_area
    real(ccs_real), parameter :: diffusion_factor = 1.e-2_ccs_real ! XXX: temporarily hard-coded
    logical :: is_boundary
    real(ccs_real), dimension(ndim) :: dx
    real(ccs_real) :: dxmag
    type(cell_locator) :: loc_p
    type(neighbour_locator) :: loc_nb

    call set_face_location(cell_mesh, local_self_idx, index_nb, face_location)
    call get_face_area(face_location, face_area)
    call get_boundary_status(face_location, is_boundary)

    call set_cell_location(cell_mesh, local_self_idx, loc_p)
    if (.not. is_boundary) then
      call set_neighbour_location(loc_p, index_nb, loc_nb)
      call get_distance(loc_p, loc_nb, dx)
    else
      call get_distance(loc_p, face_location, dx)
    end if
    dxmag = sqrt(sum(dx**2))
    
    coeff = -face_area * diffusion_factor / dxmag
  end function calc_diffusion_coeff

  !> @brief Calculates mass flux across given face. Note: assumes rho = 1 and uniform grid
  !
  !> @param[in] u, v     - arrays containing x, y velocities
  !> @param[in] p        - array containing pressure
  !> @param[in] p_x_gradients   - array containing pressure gradient in x
  !> @param[in] p_y_gradients   - array containing pressure gradient in y
  !> @param[in] invAu    - array containing inverse momentum diagonal in x
  !> @param[in] invAv    - array containing inverse momentum diagonal in y
  !> @param[in] loc_f    - face locator
  !> @param[out] flux    - The flux across the boundary
  module function calc_mass_flux(u, v, p, p_x_gradients, p_y_gradients, invAu, invAv, loc_f) result(flux)
    real(ccs_real), dimension(:), intent(in) :: u, v
    real(ccs_real), dimension(:), intent(in) :: p
    real(ccs_real), dimension(:), intent(in) :: p_x_gradients, p_y_gradients
    real(ccs_real), dimension(:), intent(in) :: invAu, invAv
    type(face_locator), intent(in) :: loc_f

    real(ccs_real) :: flux

    ! Local variables
    logical :: is_boundary                         !< Boundary indicator
    type(cell_locator) :: loc_p                    !< Primary cell locator
    type(neighbour_locator) :: loc_nb              !< Neighbour cell locator
    integer(ccs_int) :: index_nb                   !< Neighbour cell index
    real(ccs_real) :: flux_corr                    !< Flux correction
    real(ccs_real), dimension(ndim) :: dx          !< Cell-cell distance
    real(ccs_real) :: dxmag                        !< Cell-cell distance magnitude
    real(ccs_real), dimension(ndim) :: face_normal !< (local) face-normal array
    real(ccs_real) :: Vp                           !< Primary cell volume
    real(ccs_real) :: V_nb                         !< Neighbour cell volume
    real(ccs_real) :: Vf                           !< Face "volume"
    real(ccs_real) :: invAp                        !< Primary cell inverse momentum coefficient
    real(ccs_real) :: invA_nb                      !< Neighbour cell inverse momentum coefficient
    real(ccs_real) :: invAf                        !< Face inverse momentum coefficient
    
    call get_boundary_status(loc_f, is_boundary)
    if (.not. is_boundary) then
      associate(mesh => loc_f%mesh, &
           idxp => loc_f%cell_idx, &
           j => loc_f%cell_face_ctr)
        
        call set_cell_location(mesh, idxp, loc_p)
        call set_neighbour_location(loc_p, j, loc_nb)
        call get_local_index(loc_nb, index_nb)

        call get_face_normal(loc_f, face_normal)
        
        flux = 0.5_ccs_real * ((u(idxp) + u(index_nb)) * face_normal(1) &
             + (v(idxp) + v(index_nb)) * face_normal(2))

        !
        ! Rhie-Chow correction from Ferziger & Peric
        !
        call get_distance(loc_p, loc_nb, dx)
        dxmag = sqrt(sum(dx**2))
        call get_face_normal(loc_f, face_normal)
        flux_corr = -(p(index_nb) - p(idxp)) / dxmag
        flux_corr = flux_corr + 0.5_ccs_real * ((p_x_gradients(idxp) + p_x_gradients(index_nb)) * face_normal(1) &
             + (p_y_gradients(idxp) + p_y_gradients(index_nb)) * face_normal(2))

        call get_volume(loc_p, Vp)
        call get_volume(loc_nb, V_nb)
        Vf = 0.5_ccs_real * (Vp + V_nb)

        ! This is probably not quite right ...
        invAp = 0.5_ccs_real * (invAu(idxp) + invAv(idxp))
        invA_nb = 0.5_ccs_real * (invAu(index_nb) + invAv(index_nb))
        invAf = 0.5_ccs_real * (invAp + invA_nb)
        
        flux_corr = (Vf * invAf) * flux_corr
          
        ! Apply correction
        flux = flux + flux_corr

        if (idxp > index_nb) then
          ! XXX: making convention to point from low to high cell!
          flux = -flux
        end if
      end associate
    else 
      ! TODO: Write more general implementation handling BCs
      flux = 0.0_ccs_real ! XXX: hardcoded zero-flux BC
    end if
    
  end function calc_mass_flux

  !> @brief Calculates the row and column indices from flattened vector index. Assumes square mesh
  !
  !> @param[in] idx  - cell index
  !> @param[in] cps  - number of cells per side
  !> @param[out] row - cell row within mesh
  !> @param[out] col - cell column within mesh
  module subroutine calc_cell_coords(idx, cps, row, col)
    integer(ccs_int), intent(in) :: idx, cps
    integer(ccs_int), intent(out) :: row, col

    col = modulo(idx-1,cps) + 1 
    row = (idx-1)/cps + 1
  end subroutine calc_cell_coords

  !> @brief Performs an update of the gradients of a field.
  !
  !> @param[in]    cell_mesh - the mesh
  !> @param[inout] phi       - the field whose gradients we want to update
  !
  !> @note This will perform a parallel update of the gradient fields to ensure halo cells are
  !!       correctly updated on other PEs.

  module subroutine update_gradient(cell_mesh, phi)
  
    type(ccs_mesh), intent(in) :: cell_mesh
    class(field), intent(inout) :: phi

    real(ccs_real), dimension(:), pointer :: x_gradients_data, y_gradients_data, z_gradients_data
    real(ccs_real), dimension(:), allocatable :: x_gradients_old, y_gradients_old, z_gradients_old

    integer(ccs_real) :: i
    
    call get_vector_data(phi%x_gradients, x_gradients_data)
    call get_vector_data(phi%y_gradients, y_gradients_data)
    call get_vector_data(phi%z_gradients, z_gradients_data)

    associate(ntotal => cell_mesh%ntotal)
      allocate(x_gradients_old(ntotal))
      allocate(y_gradients_old(ntotal))
      allocate(z_gradients_old(ntotal))
      do i = 1, ntotal
        x_gradients_old(i) = x_gradients_data(i)
        y_gradients_old(i) = y_gradients_data(i)
        z_gradients_old(i) = z_gradients_data(i)
      end do
    end associate
    
    call restore_vector_data(phi%x_gradients, x_gradients_data)
    call restore_vector_data(phi%y_gradients, y_gradients_data)
    call restore_vector_data(phi%z_gradients, z_gradients_data)
    
    call update_gradient_component(cell_mesh, 1, phi%values, x_gradients_old, y_gradients_old, z_gradients_old, phi%x_gradients)
    call update(phi%x_gradients) ! XXX: opportunity to overlap update with later compute (begin/compute/end)
    call update_gradient_component(cell_mesh, 2, phi%values, x_gradients_old, y_gradients_old, z_gradients_old, phi%y_gradients)
    call update(phi%y_gradients) ! XXX: opportunity to overlap update with later compute (begin/compute/end)
    call update_gradient_component(cell_mesh, 3, phi%values, x_gradients_old, y_gradients_old, z_gradients_old, phi%z_gradients)
    call update(phi%z_gradients) ! XXX: opportunity to overlap update with later compute (begin/compute/end)

    deallocate(x_gradients_old)
    deallocate(y_gradients_old)
    deallocate(z_gradients_old)
    
  end subroutine update_gradient

  !> @brief Helper subroutine to calculate a gradient component at a time.
  !
  !> @param[in] cell_mesh   - the mesh
  !> @param[in] component   - which vector component (i.e. direction) to update?
  !> @param[in] phi         - a cell-centred array of the field whose gradient we
  !!                          want to compute
  !> @param[inout] gradients - a cell-centred array of the gradient
  subroutine update_gradient_component(cell_mesh, component, phi, x_gradients_old, y_gradients_old, z_gradients_old, gradients)


    type(ccs_mesh), intent(in) :: cell_mesh
    integer(ccs_int), intent(in) :: component
    class(ccs_vector), intent(in) :: phi
    real(ccs_real), dimension(:), intent(in) :: x_gradients_old
    real(ccs_real), dimension(:), intent(in) :: y_gradients_old
    real(ccs_real), dimension(:), intent(in) :: z_gradients_old
    class(ccs_vector), intent(inout) :: gradients
    
    type(vector_values) :: grad_values
    real(ccs_real), dimension(:), pointer :: phi_data
    real(ccs_real) :: grad
    
    integer(ccs_int) :: i
    integer(ccs_int) :: j
    type(cell_locator) :: loc_p
    type(face_locator) :: loc_f
    type(neighbour_locator) :: loc_nb
    
    integer(ccs_int) :: nnb
    integer(ccs_int) :: nb
    
    real(ccs_real) :: phif

    logical :: is_boundary

    real(ccs_real) :: face_area
    real(ccs_real), dimension(ndim) :: face_norm

    real(ccs_real) :: V
    integer(ccs_int) :: idxg

    real(ccs_real), dimension(ndim) :: dx
    
    allocate(grad_values%indices(1))
    allocate(grad_values%values(1))
    grad_values%setter_mode = insert_mode

    call get_vector_data(phi, phi_data)
    
    do i = 1, cell_mesh%nlocal
      grad = 0.0_ccs_int
      
      call set_cell_location(cell_mesh, i, loc_p)
      call count_neighbours(loc_p, nnb)
      do j = 1, nnb
        call set_face_location(cell_mesh, i, j, loc_f)
        call get_boundary_status(loc_f, is_boundary)

        if (.not. is_boundary) then
          call set_neighbour_location(loc_p, j, loc_nb)
          call get_local_index(loc_nb, nb)
          phif = 0.5_ccs_real * (phi_data(i) + phi_data(nb)) ! XXX: Need to do proper interpolation
        else
          call get_distance(loc_p, loc_f, dx)
          phif = phi_data(i) + (x_gradients_old(i) * dx(1) + y_gradients_old(i) * dx(2) + z_gradients_old(i) * dx(3))
        end if

        call get_face_area(loc_f, face_area)
        call get_face_normal(loc_f, face_norm)

        grad = grad + phif * (face_area * face_norm(component))
      end do

      call get_volume(loc_p, V)
      grad = grad / V
      
      call get_global_index(loc_p, idxg)
      call pack_entries(1, idxg, grad, grad_values)
      call set_values(grad_values, gradients)
    end do

    call restore_vector_data(phi, phi_data)
    
  end subroutine update_gradient_component
  
end submodule fv_common
