module forces
   use T_matrix

   implicit none

contains

!****************************************************************************80
! Calculate forces and torques during single step
   function get_forces() result(FN)
      real(dp), dimension(3, 3) :: RT, R_k, R_k90
      complex(dp), dimension(3) :: F, N, N_DG, N_B
      complex(dp), dimension(6) :: FN
      integer :: i

      RT = transpose(matrices%R)
      R_k = matmul(RT, matrices%R_fixk)
      R_k90 = matmul(R_k, matrices%R90_init)

      call gen_rotations(R_k, R_k90)

      matrices%khat = matmul(RT, matrices%k_orig)
      matrices%E0hat = dcmplx(matmul(R_k, matrices%E0_orig), 0.0d0)
      matrices%E90hat = dcmplx(matmul(R_k90, matrices%E90_orig), 0.0d0)

      FN = dcmplx(0.0d0, 0.0d0)
      N = dcmplx(0.0d0, 0.0d0)
      F = dcmplx(0.0d0, 0.0d0)

! Iteration of a single wavelength
      if (matrices%whichbar == 0) then
         do i = 1, matrices%bars
            call forcetorque(i)
            F = F + matrices%force
            N = N + matrices%torque
         end do
      else
         call forcetorque(matrices%whichbar)
         F = F + matrices%force
         N = N + matrices%torque
      end if

      if (calc_extra_torques == 1) then
         N_DG = DG_torque()
         N_B = barnett_torque()

         N = N + N_B + N_DG
      end if

      FN(1:3) = dcmplx(matmul(matrices%R, real(F))) ! {x}_sca -> {x}_lab
      FN(4:6) = dcmplx(matmul(transpose(matrices%P), real(N))) ! {N}_sca -> {N}_b

   end function get_forces

!****************************************************************************80
! Calculate forces and torques using numerical integration of Maxwell stress
! tensor
   subroutine forcetorque_num(j)
      complex(dp), dimension(:), allocatable :: a_in, b_in, a90, b90, &
                                                a, b, a_nm, b_nm, a_nm90, b_nm90
      complex(dp), dimension(:, :), allocatable :: Taa, Tab, Tba, Tbb
      complex(8), dimension(:), allocatable :: rotD, rotD90
      integer, dimension(:, :), allocatable :: indD, indD90
      complex(dp) :: F(3), G(3), F90(3), G90(3)
      integer :: Nmax, j, las, nm

      integer :: i1
      real(dp) :: r(3), n(3), E, Pow
      complex(dp) :: E1(3), H1(3), E2(3), H2(3), T1(3, 3), ED1(3, 3), &
                     HB1(3, 3), T2(3, 3), ED2(3, 3), HB2(3, 3), I(3, 3), H0(3), &
                     H90(3)
      complex(dp) :: torque1(3), torque2(3), torque(3), force1(3), force2(3), force(3)

      E = matrices%E_rel(j)*matrices%E

      matrices%E0 = E*matrices%E0hat
      matrices%E90 = E*matrices%E90hat
      mesh%k = mesh%ki(j)

      Pow = E**2/sqrt(mu/epsilon)/2d0/cc

      Nmax = matrices%Nmaxs(j)
      las = (Nmax + 1)*(2*Nmax + 1)*(2*Nmax + 3)/3 - 1
      nm = (Nmax + 1)**2 - 1

      rotD = matrices%rotDs(1:las, j)
      indD = matrices%indDs(1:las, :, j)
      rotD90 = matrices%rotD90s(1:las, j)
      indD90 = matrices%indD90s(1:las, :, j)

      Taa = matrices%Taai(1:nm, 1:nm, j)
      Tab = matrices%Tabi(1:nm, 1:nm, j)
      Tba = matrices%Tbai(1:nm, 1:nm, j)
      Tbb = matrices%Tbbi(1:nm, 1:nm, j)

      a_in = E*matrices%as(1:nm, j)
      b_in = E*matrices%bs(1:nm, j)

      a = sparse_matmul(rotD, indD, a_in, nm)
      b = sparse_matmul(rotD, indD, b_in, nm)
      a90 = sparse_matmul(rotD90, indD90, a_in, nm)
      b90 = sparse_matmul(rotD90, indD90, b_in, nm)

      if (matrices%polarization == 1) then
         a90 = dcmplx(0d0)
         b90 = dcmplx(0d0)
      end if

      a_nm = matmul(Taa, a) + matmul(Tab, b)
      b_nm = matmul(Tbb, b) + matmul(Tba, a)
      a_nm90 = matmul(Taa, a90) + matmul(Tab, b90)
      b_nm90 = matmul(Tbb, b90) + matmul(Tba, a90)

      matrices%force = dcmplx(0.0d0, 0.0d0)
      matrices%torque = dcmplx(0.0d0, 0.0d0)

      H0 = crossCC(dcmplx(matrices%khat, 0.0d0), matrices%E0)*dcmplx(sqrt(epsilon/mu))
      H90 = crossCC(dcmplx(matrices%khat, 0.0d0), matrices%E90)*dcmplx(sqrt(epsilon/mu))

      I = dcmplx(eye(3))

      force1(:) = dcmplx(0.0d0, 0.0d0)
      torque1(:) = dcmplx(0.0d0, 0.0d0)
      force2(:) = dcmplx(0.0d0, 0.0d0)
      torque2(:) = dcmplx(0.0d0, 0.0d0)

      do i1 = 1, size(mesh%P, 2)
         r = mesh%P(:, i1)
         n = r/vlen(r)

         call calc_fields(a_nm, b_nm, dcmplx(mesh%k), r, F, G, 1) ! 1 inout means outgoing wave
         call calc_fields(a_nm90, b_nm90, dcmplx(mesh%k), r, F90, G90, 1)

         E1 = F + matrices%E0*exp(dcmplx(0.0d0, mesh%k*dot_product(matrices%khat, r)))
         H1 = G + H0*exp(dcmplx(0.0d0, mesh%k*dot_product(matrices%khat, r)))

         ED1(:, 1) = epsilon*E1(:)*conjg(E1(1))
         ED1(:, 2) = epsilon*E1(:)*conjg(E1(2))
         ED1(:, 3) = epsilon*E1(:)*conjg(E1(3))

         HB1(:, 1) = mu*H1(:)*conjg(H1(1))
         HB1(:, 2) = mu*H1(:)*conjg(H1(2))
         HB1(:, 3) = mu*H1(:)*conjg(H1(3))

         E2 = F90+matrices%E90*exp(dcmplx(0.0d0, mesh%k*dot_product(matrices%khat, r)))
         H2 = G90+H90*exp(dcmplx(0.0d0, mesh%k*dot_product(matrices%khat, r)))

         ED2(:, 1) = epsilon*E2(:)*conjg(E2(1))
         ED2(:, 2) = epsilon*E2(:)*conjg(E2(2))
         ED2(:, 3) = epsilon*E2(:)*conjg(E2(3))

         HB2(:, 1) = mu*H2(:)*conjg(H2(1))
         HB2(:, 2) = mu*H2(:)*conjg(H2(2))
         HB2(:, 3) = mu*H2(:)*conjg(H2(3))

