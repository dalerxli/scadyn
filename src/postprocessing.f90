module postprocessing
use integrator
use shapebeam
use mueller

implicit none

contains

!******************************************************************************

subroutine test_methods( matrices, mesh )
type(data) :: matrices
type(mesh_struct) :: mesh
integer :: i, j, ii, range(2)
real(dp), dimension(:,:), allocatable :: Q_fcoll, Q_tcoll
real(dp), dimension(3) :: k0, E0, E90
complex(dp), dimension(3) :: F, N, FF, NN, N_B, N_DG
real(dp) :: Qmag
complex(dp), dimension(:,:), allocatable :: MM_nm, NN_nm
! Now, to comply with the properties of DDSCAT, the scattering happens
! with respect to the particle principal axes
matrices%khat = matrices%P(:,3)
! matrices%B = vlen(matrices%B)*(0.5d0*matrices%P(:,1) + matrices%P(:,3))
write(*,'(A, 3ES11.3)') ' B: ', matrices%B
matrices%Rexp = find_Rexp( matrices )
matrices%Rexp = transpose( matrices%Rexp )

call rot_setup(matrices)

allocate(Q_fcoll(3,matrices%bars))
allocate(Q_tcoll(3,matrices%bars))

if(matrices%whichbar == 0) then
   range(1) = 1
   range(2) = matrices%bars
else
   range(1) = matrices%whichbar
   range(2) = matrices%whichbar
   write(*,'(A, 20F6.3)') ' Chosen wavelength: ', 2d6*pi/mesh%ki(matrices%whichbar)
end if
 
do j = 1,2
   N = dcmplx(0.0d0, 0.0d0)
   F = dcmplx(0.0d0, 0.0d0)
   Q_tcoll = 0d0
   Q_fcoll = 0d0

	do i = range(1),range(2)
      select case (j)
			case(1); call forcetorque_num(i, matrices, mesh)
			case(2); call forcetorque(i, matrices, mesh)
		end select
      ii = i
      if(matrices%whichbar > 0) ii = matrices%whichbar
      F = F + matrices%force
      N = N + matrices%torque
      Q_fcoll(:,ii) = matmul(matrices%R,matrices%Q_f)
      Q_tcoll(:,ii) = matmul(matrices%R,matrices%Q_t)
	end do

   NN =  matmul(matrices%R, N)
   FF =  matmul(matrices%R, F)

   print*, ''
   select case (j)
		case(1); write(*,'(A)') 'Numerical integration of MST:'
		case(2); write(*,'(A)') 'Analytical VSWF coefficient integration of MST:'
	end select
   write(*,'(A,3ES11.3,A)') ' F = (', real(FF), ' ) N'
   write(*,'(A,3ES11.3,A)') ' N = (', real(NN), ' ) Nm'

   write(*,'(A)') '  [ In body coordinates, where incident field direction = z_b = a_3:'
   write(*,'(A,3ES11.3,A)') '   F = (', matmul(matrices%P,real(FF)), ' ) N'
   write(*,'(A,3ES11.3,A)') '   N = (', matmul(matrices%P,real(NN)), ' ) Nm ]'

	if(j == 2) then
      N_DG = DG_torque(matrices,mesh)
      N_B = barnett_torque(matrices,mesh)

      write(*,'(A,3ES11.3,A)') ' N_DG = (', real(N_DG), ' ) Nm'
      write(*,'(A,3ES11.3,A)') ' N_B = (', real(N_B), ' ) Nm'
	end if 

   print*, ''

   print*, 'Efficiencies for each wavelength separately, in body coordinates'
	do i = 1, size(Q_fcoll,2)
      Q_fcoll(:,i) = matmul(matrices%P,Q_fcoll(:,i))
      Q_tcoll(:,i) = matmul(matrices%P,Q_tcoll(:,i))
	end do

   write(*,'(A, 80F7.1)') 'WL(nm):', 2d9*pi/mesh%ki
   write(*,'(A, 80F7.3)') '   Qfx:', Q_fcoll(1,:)
   write(*,'(A, 80F7.3)') '   Qfy:', Q_fcoll(2,:)
   write(*,'(A, 80F7.3)') '   Qfz:', Q_fcoll(3,:)

   write(*,'(A, 80F7.3)') '   Qtx:', Q_tcoll(1,:)
   write(*,'(A, 80F7.3)') '   Qty:', Q_tcoll(2,:)
   write(*,'(A, 80F7.3)') '   Qtz:', Q_tcoll(3,:)
