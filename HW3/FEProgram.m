clear all

% select which type of plot you want to make - at least one flag must equal 1
pe_plot_flag = 1;               % 1 - plot the potential energy as a function of N
e_plot_flag = 0;                % 1 - plot the energy norm as a function of N
N_plot_flag = 0;                % 1 - plot the solutions for various N

L = 1.0;                        % problem domain
k_freq = 12;                    % forcing frequency
left = 'Dirichlet';             % left boundary condition 
left_value = -0.3;              % left Dirichlet boundary condition value
right = 'Dirichlet';            % right boundary condition type
right_value = 0.7;              % right Dirichlet boundary condition value
tolerance = 0.04;               % convergence tolerance
energy_norm = tolerance + 1;    % arbitrary initialization value
fontsize = 16;                  % fontsize for plots
pcg_error_tol = 0.000001;       % error tolerance for PCG
precondition = 'precondition';  % 'nopreconditi' for no preconditioning

if (N_plot_flag)
     N_elem = [100, 1000, 10000];              % num_elem to cycle through for soln plots
elseif (pe_plot_flag || e_plot_flag)
     N_elem = [50:5:100, 200:100:1000, 2000:1000:10000];        % num_elem to cycle through for e_N vs. N
else
    disp('Either N_plot_flag or pe_plot_flag has to equal 1.');
end

Order = [2];              % shape function (orders - 1) to cycle thru

% specify E over the domain in a block structure
E_blocks = [2.5, 1.0, 1.75, 1.25, 2.75, 3.75, 2.25, 0.75, 2.0, 1.0];
space_blocks = 0.1:0.1:L;

for shape_order = Order
    clearvars permutation

% form the permutation matrix for assembling the global matrices
[permutation] = permutation(shape_order);    

% initialize vectors for collecting error
e = 1;
pe = ones(1, length(N_elem));
pe_2 = ones(1, length(N_elem));
pe_a = ones(1, length(N_elem));
pe_a2 = ones(1, length(N_elem));

for num_elem = N_elem

    parent_domain = -1:0.1:1;
    physical_domain = linspace(0, L, num_elem * length(parent_domain) - (num_elem - 1));    

    % define the quadrature rule
    [wt, qp] = quadrature(shape_order);
    
    % interpolate E into the physical domain
    [E_physical_domain] = PhysicalInterpolation(physical_domain, space_blocks, E_blocks);
 
    % --- ANALYTICAL SOLUTION --- %
    [solution_analytical, solution_analytical_derivative, gamma] = AnalyticalSolution(L, space_blocks, left_value, E_blocks, E_physical_domain, right_value, k_freq, physical_domain);
    
    % perform the meshing
    [num_nodes, num_nodes_per_element, LM, coordinates] = mesh(L, num_elem, shape_order);
    
    j = 1;
    k = 1;
    result = zeros(length(coordinates(:,1)), 1);
    for i = 1:length(physical_domain)
        if (abs(physical_domain(i) - coordinates(j)) < 1e-10)
            result(k) = solution_analytical(i);
            k = k + 1;
            j = j + 1;
        else
        end
    end
    
    % interpolate E into the an elemental basis
    [E_elem, right_endpoint_index, right_endpoint_coordinate] = ElementInterpolation(coordinates, num_elem, num_nodes_per_element, space_blocks, E_blocks);

    % specify the boundary conditions
    [dirichlet_nodes, neumann_nodes, a_k] = BCnodes(left, right, left_value, right_value, num_nodes);

    K_cell = cell([1, num_elem]);
    F_cell = cell([1, num_elem]);
    
    K = zeros(num_nodes, num_nodes);
    F = zeros(num_nodes, 1);
    
    for elem = 1:num_elem
        k = zeros(num_nodes_per_element);
        f = zeros(num_nodes_per_element, 1);
        
         for l = 1:length(qp)
             for i = 1:num_nodes_per_element
                 [N, dN, x_xe, dx_dxe] = shapefunctions(qp(l), shape_order, coordinates, LM, elem);
          
                 % assemble the (elemental) forcing vector
                 f(i) = f(i) - wt(l) * x_xe * (k_freq .^ 3) * cos(gamma * x_xe) * N(i) * dx_dxe;

                 for j = 1:num_nodes_per_element
                     % assemble the (elemental) stiffness matrix
                     k(i,j) = k(i,j) + wt(l) * E_elem(elem) * dN(i) * dN(j) / dx_dxe;
                 end
             end
         end
         
         % store elemental values into cells
         K_cell{1, elem} = k;
         F_cell{1, elem} = f;   
    end
    
% assemble into the global matrices
for elem = 1:num_elem
     m = 1;
     for m = 1:length(permutation(:,1))
        i = permutation(m,1);
        j = permutation(m,2);
        K(LM(elem, i), LM(elem, j)) = K_cell{1, elem}(i, j) + K(LM(elem, i), LM(elem, j));
     end
     
     for i = 1:length(f)
        F(LM(elem, i)) = F((LM(elem, i))) + F_cell{1,elem}(i);
     end 
end

K = sparse(K);