! Maxwell's stress tensor
         T1 = -ED1 - HB1 + dcmplx(0.5d0)*(dcmplx(epsilon)*dot_product(E1, E1) + &
                                          dcmplx(mu)*dot_product(H1, H1))*I
         T2 = -ED2 - HB2 + dcmplx(0.5d0)*(dcmplx(epsilon)*dot_product(E2, E2) + &
                                          dcmplx(mu)*dot_product(H2, H2))*I

! Force
         force1 = force1 - dcmplx(0.5d0)*matmul(T1, dcmplx(n))*dcmplx(mesh%w(i1))
         force2 = force2 - dcmplx(0.5d0)*matmul(T2, dcmplx(n))*dcmplx(mesh%w(i1))

! Torque
         torque1 = torque1 - dcmplx(0.5d0)*crossRC(r, matmul(T1, dcmplx(n)))*dcmplx(mesh%w(i1))
         torque2 = torque2 - dcmplx(0.5d0)*crossRC(r, matmul(T2, dcmplx(n)))*dcmplx(mesh%w(i1))
      end do

! The total optical force is the average of the forces, according to the number of polarizations
      force = (force1 + force2)/matrices%polarization
      torque = (torque1 + torque2)/matrices%polarization

      matrices%force = force
      matrices%torque = torque
      matrices%Q_t = dble(torque)*(mesh%k)/Pow/pi/mesh%a**2
      matrices%Q_f = dble(force)/Pow/pi/mesh%a**2

   end subroutine forcetorque_num