end do

! allocate(MM_nm(3,(matrices%Nmaxs(1)+1)**2-1), NN_nm(3,(matrices%Nmaxs(1)+1)**2-1))
! call MN_circ(MM_nm, NN_nm, matrices%Nmaxs(1), dcmplx(mesh%ki(1)), [0d0, -7d-7, -7d-7], 0)
! do i = 1,size(MM_nm,2)
!    write(*,'(3(ES11.3,SP,ES11.3,"i"))') MM_nm(:,i)
! end do

! do i = 1, size(Q_fcoll,2)
! 	Q_fcoll(:,i) = matmul(transpose(matrices%P),Q_fcoll(:,i))
! 	Q_tcoll(:,i) = matmul(transpose(matrices%P),Q_tcoll(:,i))
! end do

! call print_mat(matrices%P, 'P')
! write(*,'(A, 3ES12.4)')  'Ip   =', matrices%Ip
! write(*,'(A, 3F8.4)') 'E0   =', real(matrices%E0hat)
! write(*,'(A, 3F8.4)') 'E90  =', real(matrices%E90hat)
! write(*,'(A, 3F8.4)') 'khat =', matrices%khat

! open(unit=2, file="out/Q.dat", ACTION="write", STATUS="replace")
! write(2,'(A)') "      ka        Qf_k       Qt_1       Qt_2       Qt_3       |Qt|"
! do i = range(1),range(2)
! 	ii = i
! 	if(matrices%whichbar > 0) ii = matrices%whichbar
! 	Qmag = dsqrt(Q_tcoll(1,ii)**2 + Q_tcoll(2,ii)**2 + Q_tcoll(3,ii)**2)
! 	write(2,'(9F11.7)') mesh%ki(ii)*mesh%a, &
! 	dot_product(Q_fcoll(:,ii),matrices%khat), &
! 	dot_product(Q_tcoll(:,ii),matrices%khat), &
! 	dot_product(Q_tcoll(:,ii),-matrices%P(:,2)), &
! 	dot_product(Q_tcoll(:,ii),-matrices%P(:,1)),  Qmag
! end do
! close(2)

end subroutine test_methods

!******************************************************************************
! Calculates the torque efficiency of a particle averaged over rotation
! about its major axis of inertia (a_3) for angles 0 to pi between 
! a_3 and incident k0. Results are automatically comparable with DDSCAT.
subroutine torque_efficiency( matrices, mesh )
type(data) :: matrices
type(mesh_struct) :: mesh
integer :: i, j, k, Nang, Bang, psi_deg, ind
real(dp), dimension(3, 3) ::  R_beta, R_phi, R_thta, R_Jb, R_B, R_xi
real(dp), dimension(3) :: k0, E0, E90, Q_t, nbeta, nphi, a_3, Jb, x_B, y_lab
real(dp) :: theta, beta, xi, phi, psi
real(dp), dimension(:,:), allocatable :: Q_coll, F_coll
real(dp), dimension(:), allocatable :: psis
call rot_setup(matrices)

k0 = matrices%khat
E0 = real(matrices%E0hat)
E90 = real(matrices%E90hat)

a_3 = matrices%P(1:3,3)
!~ write(*,'(A,3F7.3)') '  a_3  =', a_3

Nang = 180 ! Angle of rotation of a_3 about e_1 (when psi=0)
Bang = 360 ! Angle of averaging over beta

allocate(Q_coll(3,Nang))
Q_coll(:,:) = 0d0

! Torque efficiency calculations as in Lazarian2007b
write(*,'(A)') '  Starting the calculation of beta-averaged torque efficiency:'
! Theta loop
do i=0,Nang-1
   Q_t = 0d0
   theta = dble(i)*pi/180d0
   ! Beta averaging loop
	do j = 0,Bang-1
      ! Find rotation of angle beta around the rotated a_3-axis
      beta = dble(j)*pi/Bang*2d0
      
      ! Flip the coordinate labels to match Lazarian2007b
      Q_t = matmul(matrices%Rkt,Qt(matrices,mesh,theta,beta,0d0))
      Q_t = [dot_product(Q_t,k0),dot_product(Q_t,E0),dot_product(Q_t,E90)]
      Q_coll(:,i+1) = Q_coll(:,i+1) + Q_t/Bang
	end do
   call print_bar(i+1,Nang)