% perform static condensation to remove known Dirichlet nodes from solve
[K_uu, K_uk, F_u, F_k] = condensation(K, F, num_nodes, dirichlet_nodes);

% perform the solve using Gaussian elimination for comparison
a_u_condensed = K_uu \ (F_u - K_uk * dirichlet_nodes(2,:)');

% perform the solve using the global matrices
[a_u_condensed, pcg_error] = PCG(K_uu, F_u, K_uk, dirichlet_nodes, pcg_error_tol, precondition);

% perform the solve element-by-element
%[a_u_condensed] = PCG_element_by_element(F_u, K_uk, K_cell, LM, num_nodes, dirichlet_nodes, num_elem, num_nodes_per_element, pcg_error_tol, precondition);

% expand a_condensed to include the Dirichlet nodes
a = zeros(num_nodes, 1);

a_row = 1;
i = 1;      % index for dirichlet_nodes
j = 1;      % index for expanded row

for a_row = 1:num_nodes
    if (find(dirichlet_nodes(1, :) == a_row))
        a(a_row) = dirichlet_nodes(2,i);
        i = i + 1;
    else
        a(a_row) = a_u_condensed(j);
        j = j + 1;
    end
end

% assemble the solution in the physical domain
[solution_FE, solution_derivative_FE] = postprocess(num_elem, parent_domain, a, LM, num_nodes_per_element, shape_order, coordinates, physical_domain);

% compute the energy norm
energy_norm_bottom = sqrt(trapz(physical_domain, solution_analytical_derivative .* E_physical_domain .* solution_analytical_derivative));
energy_norm_top = sqrt(trapz(physical_domain, (solution_derivative_FE - solution_analytical_derivative) .* E_physical_domain .* (solution_derivative_FE - solution_analytical_derivative)));
energy_norm = energy_norm_top ./ energy_norm_bottom;

% compute the potential energy - FE
B_uNuN = trapz(physical_domain, solution_derivative_FE .* E_physical_domain .* solution_derivative_FE);
L_uN = - trapz(physical_domain, physical_domain .* k_freq .^3 .* cos(gamma .* physical_domain) .* solution_FE);
potential_energy = 0.5 .* B_uNuN - L_uN;

% compute the potential energy - analytic
B_uu = trapz(physical_domain, solution_analytical_derivative .* E_physical_domain .* solution_analytical_derivative);
L_u = - trapz(physical_domain, physical_domain .* k_freq .^3 .* cos(gamma .* physical_domain) .* solution_analytical);
pe_a = 0.5 .* B_uu - L_u;

if (N_plot_flag)
    plot(coordinates(:,1), a, '.')
    hold on
end

e_N(e) = energy_norm;
pe(e) = potential_energy;
pea(e) = pe_a;
e = e + 1;

end

if (N_plot_flag)
    txt = cell(length(N_elem),1);
    for i = 1:length(N_elem)
       txt{i}= sprintf('N = %i', N_elem(i));
    end
    h = legend(txt);
    set(h, 'FontSize', fontsize - 2);
    xlabel('Problem domain', 'FontSize', fontsize)
    ylabel(sprintf('Solution for order = %i', shape_order - 1), 'FontSize', fontsize)
    
    saveas(gcf, sprintf('Nplot', shape_order - 1), 'jpeg')
    close all
end

if (pe_plot_flag || e_plot_flag)
    if (pe_plot_flag)
        plot(N_elem, pe, '*-', N_elem, pea, '-')
        legend('FEM Solution','Analytic Solution')
        ylabel_str = 'Potential Energy';
        filename = 'pe_vs_N';
    else
        loglog(N_elem, e_N, '*-')
        ylabel_str = 'Energy Norm';
        filename = 'eN_vs_N';
    end
    
    xlabel('Number of Elements', 'FontSize', fontsize)
    ylabel(ylabel_str, 'FontSize', fontsize)
    saveas(gcf, filename, 'jpeg')
    close all
end

end

% --- analytical solution plot --- %
% plot(physical_domain, solution_analytical)
% xlabel('Physical Domain', 'FontSize', fontsize)
% ylabel('Solution u(x)', 'FontSize', fontsize)
% saveas(gcf, 'AnalyticalSoln2', 'jpeg')
% close all


% --- plot of error as a function of iteration --- %
% loglog(1:1:length(pcg_error), pcg_error)
% xlabel('Iteration Number', 'FontSize', fontsize)
% ylabel('PCG Error','FontSize', fontsize)
% close all


% --- plot of number of iterations as a function of N_elem --- %
% plot([100, 1000:1000:10000], [100, 1000:1000:10000], '*-')
% xlabel('Number of Elements', 'FontSize', fontsize)
% ylabel('PCG Iterations', 'FontSize', fontsize)
% saveas(gcf, 'PCGIterations', 'jpeg')
% close all


% --- plot pcg_error as a function of number of iterations --- %
% loglog(1:1:length(pcg_error), pcg_error)
% xlabel('Number of Iterations', 'FontSize', fontsize)
% ylabel('PCG Error', 'FontSize', fontsize)
% saveas(gcf, 'PCGerror', 'jpeg')
% close all