!****************************************************************************80
! Calculate forces and torques using the analytical z-formulae
   subroutine forcetorque(i)
      complex(dp), dimension(:), allocatable :: a_in, b_in, a90, b90, &
                                                a, b, p, q, p90, q90, a2, b2, p2, q2, a290, b290, p290, q290
      complex(dp), dimension(:, :), allocatable :: Taa, Tab, Tba, Tbb
      complex(8), dimension(:), allocatable :: rotD, rotD90
      integer, dimension(:, :), allocatable :: indD, indD90
      integer :: Nmax, i, las, nm
      real(dp) :: tx, ty, tz, fx, fy, fz, Pow, E

      E = matrices%E_rel(i)*matrices%E
      mesh%k = mesh%ki(i)

      Nmax = matrices%Nmaxs(i)
      las = (Nmax + 1)*(2*Nmax + 1)*(2*Nmax + 3)/3 - 1
      nm = (Nmax + 1)**2 - 1

      allocate (a(nm), b(nm), a90(nm), b90(nm), p(nm), q(nm), p90(nm), q90(nm))

      rotD = matrices%rotDs(1:las, i)
      indD = matrices%indDs(1:las, :, i)
      rotD90 = matrices%rotD90s(1:las, i)
      indD90 = matrices%indD90s(1:las, :, i)

      Taa = matrices%Taai(1:nm, 1:nm, i)
      Tab = matrices%Tabi(1:nm, 1:nm, i)
      Tba = matrices%Tbai(1:nm, 1:nm, i)
      Tbb = matrices%Tbbi(1:nm, 1:nm, i)

      a_in = E*matrices%as(1:nm, i)/sqrt(2d0*sqrt(mu/epsilon)*mesh%k**2)/2d0
      b_in = E*matrices%bs(1:nm, i)/sqrt(2d0*sqrt(mu/epsilon)*mesh%k**2)/2d0

      Pow = E**2/sqrt(mu/epsilon)/2d0/cc

      a = sparse_matmul(rotD, indD, a_in, nm)
      b = sparse_matmul(rotD, indD, b_in, nm)
      a90 = sparse_matmul(rotD90, indD90, a_in, nm)
      b90 = sparse_matmul(rotD90, indD90, b_in, nm)
      if (matrices%polarization == 1) then
         a90 = dcmplx(0d0)
         b90 = dcmplx(0d0)
      end if

      p = matmul(Taa, a) + matmul(Tab, b)
      q = matmul(Tbb, b) + matmul(Tba, a)
      p90 = matmul(Taa, a90) + matmul(Tab, b90)
      q90 = matmul(Tbb, b90) + matmul(Tba, a90)

      p = 2d0*p + a
      q = 2d0*q + b
      p90 = 2d0*p90+a90
      q90 = 2d0*q90+b90

! formula is for z-direction
      fz = F_z(Nmax, a, b, p, q) + F_z(Nmax, a90, b90, p90, q90)
      tz = T_z(Nmax, a, b, p, q) + T_z(Nmax, a90, b90, p90, q90)

! x-direction
      a2 = sparse_matmul(matrices%rotXs(1:las, i), matrices%indXs(1:las, :, i), a, nm)
      b2 = sparse_matmul(matrices%rotXs(1:las, i), matrices%indXs(1:las, :, i), b, nm)
      p2 = sparse_matmul(matrices%rotXs(1:las, i), matrices%indXs(1:las, :, i), p, nm)
      q2 = sparse_matmul(matrices%rotXs(1:las, i), matrices%indXs(1:las, :, i), q, nm)
      a290 = sparse_matmul(matrices%rotXs(1:las, i), matrices%indXs(1:las, :, i), a90, nm)
      b290 = sparse_matmul(matrices%rotXs(1:las, i), matrices%indXs(1:las, :, i), b90, nm)
      p290 = sparse_matmul(matrices%rotXs(1:las, i), matrices%indXs(1:las, :, i), p90, nm)
      q290 = sparse_matmul(matrices%rotXs(1:las, i), matrices%indXs(1:las, :, i), q90, nm)

      fx = F_z(Nmax, a2, b2, p2, q2) + F_z(Nmax, a290, b290, p290, q290)
      tx = T_z(Nmax, a2, b2, p2, q2) + T_z(Nmax, a290, b290, p290, q290)

