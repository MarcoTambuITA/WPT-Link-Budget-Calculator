function results = wpt_farfield_model(params)
% WPT_FARFIELD_MODEL  Far-field radiative wireless power transfer link budget.
%
% Computes system efficiency vs. distance using the Close-In (CI) reference
% distance model with circular-aperture antenna gain, three-layer near-field
% masking, and configurable rectenna efficiency.
%
% REQUIRED INPUTS (params struct):
%   freq_Hz        - Operating frequency (Hz)
%   D_tx_m         - TX antenna diameter (m)
%   D_rx_m         - RX antenna diameter (m)
%   P_tx_dBm       - Transmit power (dBm)
%   n_path         - Path-loss exponent (2 = free space)
%   eff_rectenna   - Rectenna DC conversion efficiency, 0 to 1 (flat)
%   eta_ap         - Aperture efficiency (typically 0.5-0.7)
%   d_vec          - Distance vector (m)
%
% OPTIONAL INPUTS (backward-compatible, defaults are lossless):
%   polarization_factor    - Polarization mismatch, 0 to 1 (default: 1.0)
%   S11_tx_dB              - TX return loss in dB (default: -Inf = perfect)
%   S11_rx_dB              - RX return loss in dB (default: -Inf = perfect)
%   L_hardware_dB          - Hardware/insertion loss in dB (default: 0)
%   rectenna_curve         - Nx2 matrix [P_rx_dBm, eff], overrides all
%   use_heuristic_rectenna - If true, use HSMS-2850 sigmoid model
%
% OUTPUTS (results struct):
%   eff_system_pct, P_rx_dBm, near_field_boundary_m, fraunhofer_dist,
%   radiansphere_dist, aperture_capture_dist, G_tx_dBi, G_rx_dBi,
%   invalid_indices, d_vec, freq_MHz, D_tx_cm, D_rx_cm,
%   mismatch_tx_dB, mismatch_rx_dB, pol_loss_dB, P_rx_W, P_tx_W, P_dc_W

    % ---- 1. Constants & Wavelength ----
    c = 299792458;
    lambda = c / params.freq_Hz;

    % ---- 2. Optional Parameters (backward-compatible lossless defaults) ----
    if ~isfield(params, 'polarization_factor');    params.polarization_factor = 1.0;    end
    if ~isfield(params, 'S11_tx_dB');              params.S11_tx_dB = -Inf;              end
    if ~isfield(params, 'S11_rx_dB');              params.S11_rx_dB = -Inf;              end
    if ~isfield(params, 'L_hardware_dB');          params.L_hardware_dB = 0;             end
    if ~isfield(params, 'rectenna_curve');         params.rectenna_curve = [];           end
    if ~isfield(params, 'use_heuristic_rectenna'); params.use_heuristic_rectenna = false; end

    % ---- 3. Antenna Gain (Circular Aperture) ----
    % G = (pi^2 * eta_ap * D^2) / lambda^2
    % No minimum clamp — electrically small apertures correctly yield
    % sub-isotropic gain (negative dBi), producing near-zero efficiency.
    G_tx_linear = (pi^2 * params.eta_ap * params.D_tx_m^2) / lambda^2;
    G_rx_linear = (pi^2 * params.eta_ap * params.D_rx_m^2) / lambda^2;
    G_tx_dBi = 10 * log10(G_tx_linear);
    G_rx_dBi = 10 * log10(G_rx_linear);

    % ---- 4. Near-Field Boundaries (Three-Layer Mask) ----
    D_max = max(params.D_tx_m, params.D_rx_m);
    fraunhofer_dist = (2 * D_max^2) / lambda;
    radiansphere_dist = lambda / (2 * pi);
    Ae_rx = (lambda^2 * G_rx_linear) / (4 * pi);
    aperture_capture_dist = sqrt(Ae_rx / (4 * pi));
    near_field_boundary_m = max([fraunhofer_dist, radiansphere_dist, aperture_capture_dist]);

    % ---- 5. Impedance & Polarization Losses ----
    % S11 (dB) -> |Gamma|^2 = 10^(S11/10) -> mismatch_eff = 1 - |Gamma|^2
    % Guard: S11 is physically <= 0 dB (return loss convention).
    % Clamp to -0.01 dB to prevent log(negative) if user enters positive
    % values, and to avoid the degenerate S11=0 case (total reflection).
    S11_tx_clamped = min(params.S11_tx_dB, -0.01);
    S11_rx_clamped = min(params.S11_rx_dB, -0.01);
    gamma_sq_tx = 10^(S11_tx_clamped / 10);
    gamma_sq_rx = 10^(S11_rx_clamped / 10);
    mismatch_tx_dB = 10 * log10(1 - gamma_sq_tx);
    mismatch_rx_dB = 10 * log10(1 - gamma_sq_rx);
    pol_loss_dB = 10 * log10(max(params.polarization_factor, 1e-10));

    % ---- 6. Link Budget — Close-In (CI) Reference Distance Model ----
    % PL(d) = FSPL(d0) + 10*n*log10(d/d0) + L_hardware
    % where d0 = near_field_boundary_m (the NF/FF transition point).
    %
    % This eliminates the "free energy" bug: when n > 2, log10(d/d0) >= 0
    % for all valid far-field points (d >= d0), guaranteeing realistic
    % efficiency is always <= ideal efficiency.
    %
    % When n=2 and L_hardware=0, this is mathematically identical to
    % standard FSPL: FSPL(d0) + 20*log10(d/d0) = FSPL(d).
    d0 = near_field_boundary_m;
    FSPL_d0 = 20 * log10(4 * pi * d0 / lambda);
    path_loss_dB = FSPL_d0 ...
                   + 10 * params.n_path * log10(params.d_vec / d0) ...
                   + params.L_hardware_dB;

    % Received power including all loss terms
    P_rx_dBm = params.P_tx_dBm + G_tx_dBi + G_rx_dBi - path_loss_dB ...
               + mismatch_tx_dB + mismatch_rx_dB + pol_loss_dB;

    % ---- 7. Rectenna Efficiency (three-tier priority) ----
    P_rx_W = 10.^((P_rx_dBm - 30) ./ 10);

    if ~isempty(params.rectenna_curve)
        % PRIORITY 1: CSV ground truth (user's LTspice data)
        sorted_curve = sortrows(params.rectenna_curve, 1);
        eff_rect = interp1(sorted_curve(:,1), sorted_curve(:,2), ...
                           P_rx_dBm, 'linear', 0);
        % Clamp above max P_rx to peak efficiency (flatline)
        max_prx = sorted_curve(end, 1);
        max_eff = sorted_curve(end, 2);
        eff_rect(P_rx_dBm > max_prx) = max_eff;
        eff_rect = max(eff_rect, 0);

    elseif params.use_heuristic_rectenna
        % PRIORITY 2: HSMS-2850 sigmoid heuristic
        h = wpt_heuristics(params.freq_Hz);
        eff_rect = h.eta_peak ./ (1 + exp(-(P_rx_dBm - h.P_thresh) / h.P_slope));
        eff_rect = max(eff_rect, 0);

    else
        % PRIORITY 3: Flat efficiency (Phase 1 backward compatibility)
        eff_rect = params.eff_rectenna;
    end

    P_dc_W = P_rx_W .* eff_rect;

    % System efficiency = P_dc / P_tx
    P_tx_W = 10^((params.P_tx_dBm - 30) / 10);
    eff_system_pct = (P_dc_W ./ P_tx_W) .* 100;

    % ---- 8. Physics Mask ----
    invalid_indices = params.d_vec < near_field_boundary_m;
    eff_system_pct(invalid_indices) = NaN;
    P_rx_dBm(invalid_indices) = NaN;

    % ---- 9. Pack Results ----
    results.eff_system_pct        = eff_system_pct;
    results.P_rx_dBm              = P_rx_dBm;
    results.near_field_boundary_m = near_field_boundary_m;
    results.fraunhofer_dist       = fraunhofer_dist;
    results.radiansphere_dist     = radiansphere_dist;
    results.aperture_capture_dist = aperture_capture_dist;
    results.G_tx_dBi              = G_tx_dBi;
    results.G_rx_dBi              = G_rx_dBi;
    results.invalid_indices       = invalid_indices;
    results.d_vec                 = params.d_vec;
    results.freq_MHz              = params.freq_Hz / 1e6;
    results.D_tx_cm               = params.D_tx_m * 100;
    results.D_rx_cm               = params.D_rx_m * 100;
    results.mismatch_tx_dB        = mismatch_tx_dB;
    results.mismatch_rx_dB        = mismatch_rx_dB;
    results.pol_loss_dB           = pol_loss_dB;
    results.P_rx_W                = P_rx_W;
    results.P_tx_W                = P_tx_W;
    results.P_dc_W                = P_dc_W;
end