end do

open(unit=1, file="out/Q.out", ACTION="write", STATUS="replace")
write(1,'(A)') 'cos(theta)  Q_{t,1} Q_{t,2} Q_{t,3}'
do i = 0,Nang-1
theta = dble(i)*pi/180d0
write(1,'(4E12.3)') dcos(theta), Q_coll(:,i+1)
end do
close(1)

! Radiative torque calculations, emulating work of Draine & Weingartner (1997), ApJ 480:633
allocate(psis(5))
psis = [1d0, 30d0, 60d0, 80d0, 90d0]

allocate(F_coll(6,Nang*size(psis,1)))
F_coll(:,:) = 0d0
ind = 0

write(*,'(A)') '  Starting the calculation of beta-averaged radiative torques:'
do psi_deg = 1,size(psis,1)
   psi = dble(psis(psi_deg))*pi/180
   ! y_lab = [0d0, 1d0, 0d0]
   ! x_B = matmul(R_aa(y_lab,psi),[1d0,0d0,0d0])
   x_B = [0d0,1d0,0d0]
   R_B = rotate_a_to_b(a_3,matrices%B)
   a_3 = matmul(R_B,a_3)
   Q_coll = 0d0
   ! Xi loop

   do i=0,Nang-1
      xi = dble(i)*pi/180d0
      
      R_xi = R_aa(x_B,xi)

      ! Rotation axis for precession averaging for current xi
      nphi = matrices%B/vlen(matrices%B) ! Ensure unit length of axis vector
      ! Beta averaging loop
      do j = 0,Bang-1
         Q_t = 0d0

         ! Find rotation of angle beta around the rotated a_3-axis
         phi = dble(j)*pi/Bang*2d0
         R_phi = R_aa(nphi,phi)

         ! The ultimate rotation matrices for scattering event
         matrices%R = matmul(R_phi,R_xi) ! First a_3 to xi, then beta about a_3
         call rot_setup(matrices)

         if (matrices%whichbar == 0) then
            do k = 1,matrices%bars
               call forcetorque(k, matrices, mesh)
               Q_t = Q_t + matrices%Q_t/matrices%bars
            end do
         else
            k = matrices%whichbar
            call forcetorque(k, matrices, mesh)
            Q_t = Q_t + matrices%Q_t
         end if

         Q_t = matmul(matrices%R,Q_t)
         Q_coll(:,i+1) = Q_coll(:,i+1) + Q_t/Bang
      end do
      F_coll(1:2,ind+1) = [xi, psi]
      F_coll(3,ind+1) = F_align(Q_coll(:,i+1),xi,phi,psi)
      F_coll(4,ind+1) = H_align(Q_coll(:,i+1),xi,phi,psi)
      F_coll(5,ind+1) = G_align(Q_coll(:,i+1),xi,phi,psi)
      call print_bar(ind,size(F_coll,2))
      ind = ind + 1

   end do
end do

open(unit=1, file="out/F.out", ACTION="write", STATUS="replace")
write(1,'(A)') 'xi   phi   psi   F  H  G'
do i = 0,size(F_coll,2)-1
write(1,'(6E12.3)') dcos(F_coll(1:2,i+1)), F_coll(3:5,i+1)
end do
close(1)

end subroutine torque_efficiency

!*******************************************************************************

subroutine stability_analysis(matrices,mesh)
type(data) :: matrices
type(mesh_struct) :: mesh
integer :: i, j, k, l, ind, Npoints, Nang, Bang, N_J, Nphi, Ntheta
real(dp), dimension(3, 3) ::  R_beta, R_thta
real(dp), dimension(3) :: Q_t, nbeta
real(dp) :: thta, beta
real(dp), dimension(:,:), allocatable :: Q_coll, vec
real(dp) :: res, res1, res2, res3, mx
real(dp), dimension(3) :: k0, a_1, a_2, a_3, knew, NN, maxdir, anew
complex(dp), dimension(3) :: N
real(dp), dimension(:), allocatable :: theta, costheta, phi 

call rot_setup(matrices)

k0 = matrices%khat

a_1 = matrices%P(1:3,1)
a_2 = matrices%P(1:3,2)
a_3 = matrices%P(1:3,3)
!~ write(*,'(A,3F7.3)') '  a_3  =', a_3