! y-direction
      a2 = sparse_matmul(matrices%rotYs(1:las, i), matrices%indYs(1:las, :, i), a, nm)
      b2 = sparse_matmul(matrices%rotYs(1:las, i), matrices%indYs(1:las, :, i), b, nm)
      p2 = sparse_matmul(matrices%rotYs(1:las, i), matrices%indYs(1:las, :, i), p, nm)
      q2 = sparse_matmul(matrices%rotYs(1:las, i), matrices%indYs(1:las, :, i), q, nm)
      a290 = sparse_matmul(matrices%rotYs(1:las, i), matrices%indYs(1:las, :, i), a90, nm)
      b290 = sparse_matmul(matrices%rotYs(1:las, i), matrices%indYs(1:las, :, i), b90, nm)
      p290 = sparse_matmul(matrices%rotYs(1:las, i), matrices%indYs(1:las, :, i), p90, nm)
      q290 = sparse_matmul(matrices%rotYs(1:las, i), matrices%indYs(1:las, :, i), q90, nm)

      fy = F_z(Nmax, a2, b2, p2, q2) + F_z(Nmax, a290, b290, p290, q290)
      ty = T_z(Nmax, a2, b2, p2, q2) + T_z(Nmax, a290, b290, p290, q290)

! Averaging now, thus division by the number of polarization states
      matrices%force = dcmplx([fx, fy, fz]/cc/matrices%polarization)
      matrices%torque = dcmplx([tx, ty, tz]/(cc*mesh%k)/matrices%polarization)
      matrices%Q_t = dble(matrices%torque)*(mesh%k)/Pow/pi/mesh%a**2
      matrices%Q_f = dble(matrices%force)/Pow/pi/mesh%a**2

   end subroutine forcetorque

!****************************************************************************80
! Calculates z-component of force analytically
   function F_z(Nmax, a, bb, p, qq) result(f)
      real(dp) :: f, g
      complex(dp), dimension(:), allocatable, intent(in) :: a, bb, p, qq
      complex(dp), dimension(:), allocatable :: b, q
      integer :: Nmax, n, m, ind

      ind = 0
      f = 0.d0
      b = bb*dcmplx(0d0, 1d0)
      q = qq*dcmplx(0d0, 1d0)
      do n = 1, Nmax
         do m = -n, n
            ind = ind + 1
            g = (2d0*m/(n*(n + 1d0)))*dimag(dconjg(a(ind))*b(ind) - dconjg(p(ind))*q(ind))
            if (ind + 2*n + 2 <= Nmax*(Nmax + 2)) then
               g = g &
                   - (2d0/(n + 1d0))*sqrt((n*(n + 2d0)*(n - m + 1d0)*(n + m + 1d0))/((2d0*n + 1d0)*(2d0*n + 3d0))) &
                   *dimag(a(ind)*dconjg(a(ind + 2*n + 2)) + b(ind)*dconjg(b(ind + 2*n + 2)) - &
                          p(ind)*dconjg(p(ind + 2*n + 2)) - q(ind)*dconjg(q(ind + 2*n + 2)))
            end if
            f = f + g
         end do
      end do
   end function F_z

!****************************************************************************80
! Calculates the z-component of torque analytically
   function T_z(Nmax, a, b, p, q) result(t)
      real(dp) :: t
      complex(dp), dimension(:), allocatable :: a, b, p, q
      integer :: Nmax, n, m, ind

      ind = 0
      t = 0.d0
      do n = 1, Nmax
         do m = -n, n
            ind = ind + 1
            t = t + dble(m)*(cdabs(a(ind))**2 + cdabs(b(ind))**2 - &
                             cdabs(p(ind))**2 - cdabs(q(ind))**2)
         end do
      end do

   end function T_z

!****************************************************************************80
! Calculates the z-component of torque analytically
   function barnett_torque() result(N)
      real(dp) :: a
      complex(dp), dimension(3) :: N
      real(dp), dimension(3)    :: tmp, w, mu_Bar, B

! The approximate Barnett proportional constant X(0)*hbar/(g*mu_B)
      a = 10d0**(-14)
      w = matrices%w
      mu_Bar = a*mesh%V*w
      B = matrices%B

      tmp = crossRR(mu_Bar, B)

      N = dcmplx(tmp, 0d0)

   end function barnett_torque

