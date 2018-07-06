module postprocessing
   use integrator
   use shapebeam
   use mueller

   implicit none

contains

!****************************************************************************80
! Test the numerical and analytical methods of calculating scattering forces. 
! When incident field is planewave, the results should match always. Numerical
! shenanigans seem to occur with other beams. PSA: Fixing it can be a hassle.
   subroutine test_methods(matrices, mesh)
      type(data) :: matrices
      type(mesh_struct) :: mesh
      integer :: i, j, ii, range(2)
      real(dp), dimension(:, :), allocatable :: Q_fcoll, Q_tcoll
      real(dp), dimension(3) :: F, N, FF, NN, N_B, N_DG
      real(dp) :: urad

      call rot_setup(matrices, mesh)

      allocate (Q_fcoll(3, matrices%bars))
      allocate (Q_tcoll(3, matrices%bars))

      if (matrices%whichbar == 0) then
         range(1) = 1
         range(2) = matrices%bars
      else
         range(1) = matrices%whichbar
         range(2) = matrices%whichbar
         write (*, '(A, 20F6.3)') ' Chosen wavelength: ', 2d6*pi/mesh%ki(matrices%whichbar)
      end if

      do j = 1, 2
         N = dcmplx(0.0d0, 0.0d0)
         F = dcmplx(0.0d0, 0.0d0)
         Q_tcoll = 0d0
         Q_fcoll = 0d0

         do i = range(1), range(2)
            select case (j)
            case (1); call forcetorque_num(matrices, mesh, i)
            case (2); call forcetorque(matrices, mesh, i)
            end select
            ii = i
            if (matrices%whichbar > 0) ii = matrices%whichbar
            F = F + matrices%force
            N = N + matrices%torque
            urad = epsilon*(matrices%E_rel(ii)*matrices%E)**2/2d0
            Q_fcoll(:, ii) = matmul(matrices%R, &
               matrices%force/urad/pi/mesh%a**2)
            Q_tcoll(:, ii) = matmul(matrices%R, &
               matrices%torque*(mesh%ki(ii))/urad/pi/mesh%a**2)
         end do

         NN = matmul(matrices%R, N)
         FF = matmul(matrices%R, F)

         print *, ''
         select case (j)
         case (1); write (*, '(A)') 'Numerical integration of MST:'
         case (2); write (*, '(A)') 'Analytical VSWF coefficient integration of MST:'
         end select
         write (*, '(A,3ES11.3,A)') ' F = (', real(FF), ' ) N'
         write (*, '(A,3ES11.3,A)') ' N = (', real(NN), ' ) Nm'

         if (j == 2) then
            N_DG = DG_torque(matrices, mesh)
            N_B = barnett_torque(matrices, mesh)

            write (*, '(A,3ES11.3,A)') ' N_DG = (', real(N_DG), ' ) Nm'
            write (*, '(A,3ES11.3,A)') ' N_B = (', real(N_B), ' ) Nm'
         end if

         print *, ''

         print *, 'Efficiencies for each wavelength separately'
         do i = 1, size(Q_fcoll, 2)
            Q_fcoll(:, i) = matmul(matrices%R, Q_fcoll(:, i))
            Q_tcoll(:, i) = matmul(matrices%R, Q_tcoll(:, i))
         end do

         write (*, '(A, 80F7.1)') 'WL(nm):', 2d9*pi/mesh%ki
         write (*, '(A, 80F7.3)') '   Qfx:', Q_fcoll(1, :)
         write (*, '(A, 80F7.3)') '   Qfy:', Q_fcoll(2, :)
         write (*, '(A, 80F7.3)') '   Qfz:', Q_fcoll(3, :)

         write (*, '(A, 80F7.3)') '   Qtx:', Q_tcoll(1, :)
         write (*, '(A, 80F7.3)') '   Qty:', Q_tcoll(2, :)
         write (*, '(A, 80F7.3)') '   Qtz:', Q_tcoll(3, :)
      end do

   end subroutine test_methods

!****************************************************************************80
! Calculates the torque efficiency of a particle averaged over rotation
! about its major axis of inertia (a_3) for angles 0 to pi between
! a_3 and incident k0. Results are automatically comparable with DDSCAT.
   subroutine torque_efficiency(matrices, mesh, q_factor)
      type(data) :: matrices
      type(mesh_struct) :: mesh
      real(dp), intent(out), optional :: q_factor
      integer :: i, Ntheta
      real(dp), dimension(3) :: Q_t
      real(dp), dimension(:), allocatable :: theta
      real(dp), dimension(:, :), allocatable :: Q_coll

      Ntheta = 60 ! Angle of rotation of a_3 about e_1 (when psi=0)

      allocate (theta(Ntheta), Q_coll(3, Ntheta))
      call linspace(0d0, pi, Ntheta, theta)

! Torque efficiency calculations as in Lazarian2007b
      write (*, '(A)') '  Starting the calculation of beta-averaged torque efficiency:'
! Theta loop
      do i = 1, Ntheta
         Q_t = get_Qav(matrices, mesh, theta(i), 0d0)
! Flip the coordinate labels to match Lazarian2007b: In this code, k is along 
! z instead of x, 0-polarization is the y of L2007b. So, inverse that next.
         Q_coll(:, i) = [Q_t(3),Q_t(1),Q_t(2)]
         call print_bar(i, Ntheta)
      end do
      q_factor = maxval(abs(Q_coll(1,:)))/maxval(abs(Q_coll(2,:)))
      open (unit=1, file="out/Q"//trim(matrices%out), ACTION="write", STATUS="replace")
      if(present(q_factor)) then
         write (1, '(1E12.3)') q_factor
      else
         write (1, '(A)') 'cos(theta)  Q_{t,1} Q_{t,2} Q_{t,3}'
         do i = 1, Ntheta
            write (1, '(4E12.3)') dcos(theta(i)), Q_coll(:, i)
         end do
      end if 
      close (1)
   end subroutine torque_efficiency

!****************************************************************************80
! Mueller matrices needed in SOCpol.
   subroutine test_mueller(matrices, mesh, Ntheta, Nphi)
      type(data) :: matrices
      type(mesh_struct) :: mesh
      integer :: i, j, ind, halton_init, Nphi, Ntheta
      real(dp), dimension(:,:), allocatable :: points

      halton_init = 0
      allocate(points(2,Ntheta*Nphi))

      ind = 1
      do i = 1, Ntheta
         do j = 1, Nphi
            points(1, ind) = pi*(i - 1)/(Ntheta) + pi/Ntheta/2.0
            points(2, ind) = 2*pi*(j - 1)/Nphi
            ind = ind + 1
         end do
      end do

      call scattering_extinction_matrices(matrices, mesh, points)

   end subroutine test_mueller

end module postprocessing
