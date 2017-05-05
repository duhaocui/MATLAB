% Test UKF vs PF

%% clear memory, screen, and close all figures
clear, clc, close all;

%% Process equation x[k] = sys(k, x[k-1], u[k]);
nx = 4;  % number of states
sys = @(k, xkm1, uk) [xkm1(1)/2+25*xkm1(1)/(1+xkm1(1)^2)+8*cos(1.2*k) + uk(1); 2*cos(k/10) + uk(2); 2*cos(xkm1(3)) + uk(3); xkm1(4)+0.1 + uk(4)]; % (returns column vector)

%% Observation equation y[k] = obs(k, x[k], v[k]);
ny = 4;                                           % number of observations
obs = @(k, xk, vk) [xk(1)+vk(1); xk(2)+vk(2); xk(3)+vk(3); xk(4)+vk(4)];                  % (returns column vector)

%% PDF of process noise and noise generator function
nu = 4;                                           % size of the vector of process noise
sigma_u = .1;
cov_u = sigma_u^2*eye(nu);
p_sys_noise   = @(u) mvnpdf(u, zeros(1, nu), cov_u);
gen_sys_noise = @(u) mvnrnd(zeros(1, nu), cov_u);         % sample from p_sys_noise (returns column vector)

%% PDF of observation noise and noise generator function
nv = 4;                                           % size of the vector of observation noise
sigma_v = 10;
cov_v = sigma_v^2*eye(nv);
p_obs_noise   = @(v) mvnpdf(v, zeros(1, nv), cov_v);
gen_obs_noise = @(v) mvnrnd(zeros(1, nv), cov_v);         % sample from p_obs_noise (returns column vector)

%% Initial PDF
% p_x0 = @(x) normpdf(x, 0,sqrt(10));             % initial pdf
gen_x0 = @(x) mvnrnd(zeros(1,nx), sqrt(10)*eye(nx));               % sample from p_x0 (returns column vector)

%% Transition prior PDF p(x[k] | x[k-1])
% (under the suposition of additive process noise)
% p_xk_given_xkm1 = @(k, xk, xkm1) p_sys_noise(xk - sys(k, xkm1, 0));