!****************************************************************************80
! Calculates the z-component of torque analytically
   function DG_torque() result(N)
      real(dp) :: psi, xi, phi, Kw, V, tau, mag_B
      complex(dp), dimension(3) :: N
      real(dp), dimension(3)    :: a3, tmp, w, B, B_perp, proj_Bperp_a3, psi_vec

      mag_B = vlen(matrices%B)
      Kw = 10d0**(-13)

      a3 = matrices%P(:, 3)
      V = mesh%V
      w = matrices%w
      tau = matrices%Ip(3)/(Kw*V*mag_B**2)
      B = matrices%B/mag_B
      B_perp = crossRR([0d0, 1d0, 0d0], B)
      proj_Bperp_a3 = a3 - dot_product(a3, B_perp)*a3
      proj_Bperp_a3 = proj_Bperp_a3/vlen(proj_Bperp_a3)

      psi = dacos(dot_product(B, matrices%khat))
      xi = dacos(dot_product(B, a3))
      phi = dacos(dot_product(B_perp, proj_Bperp_a3))

      if (psi > pi/2) then
         psi = psi - pi/2
      end if
      if (proj_Bperp_a3(2) < 0) phi = phi + pi

      psi_vec = [dcos(phi)*dcos(xi)*dcos(phi) - dsin(psi)*dsin(xi), &
                 dcos(xi)*dsin(phi), -dsin(psi)*dcos(xi)*dcos(phi) - dcos(psi)*dsin(xi)]

      tmp = -(dsin(xi)*dcos(xi)*psi_vec + dsin(xi)*dsin(xi)*a3)*matrices%Ip(3)*vlen(w)/tau

      N = dcmplx(tmp, 0d0)

      if (mag_B < 1d-16) N = dcmplx(0d0)

   end function DG_torque

!****************************************************************************80
! The radiative alignment torque, from Weingartner & Draine (2003). Components are
! calculated using vector \hat{\xi} = \partial_\xi \hat{X_\psi}, where X_\psi is
! the position vector in terms of alignment directions \xi and \phi rotated amount
! \psi about the y-axis. Same is done in WD2003 for different axis notation.
   function F_align(Qt, xi, phi, psi) result(F)
      real(dp) :: Qt(3), xi, phi, psi, F

      F = Qt(1)*(cos(psi)*cos(xi)*cos(phi) - sin(psi)*sin(xi)) &
          + Qt(2)*cos(xi)*sin(phi) &
          - Qt(3)*(sin(psi)*cos(xi)*cos(phi) + cos(psi)*sin(xi))

   end function F_align

!****************************************************************************80
! The radiative spin-up torque, from Weingartner & Draine (2003)
   function H_align(Qt, xi, phi, psi) result(H)
      real(dp) :: Qt(3), xi, phi, psi, H

      H = Qt(3)*(cos(psi)*cos(xi) - sin(psi)*sin(xi)*cos(phi)) &
          + Qt(1)*(sin(psi)*cos(xi) + cos(psi)*sin(xi)*cos(phi)) &
          + Qt(2)*sin(xi)*cos(phi)

   end function H_align

!****************************************************************************80
! The radiative precession torque, from Weingartner & Draine (2003)
   function G_align(Qt, phi, psi) result(G)
      real(dp) :: Qt(3), phi, psi, G

      G = Qt(3)*sin(psi)*sin(phi) - Qt(1)*cos(psi)*sin(phi) &
          + Qt(2)*cos(phi)

   end function G_align

!****************************************************************************80
! Torque efficiency as a function of capital theta and phi (as in the works of
! Draine and Weingartner)
   function get_Qt(theta, phi, beta) result(Q)
      real(dp) :: R_thta(3, 3), nbeta(3), R_beta(3, 3), Q(3), theta, beta, phi, &
                  a_3(3), R_phi(3, 3)
      integer :: k

      Q = 0d0

      a_3 = matrices%P(1:3, 3)

      R_thta = R_theta(theta)
      R_phi = R_aa([0d0, 0d0, 1d0], phi)

! Rotation axis for beta averaging for current theta
      nbeta = matmul(matmul(R_phi, R_thta), a_3) ! Beta rotation about a_3
      nbeta = nbeta/vlen(nbeta) ! Ensure unit length of axis vector

      R_beta = R_aa(nbeta, beta)

! The ultimate rotation matrices for scattering event
      matrices%R = matmul(R_beta, R_thta) ! First a_3 to theta, then beta about a_3

      call rot_setup()

      if (matrices%whichbar == 0) then
         do k = 1, matrices%bars
            call forcetorque(k)
            Q = Q + matrices%Q_t/matrices%bars/matrices%polarization
         end do
      else
         k = matrices%whichbar
         call forcetorque(k)
         Q = Q + matrices%Q_t/matrices%polarization
      end if

   end function get_Qt

!****************************************************************************80
! Calculates orientation angles in terms of alignment angles xi, psi and phi
   function thetaphi(xi, psi, phi) result(tp)
      real(dp) :: xi, psi, phi, tp(2)

      tp(1) = dacos(cos(psi)*cos(xi) - sin(psi)*sin(xi)*cos(phi))
      tp(2) = 2d0*datan2(sin(tp(1)) - sin(psi)*cos(xi) - &
                         cos(psi)*sin(xi)*cos(phi), sin(xi)*sin(phi))

   end function thetaphi

end module forces