Ntheta = 90
Nphi = 180
allocate(theta(Ntheta),costheta(Ntheta),phi(Nphi))
call linspace(0d0,2d0*pi,Nphi,phi)
call linspace(1d0,-1d0,Ntheta,costheta)
do i = 1,Ntheta
   theta(i) = dacos(costheta(i))
end do
Npoints = Ntheta*Nphi
allocate(vec(3,Npoints))
vec = 0d0
mx = 0d0

!~ vec = fibonacci_sphere(Npoints,1)
vec = uniform_sphere(Npoints,theta,phi)

open(unit=1, file="out/NdotQ.dat", ACTION="write", STATUS="replace")
write(1,'(2(A,I0))') 'Ntheta = ', Ntheta, ' | Nphi = ', Nphi
write(1,'(A)') '  x   y   z   N.a_1   N.a_2   N.a_3'

do i = 1,Npoints
   N = dcmplx(0d0)
   knew = vec(:,i)       
   ! The ultimate rotation matrices for scattering event
   matrices%R = rotate_a_to_b(k0,knew)
   call rot_setup(matrices)

	if (matrices%whichbar == 0) then
		do k = 1,matrices%bars
         call forcetorque(k, matrices, mesh)
         N = N + matrices%Q_t
		end do
	else
      k = matrices%whichbar
      call forcetorque(k, matrices, mesh)
      N = N + matrices%Q_t
	end if
   anew = matmul(transpose(matrices%R),a_3)
   NN = matmul(transpose(matrices%P) , real(N))
   res1 = dot_product(NN,a_1)
   res2 = dot_product(NN,a_2)
   res3 = dot_product(NN,a_3)
	if (res3 > mx) then
      mx = res3
      maxdir = anew
	end if
   write(1,'(6E12.3)') anew(1), anew(2), anew(3), res1, res2, res3
   call print_bar(i+1,Npoints)
end do

close(1)
res = dacos(dot_product([0d0,0d0,1d0],maxdir/vlen(maxdir)))*180d0/pi
write(*,'(A,3F7.3,A,F7.3)') 'Stablest direction = (', maxdir, ' ), angle between a_3 and k = ', res

N_J  = 5
Nang = 180 ! Angle of rotation of a_3 about e_1 (when psi=0)
Bang = 360 ! Angle of averaging over beta

allocate(Q_coll(3,Nang))
Q_coll(:,:) = 0d0
ind = 0

open(unit=1, file="out/N.out", ACTION="write", STATUS="replace")
write(1,'(A)') 'cos(theta)  N_k   N_E0    N_E90'

! Theta loop
do i=0,Nang-1
   thta = dble(i)*pi/180d0
   R_thta = R_theta(matrices, thta)
   N = 0d0

   ! Rotation axis for beta averaging for current theta
   nbeta = matmul(R_thta,a_3) ! Beta rotation about a_3
   nbeta = nbeta/vlen(nbeta) ! Ensure unit length of axis vector

   ! Beta averaging loop
	do j = 0,Bang-1
      Q_t = 0d0

      ! Find rotation of angle beta around the rotated a_3-axis
      beta = dble(j)*pi/Bang*2d0
      R_beta = R_aa(nbeta,beta)

      ! The ultimate rotation matrices for scattering event
      matrices%R = matmul(R_beta,R_thta) ! First a_3 to theta, then beta about a_3
      call rot_setup(matrices)
		if (matrices%whichbar == 0) then
			do k = 1,matrices%bars
            call forcetorque(k, matrices, mesh)
            N = N + matrices%torque
			end do
		else
         k = matrices%whichbar
         call forcetorque(k, matrices, mesh)
         N = N + matrices%torque
		end if
      ! Flip the coordinate labels to match Lazarian2007b
      NN = matmul(matrices%Rkt,real(N))
      NN = [dot_product(NN,matrices%khat),&
      dot_product(NN,real(matrices%E0hat)),dot_product(NN,real(matrices%E90hat))]
      Q_coll(:,i+1) = Q_coll(:,i+1) + NN
	end do
!~ 	NN = matmul(transpose(matrices%R) , real(N))
   ind = ind + 1
   call print_bar(ind,Nang)

   write(1,'(4E14.5)') dcos(thta), Q_coll(:,i+1)

end do
close(1)

end subroutine stability_analysis

end module postprocessing