%% 
% (under the suposition of additive process noise)
p_yk_given_xk = @(k, yk, xk) p_obs_noise((yk - obs(k, xk, zeros(1, nv)))');

%% Number of time steps
T = 500;

%% Separate memory space
x = zeros(nx,T);  y = zeros(ny,T);
u = zeros(nu,T);  v = zeros(nv,T);

%% Simulate system
xh0 = [0; 0; 0; 0];                                  % initial state
u(:,1) = gen_sys_noise(sigma_u)';                               % initial process noise
v(:,1) = gen_obs_noise(sigma_v)';          % initial observation noise
x(:,1) = xh0;
y(:,1) = obs(1, xh0, v(:,1));
for k = 2:T
   % here we are basically sampling from p_xk_given_xkm1 and from p_yk_given_xk
   u(:,k) = gen_sys_noise();              % simulate process noise
   v(:,k) = gen_obs_noise();              % simulate observation noise
   x(:,k) = sys(k, x(:,k-1), u(:,k));     % simulate state
   y(:,k) = obs(k, x(:,k),   v(:,k));     % simulate observation
end

%% Separate memory
xh = zeros(nx, T); xh(:,1) = xh0;
xh_ukf = zeros(nx, T); xh_ukf(:,1) = xh0;
yh = zeros(ny, T); yh(:,1) = obs(1, xh0, zeros(1, nv));

pf.k               = 1;                   % initial iteration number
pf.Np              = 1000;                 % number of particles
%s.w               = zeros(s.Np, T);     % weights
pf.particles       = zeros(nx, pf.Np, T); % particles
pf.gen_x0          = gen_x0;              % function for sampling from initial pdf p_x0
pf.obs             = p_yk_given_xk;       % function of the observation likelihood PDF p(y[k] | x[k])
pf.sys_noise       = gen_sys_noise;       % function for generating system noise
%pf.p_x0 = p_x0;                          % initial prior PDF p(x[0])
%pf.p_xk_given_ xkm1 = p_xk_given_xkm1;   % transition prior PDF p(x[k] | x[k-1])
pf.xhk = xh0;
pf.sys = sys;
pf.resampling_strategy = 'systematic_resampling';
my_pf = ParticleFilter(pf);

kf.sys = @(k)(@(x)[x(1)/2+25*x(1)/(1+x(1)^2)+8*cos(1.2*k); 2*cos(k/10); 2*cos(x(3)); x(4)+0.1]);
kf.obs = @(x)[x(1);x(2);x(3);x(4)];
kf.Q = cov_u;
kf.R = cov_v;
kf.x = xh0;
kf.P = sqrt(10)*eye(nx);
ukf = UKalmanFilter(kf, 0.5, 0, 2);

%% Estimate state
for k = 2:T
   fprintf('Iteration = %d/%d\n',k,T);
   % state estimation
   my_pf.pf.k = k;
   my_pf.pf.z = y(:,k);
   my_pf.pf = my_pf.Iterate(my_pf.pf);
   
   ukf.s.sys = kf.sys(k);
   ukf.s.z = y(:,k);
   ukf.s = ukf.Iterate(ukf.s);
   xh(:,k) = my_pf.pf.xhk(:,k);
   xh_ukf(:,k) = ukf.s.x;
   % filtered observation
   yh(:,k) = obs(k, xh(:,k), zeros(1, nv));
   %hold on
   %plot(my_pf.pf.w, my_pf.pf.particles(1,:,k),'k.')
end

%% Compute RMSE
err = (xh - x).*(xh - x);
RMSE_pf = sqrt(sum(err,2)/T)

err = (xh_ukf - x).*(xh_ukf - x);
RMSE_ukf = sqrt(sum(err,2)/T)

%% Make plots of the evolution of the density
figure
hold on;
xi = 1:T;
yi = -25:0.25:25;
[xx,yy] = meshgrid(xi,yi);
den = zeros(size(xx));
xhmode = zeros(size(xh));

for i = xi
   % for each time step perform a kernel density estimation
   den(:,i) = ksdensity(my_pf.pf.particles(1,:,i), yi,'kernel','epanechnikov');
   [~, idx] = max(den(:,i));

   % estimate the mode of the density
   xhmode(i) = yi(idx);
   plot3(repmat(xi(i),length(yi),1), yi', den(:,i));
end
view(3);
box on;
title('Evolution of the state density','FontSize',14)

figure
mesh(xx,yy,den);   
title('Evolution of the state density','FontSize',14)

%% plot of the state vs estimated state by the particle filter vs particle paths
figure
hold on;
h1 = plot(1:T,squeeze(my_pf.pf.particles(2,:,:)),'y');
h2 = plot(1:T,x(1,:),'b','LineWidth',1);
h3 = plot(1:T,xh(1,:),'r','LineWidth',1);
h4 = plot(1:T,y(1,:),'g.','LineWidth',1);
legend([h2 h3 h1(1)],'state','mean of estimated state','particle paths');
title('State vs estimated state by the particle filter vs particle paths','FontSize',14);

%% plot of the observation vs filtered observation by the particle filter
figure
plot(1:T,y(1,:),'b', 1:T,yh(1,:),'r');
legend('observation','filtered observation');
title('Observation vs filtered observation by the particle filter','FontSize',14);

%% Plot results
figure
for k=1:4                                 % plot results
    subplot(4,1,k)
%     figure
%     hold on
    plot( 1:T, squeeze(my_pf.pf.particles(k,:,:)), 'y', 1:T, x(k,:), 'k--', 1:T, xh(k,:), 'b', 1:T, xh_ukf(k,:), 'g', 1:T, y(k,:), 'r.')
%     for i = 1:N
%         hold on
%         error_ellipse('C', blkdiag(PV_ukf{i}(1,1),1), 'mu', [i, xV_ukf(k,i)], 'style', 'r--')
%         hold on
%         error_ellipse('C', blkdiag(PV_ekf{i}(1,1),1), 'mu', [i, xV_ekf(k,i)], 'style', '--')
%     end
    str = sprintf('Patricle Filter Estimated State X(%d)',k);
    title(str)
    legend('Real', 'Particle paths', 'Estimated Mean', 'Meas');
end
return;