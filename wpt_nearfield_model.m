function results = wpt_nearfield_model(params)
% WPT_NEARFIELD_MODEL  Near-field inductive wireless power transfer link budget.
%
% Computes resonant inductive link efficiency vs. distance using Neumann's
% mutual inductance formula, Wheeler's flat spiral self-inductance formula,
% and a first-order skin-effect AC resistance model.
%
% NOTE: This model assumes the coils are operated at RESONANCE (tuned with
% external capacitors to cancel reactive impedance). Without resonant tuning,
% this efficiency calculation is inapplicable.
%
% REQUIRED INPUTS (params struct):
%   freq_Hz        - Operating frequency (Hz)
%   r_tx_m         - TX coil outer radius (m)
%   r_rx_m         - RX coil outer radius (m)
%   N_tx           - TX coil number of turns
%   N_rx           - RX coil number of turns
%   AWG_tx         - TX wire gauge (American Wire Gauge)
%   AWG_rx         - RX wire gauge (American Wire Gauge)
%   P_tx_dBm       - Transmit power (dBm)
%   d_vec          - Distance vector (m)
%
% OUTPUTS (results struct):
%   eta_inductive_pct - Efficiency vs distance (%)
%   P_rx_W            - Received power (Watts)
%   M                 - Mutual inductance (Henrys)
%   k_coil            - Coupling coefficient
%   U                 - Figure of merit
%   Q1, Q2            - Quality factors of TX and RX coils
%   L1, L2            - Self-inductances of TX and RX coils (Henrys)
%   R_ac1, R_ac2      - AC resistances of TX and RX coils (Ohms)
%   d_vec             - Distance vector (m)
%   freq_Hz           - Operating frequency (Hz)

    % ---- 1. Coil Geometry & Inductance ----
    d_wire_tx = awg_to_diameter(params.AWG_tx);
    d_wire_rx = awg_to_diameter(params.AWG_rx);
    
    r_wire_tx = d_wire_tx / 2;
    r_wire_rx = d_wire_rx / 2;
    
    % Compute inner radius assuming tightly wound flat spiral
    % Guard against physically impossible turns
    r_in_tx = max(params.r_tx_m - params.N_tx * d_wire_tx, 0.001 * params.r_tx_m);
    r_in_rx = max(params.r_rx_m - params.N_rx * d_wire_rx, 0.001 * params.r_rx_m);
    
    r_avg_tx = (params.r_tx_m + r_in_tx) / 2;
    r_avg_rx = (params.r_rx_m + r_in_rx) / 2;
    
    rho_tx = (params.r_tx_m - r_in_tx) / (params.r_tx_m + r_in_tx);
    rho_rx = (params.r_rx_m - r_in_rx) / (params.r_rx_m + r_in_rx);
    
    L1 = wheeler_spiral_inductance(r_avg_tx, params.N_tx, rho_tx);
    L2 = wheeler_spiral_inductance(r_avg_rx, params.N_rx, rho_rx);
    
    % Wire lengths (approximate Archimedean spiral length: 2*pi*N*r_avg)
    len_tx = 2 * pi * params.N_tx * r_avg_tx;
    len_rx = 2 * pi * params.N_rx * r_avg_rx;
    
    % ---- 2. AC Resistance (Skin Effect) ----
    rho_cu = 1.68e-8; % Copper resistivity at room temp (Ohm-m)
    R_ac1 = skin_effect_resistance(r_wire_tx, len_tx, params.freq_Hz, rho_cu);
    R_ac2 = skin_effect_resistance(r_wire_rx, len_rx, params.freq_Hz, rho_cu);
    
    % ---- 3. Quality Factors ----
    % Assumes coils are resonantly tuned
    omega = 2 * pi * params.freq_Hz;
    Q1 = (omega * L1) / R_ac1;
    Q2 = (omega * L2) / R_ac2;
    
    % ---- 4. Mutual Inductance & Coupling ----
    % Use average radius for the Neumann filament approximation
    M_single = neumann_mutual_inductance(r_avg_tx, r_avg_rx, params.d_vec);
    M = params.N_tx * params.N_rx * M_single;
    
    k_coil = M ./ sqrt(L1 * L2);
    
    % ---- 5. Efficiency & Received Power ----
    U = k_coil .* sqrt(Q1 * Q2);
    
    % Maximum power transfer efficiency (optimal load)
    eta_inductive = U.^2 ./ (1 + sqrt(1 + U.^2)).^2;
    eta_inductive_pct = eta_inductive * 100;
    
    P_tx_W = 10^((params.P_tx_dBm - 30) / 10);
    P_rx_W = P_tx_W .* eta_inductive;
    
    % ---- 6. Pack Results ----
    results.eta_inductive_pct = eta_inductive_pct;
    results.P_rx_W            = P_rx_W;
    results.M                 = M;
    results.k_coil            = k_coil;
    results.U                 = U;
    results.Q1                = Q1;
    results.Q2                = Q2;
    results.L1                = L1;
    results.L2                = L2;
    results.R_ac1             = R_ac1;
    results.R_ac2             = R_ac2;
    results.d_vec             = params.d_vec;
    results.freq_Hz           = params.freq_Hz;
end

% -------------------------------------------------------------------------
% Helper Functions
% -------------------------------------------------------------------------

function d_m = awg_to_diameter(awg)
    % Converts American Wire Gauge to diameter in meters
    d_mm = 0.127 * 92.^((36 - awg) / 39);
    d_m = d_mm / 1000;
end

function L = wheeler_spiral_inductance(r_avg, N, rho)
    % Wheeler's formula for planar spiral inductors (Mohan 1999)
    % Uses d_avg = 2 * r_avg
    mu0 = 4 * pi * 1e-7;
    d_avg = 2 * r_avg;
    c1 = 1.00; 
    c2 = 2.46;
    
    L = (mu0 * c1 * N^2 * d_avg) / (1 + c2 * rho);
end

function R_ac = skin_effect_resistance(r_wire, length_wire, freq_Hz, rho_cu)
    % First-order AC resistance due to skin effect.
    % LIMITATION: Ignores turn-to-turn proximity effect, which can
    % increase R_ac by 2-5x in tightly wound coils. For accurate
    % results at high turn counts, use FEM simulation (COMSOL/HFSS).
    mu0 = 4 * pi * 1e-7;
    delta = sqrt(rho_cu / (pi * freq_Hz * mu0));  % skin depth (m)
    
    if delta >= r_wire
        % At low frequencies, skin depth > wire radius: use DC resistance
        A_eff = pi * r_wire^2;
    else
        % Skin effect regime: current flows in annular ring of depth delta
        A_eff = pi * (r_wire^2 - (r_wire - delta)^2);
    end
    
    R_ac = rho_cu * length_wire / A_eff;
end

function M = neumann_mutual_inductance(r1, r2, d)
    % Computes mutual inductance between two coaxial circular loops
    % r1, r2: loop radii (m)
    % d: separation distance array (m)
    
    % Coupling parameter k^2
    k_sq = (4 * r1 * r2) ./ ((r1 + r2)^2 + d.^2);
    
    % GUARD: Clamp k^2 to prevent ellipke divergence at k -> 1 (d -> 0)
    k_sq = min(k_sq, 0.9999);
    
    k_param = sqrt(k_sq);
    [K_val, E_val] = ellipke(k_sq);
    
    mu0 = 4 * pi * 1e-7;
    M = mu0 * sqrt(r1 * r2) .* ((2./k_param - k_param) .* K_val - (2./k_param) .* E_val);
end
