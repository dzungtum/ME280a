% Mesh generator, ME 280a HW 5
clear all

Nt = 3;                             % number of layers
No = 8;                             % number of elements in theta
Nc = 8;                             % number of elements in circum

if mod(No, 2) ~= 0
    disp('No must be even!')
end

num_nodes_per_elem = 4;             % linear elements

R = 1;                              % radius of each arch
r = 0.2;                            % radius of inner hole
t = 0.1;                            % thickness of the tube wall

layer_thickness = t / (Nt);         % thickness of each ring
angle = (2*pi) / Nc;                % angle in horizontal plane



% global node numbering begins on the inner surface, and moves clockwise
% until reaching the outer surface

% each row represents one coordinate of a global node
coordinates = zeros(Nt * Nc, 3);
Angle = pi / (No / 2);

k = 1; % index for coordinate row
x = 0;
y = 0;
z = 0;

Theta = 0;  % angle in each plane

% find the x-coordinates of the No + 1 slices
x_centers = zeros(1, No + 1);
x_centers(1) = x;

theta_inc = pi / (No / 2);
theta = theta_inc;

% in the first half of the tube
for i = 2:((No/2) + 1)
    x_centers(i) = x_centers(1) + (R + t + r) * (1 - cos(theta));
    theta = theta + theta_inc;
end

% in the second half of the tube
j = i + 1;
second_part_start = x_centers(i);
for l = 2:((No/2) + 1)
    x_centers(j) = second_part_start + x_centers(l);
    j = j + 1;
end



% create a vector of the y-coordinates
z_centers = zeros(1, No + 1);
z_centers(1) = z;
theta = theta_inc;

% in the first half of the tube
for i = 2:((No/2) + 1)
    z_centers(i) = (R + t + r) * sin(theta);
    theta = theta + theta_inc;
end

% in the second half of the tube
j = i + 1;
for l = 2:((No/2) + 1)
    z_centers(j) = - z_centers(l);
    j = j + 1;
end




% mesh in the theta direction
for l = 1:(No + 1)

    % for each plane
    theta = 0;
    dt = 0;

    % meshes in a plane perpendicular to tube axis
    for j = 1:(Nt + 1) % create all layers of rings
        for i = 1:Nc % create a single ring
            
            % x-coordinate
            coordinates(k, 1) = x_centers(l) + (r + dt) * cos(theta);
            
            % compute tilting parameters
            w = sin(pi/2 - Theta) * ((r + dt) * cos(theta)) / sin(pi/2);
            h = w * sin(Theta);
            p = w * cos(Theta);

            % y-coordinate
            coordinates(k, 2) = y + (r + dt) * sin(theta);

            % z-coordinate
            coordinates(k,3) = z_centers(l);
            
            % tilt for each half of the tube
            if l > No/2
                sn = -1;
            else
                sn = 1;
            end
            
            % tilt the z-coordinate for off-symmetric planes
            if find([1, 2, 8], i)
                coordinates(k,3) = coordinates(k,3) - sn*h;
            else
                coordinates(k,3) = coordinates(k,3) + sn*h;
            end
            
            % tilt the symmtric planes (the peaks)
            if (l == 3) || (l == 7)
                coordinates(k,3) = coordinates(k,3) - ((r + dt) * cos(theta));
                coordinates(k,1) = x_centers(l);
            end
            
            % tilt the x-coordinate
            %coordinates(k,1) = coordinates(k,1) + p;
            
            k = k + 1;
            theta = theta + angle;
        end
        dt = dt + layer_thickness; % reset radius
        theta = 0; % reset angle
    end
    
    % move the angle (along length) and centers for the next plane
    Theta = Theta + Angle;
    x = x + (R + t + r) * (1 - cos(Theta));
    y = y;
    z = z + (R + t + r) * sin(Theta);
end




X = coordinates(:,1);
Y = coordinates(:,2);
Z = coordinates(:,3);

scatter3(X,Y,Z)
xlim([-r - t, max(X)])
zlim([-max(Z), max(Z)])
xlabel('x')
ylabel('y')
zlabel('z')
