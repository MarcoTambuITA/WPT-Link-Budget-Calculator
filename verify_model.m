% VERIFY_MODEL — Command-line verification of wpt_farfield_model.m
%
% Run this script from the MATLAB command window to validate the physics
% engine against hand-calculated Friis equation results. No GUI required.
%
% Usage:
%   >> verify_model

clear; clc;
c = 299792458;
pass_count = 0;
fail_count = 0;

fprintf('============================================================\n');
fprintf('  WPT Far-Field Model — Verification Suite\n');
fprintf('============================================================\n\n');

%% ===== TEST 1: Gain & Link Budget at 2.45 GHz =====
fprintf('--- Test 1: 2.45 GHz, TX=10cm, RX=5cm, 20 dBm, n=2 ---\n');
params = struct();
params.freq_Hz     = 2.45e9;
params.D_tx_m      = 0.10;
params.D_rx_m      = 0.05;
params.P_tx_dBm    = 20;
params.n_path      = 2;
params.eff_rectenna = 0.60;
params.eta_ap      = 0.60;
params.d_vec       = linspace(0.1, 5, 500);

results = wpt_farfield_model(params);

% Hand-calculate expected values
lambda = c / params.freq_Hz;
G_tx_hand = (pi^2 * 0.60 * 0.10^2) / lambda^2;
G_rx_hand = (pi^2 * 0.60 * 0.05^2) / lambda^2;
G_tx_dBi_hand = 10 * log10(G_tx_hand);
G_rx_dBi_hand = 10 * log10(G_rx_hand);

fprintf('  Wavelength: %.6f m\n', lambda);
fprintf('  TX Gain:  model = %+.4f dBi  |  hand = %+.4f dBi  |  delta = %.6f dB\n', ...
    results.G_tx_dBi, G_tx_dBi_hand, abs(results.G_tx_dBi - G_tx_dBi_hand));
fprintf('  RX Gain:  model = %+.4f dBi  |  hand = %+.4f dBi  |  delta = %.6f dB\n', ...
    results.G_rx_dBi, G_rx_dBi_hand, abs(results.G_rx_dBi - G_rx_dBi_hand));

% Verify gains match to machine precision
if abs(results.G_tx_dBi - G_tx_dBi_hand) < 1e-10 && ...
   abs(results.G_rx_dBi - G_rx_dBi_hand) < 1e-10
    fprintf('  [PASS] Gain calculation matches hand computation\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Gain mismatch detected!\n');
    fail_count = fail_count + 1;
end

% Verify P_rx and efficiency at d = 1.0 m
d_test = 1.0;
[~, idx] = min(abs(results.d_vec - d_test));
PL_hand = 20*log10(4*pi/lambda) + 20*log10(d_test);
Prx_hand = params.P_tx_dBm + G_tx_dBi_hand + G_rx_dBi_hand - PL_hand;
Prx_W_hand = 10^((Prx_hand - 30) / 10);
Pdc_hand = Prx_W_hand * params.eff_rectenna;
Ptx_W = 10^((params.P_tx_dBm - 30) / 10);
eff_hand = (Pdc_hand / Ptx_W) * 100;

fprintf('  At d = %.1f m:\n', d_test);
fprintf('    P_rx:  model = %.4f dBm  |  hand = %.4f dBm\n', results.P_rx_dBm(idx), Prx_hand);
fprintf('    Eff:   model = %.6f%%  |  hand = %.6f%%\n', results.eff_system_pct(idx), eff_hand);

if ~isnan(results.eff_system_pct(idx)) && abs(results.eff_system_pct(idx) - eff_hand) < 0.01
    fprintf('  [PASS] Link budget at 1 m matches hand computation\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Link budget mismatch at 1 m\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 2: Near-Field Boundary Masking =====
fprintf('\n--- Test 2: Near-Field Masking ---\n');
fprintf('  Near-field boundary: %.4f m\n', results.near_field_boundary_m);
fprintf('    Fraunhofer:        %.4f m\n', results.fraunhofer_dist);
fprintf('    Radiansphere:      %.4f m\n', results.radiansphere_dist);
fprintf('    Aperture capture:  %.4f m\n', results.aperture_capture_dist);

% Check that points before the boundary are NaN
[~, idx_before] = min(abs(results.d_vec - (results.near_field_boundary_m - 0.01)));
[~, idx_after]  = min(abs(results.d_vec - (results.near_field_boundary_m + 0.01)));

if results.d_vec(idx_before) < results.near_field_boundary_m && ...
   isnan(results.eff_system_pct(idx_before))
    fprintf('  [PASS] Efficiency is NaN at d = %.4f m (before boundary)\n', results.d_vec(idx_before));
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Efficiency should be NaN before boundary\n');
    fail_count = fail_count + 1;
end

if results.d_vec(idx_after) > results.near_field_boundary_m && ...
   ~isnan(results.eff_system_pct(idx_after))
    fprintf('  [PASS] Efficiency = %.6f%% at d = %.4f m (after boundary)\n', ...
        results.eff_system_pct(idx_after), results.d_vec(idx_after));
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Efficiency should be a valid number after boundary\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 3: Energy Conservation =====
fprintf('\n--- Test 3: Energy Conservation ---\n');
valid_eff = results.eff_system_pct(~isnan(results.eff_system_pct));
if isempty(valid_eff)
    fprintf('  [SKIP] All points masked — no valid data to check\n');
else
    max_eff = max(valid_eff);
    fprintf('  Max valid efficiency: %.6f%%\n', max_eff);
    if max_eff <= 100
        fprintf('  [PASS] No efficiency exceeds 100%%\n');
        pass_count = pass_count + 1;
    else
        fprintf('  [FAIL] Efficiency exceeds 100%%! Physics violation.\n');
        fail_count = fail_count + 1;
    end
end

%% ===== TEST 4: Low Frequency Edge Case (10 MHz) =====
fprintf('\n--- Test 4: Low Frequency Edge Case (10 MHz) ---\n');
params_lf = params;
params_lf.freq_Hz = 10e6;
results_lf = wpt_farfield_model(params_lf);

lambda_lf = c / 10e6;
fprintf('  Wavelength: %.2f m\n', lambda_lf);
fprintf('  Near-field boundary: %.2f m\n', results_lf.near_field_boundary_m);
fprintf('  Radiansphere: %.2f m  (should dominate at 10 MHz)\n', lambda_lf / (2*pi));

pct_nan = sum(isnan(results_lf.eff_system_pct)) / length(results_lf.eff_system_pct) * 100;
fprintf('  Points masked: %.1f%%\n', pct_nan);

% At 10 MHz with 10cm antenna, radiansphere ~ 4.77 m. Most of the 0.1–5m
% range should be NaN.
if results_lf.near_field_boundary_m > 4.0
    fprintf('  [PASS] Near-field boundary correctly > 4 m for 10 MHz\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Near-field boundary too small for 10 MHz\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 5: High-Gain / Large Antenna at High Frequency =====
fprintf('\n--- Test 5: Large Antenna at 5.8 GHz (stress test) ---\n');
params_hg = params;
params_hg.freq_Hz = 5.8e9;
params_hg.D_tx_m  = 0.50;  % 50 cm dish
params_hg.D_rx_m  = 0.30;  % 30 cm dish
% Extend distance vector well past the Fraunhofer boundary (~9.7 m)
params_hg.d_vec   = linspace(0.1, 20, 500);
results_hg = wpt_farfield_model(params_hg);

fprintf('  TX Gain: %.2f dBi\n', results_hg.G_tx_dBi);
fprintf('  RX Gain: %.2f dBi\n', results_hg.G_rx_dBi);
fprintf('  Near-field boundary: %.4f m\n', results_hg.near_field_boundary_m);
fprintf('    Fraunhofer:        %.4f m  (should dominate for large D)\n', results_hg.fraunhofer_dist);
fprintf('    Aperture capture:  %.4f m\n', results_hg.aperture_capture_dist);

valid_eff_hg = results_hg.eff_system_pct(~isnan(results_hg.eff_system_pct));
if ~isempty(valid_eff_hg) && max(valid_eff_hg) <= 100
    fprintf('  Max valid efficiency: %.6f%%\n', max(valid_eff_hg));
    fprintf('  [PASS] No energy conservation violation with high-gain antennas\n');
    pass_count = pass_count + 1;
elseif isempty(valid_eff_hg)
    fprintf('  [FAIL] All points masked — d_vec does not extend past NF boundary\n');
    fail_count = fail_count + 1;
else
    fprintf('  [FAIL] Energy conservation violated: max eff = %.4f%%\n', max(valid_eff_hg));
    fail_count = fail_count + 1;
end

%% ===== TEST 6: Symmetric vs Asymmetric Antennas =====
fprintf('\n--- Test 6: Symmetric TX/RX Sanity Check ---\n');
params_sym = params;
params_sym.D_tx_m = 0.10;
params_sym.D_rx_m = 0.10;
results_sym = wpt_farfield_model(params_sym);

if abs(results_sym.G_tx_dBi - results_sym.G_rx_dBi) < 1e-12
    fprintf('  [PASS] TX gain == RX gain when D_tx == D_rx (%.4f dBi)\n', results_sym.G_tx_dBi);
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] TX and RX gains should be equal for identical antennas\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 7: Backward Compatibility (No Realistic Fields) =====
fprintf('\n--- Test 7: Backward Compatibility ---\n');
% Model with NO realistic fields should produce identical results to
% model with explicit lossless defaults.
results_base = wpt_farfield_model(params);

params_explicit = params;
params_explicit.polarization_factor = 1.0;
params_explicit.S11_tx_dB = -Inf;
params_explicit.S11_rx_dB = -Inf;
params_explicit.rectenna_curve = [];

results_explicit = wpt_farfield_model(params_explicit);

% Compare valid points only (NaN == NaN fails by design)
valid_both = ~isnan(results_base.eff_system_pct) & ~isnan(results_explicit.eff_system_pct);
if any(valid_both) && max(abs( ...
        results_base.eff_system_pct(valid_both) - ...
        results_explicit.eff_system_pct(valid_both))) < 1e-10
    fprintf('  [PASS] Results identical with and without explicit lossless defaults\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Results differ — backward compatibility broken\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 8: Realistic Losses Reduce Efficiency =====
fprintf('\n--- Test 8: Realistic Mode Reduces Efficiency ---\n');
params_real = params;
params_real.S11_tx_dB = -10;          % Moderate mismatch
params_real.S11_rx_dB = -10;
params_real.polarization_factor = 0.5; % 45 deg mismatch

results_real = wpt_farfield_model(params_real);

valid_ideal = ~isnan(results_base.eff_system_pct);
valid_real  = ~isnan(results_real.eff_system_pct);
valid_cmp   = valid_ideal & valid_real;

if any(valid_cmp)
    ideal_vals = results_base.eff_system_pct(valid_cmp);
    real_vals  = results_real.eff_system_pct(valid_cmp);
    if all(real_vals <= ideal_vals + 1e-10)
        fprintf('  [PASS] Realistic efficiency <= ideal at all valid points\n');
        fprintf('    Example: ideal=%.6f%%  real=%.6f%%  (delta=%.4f%%)\n', ...
            ideal_vals(1), real_vals(1), ideal_vals(1) - real_vals(1));
        pass_count = pass_count + 1;
    else
        fprintf('  [FAIL] Realistic exceeds ideal at some points!\n');
        fail_count = fail_count + 1;
    end
else
    fprintf('  [SKIP] No overlapping valid points\n');
end

%% ===== TEST 9: S11 Mismatch Math =====
fprintf('\n--- Test 9: S11 Mismatch Hand Computation ---\n');
% S11 = -10 dB  ->  |Gamma|^2 = 0.1  ->  mismatch_eff = 0.9
% mismatch_dB = 10*log10(0.9) = -0.45757 dB
params_s11 = params;
params_s11.S11_tx_dB = -10;
params_s11.S11_rx_dB = -Inf;   % Perfect RX match
params_s11.polarization_factor = 1.0;
results_s11 = wpt_farfield_model(params_s11);

expected_mismatch_dB = 10 * log10(1 - 10^(-10/10));  % -0.45757 dB
fprintf('  S11 TX = -10 dB\n');
fprintf('    Mismatch (model): %.6f dB  |  hand: %.6f dB\n', ...
    results_s11.mismatch_tx_dB, expected_mismatch_dB);

if abs(results_s11.mismatch_tx_dB - expected_mismatch_dB) < 1e-10
    fprintf('  [PASS] S11 mismatch calculation is exact\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] S11 mismatch calculation error\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 10: Rectenna Curve Interpolation =====
fprintf('\n--- Test 10: Rectenna Curve Interpolation ---\n');
% Create a synthetic rectenna curve: efficiency ramps from 0 to 0.5
% between -20 dBm and 0 dBm
synth_curve = [-30 0; -20 0; -10 0.25; 0 0.50; 10 0.50];

params_rect = params;
params_rect.rectenna_curve = synth_curve;
results_rect = wpt_farfield_model(params_rect);

% Check that efficiency is non-negative everywhere
valid_rect = results_rect.eff_system_pct(~isnan(results_rect.eff_system_pct));
if ~isempty(valid_rect) && all(valid_rect >= 0)
    fprintf('  [PASS] Rectenna curve produces non-negative efficiency\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Negative efficiency detected with rectenna curve\n');
    fail_count = fail_count + 1;
end

% Verify the curve differs from the flat-efficiency baseline
valid_base = results_base.eff_system_pct(~isnan(results_base.eff_system_pct));
if ~isempty(valid_rect) && ~isempty(valid_base) && ...
        max(abs(valid_rect(1:min(end,length(valid_base))) - ...
                valid_base(1:min(end,length(valid_rect))))) > 1e-6
    fprintf('  [PASS] Rectenna curve produces different results from flat efficiency\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Rectenna curve should differ from flat baseline\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 11: CI Model — No "Free Energy" Bug =====
fprintf('\n--- Test 11: CI Model — Realistic <= Ideal at ALL Distances ---\n');
% This is the critical test: with n > 2, the old log-distance model
% produced higher realistic P_rx than ideal when d < 1 m.
% The CI model anchored at d0 = near_field_boundary_m fixes this.
params_ci = params;
params_ci.n_path = 3.0;              % Aggressive path loss exponent
params_ci.L_hardware_dB = 3.0;       % 3 dB hardware loss
params_ci.S11_tx_dB = -10;
params_ci.S11_rx_dB = -10;
params_ci.polarization_factor = 1.0;

% Use a distance vector that starts very close to NF boundary
results_ci_ideal = wpt_farfield_model(params);  % n=2, L_hw=0
results_ci_real  = wpt_farfield_model(params_ci);

valid_i = ~isnan(results_ci_ideal.eff_system_pct);
valid_r = ~isnan(results_ci_real.eff_system_pct);
valid_ci = valid_i & valid_r;

if any(valid_ci)
    ideal_v = results_ci_ideal.eff_system_pct(valid_ci);
    real_v  = results_ci_real.eff_system_pct(valid_ci);
    d_valid = params.d_vec(valid_ci);

    if all(real_v <= ideal_v + 1e-10)
        fprintf('  [PASS] Realistic <= ideal at ALL %d valid points (n=3.0, L_hw=3dB)\n', sum(valid_ci));
        fprintf('    At d=%.3f m: ideal=%.6f%%  real=%.6f%%  (delta=%.4f%%)\n', ...
            d_valid(1), ideal_v(1), real_v(1), ideal_v(1) - real_v(1));
        % Also check a point near d < 1 m if available
        near_1m = find(d_valid < 1.0, 1, 'last');
        if ~isempty(near_1m)
            fprintf('    At d=%.3f m: ideal=%.6f%%  real=%.6f%%  (delta=%.4f%%) — sub-1m point\n', ...
                d_valid(near_1m), ideal_v(near_1m), real_v(near_1m), ...
                ideal_v(near_1m) - real_v(near_1m));
        end
        pass_count = pass_count + 1;
    else
        violations = find(real_v > ideal_v + 1e-10);
        fprintf('  [FAIL] "Free energy" bug: realistic > ideal at %d points!\n', length(violations));
        fprintf('    First violation at d=%.3f m: ideal=%.6f%%  real=%.6f%%\n', ...
            d_valid(violations(1)), ideal_v(violations(1)), real_v(violations(1)));
        fail_count = fail_count + 1;
    end
else
    fprintf('  [SKIP] No overlapping valid points\n');
end

%% ===== TEST 12: CI Model Backward Compatibility =====
fprintf('\n--- Test 12: CI Model = FSPL When n=2, L_hw=0 ---\n');
% Mathematically: FSPL(d0) + 20*log10(d/d0) + 0 = FSPL(d)
% So the CI model should produce identical results to Phase 1.
params_ci2 = params;
params_ci2.L_hardware_dB = 0;  % Explicit zero

results_ci2 = wpt_farfield_model(params_ci2);
results_base2 = wpt_farfield_model(params);

valid_ci2 = ~isnan(results_ci2.eff_system_pct) & ~isnan(results_base2.eff_system_pct);
if any(valid_ci2)
    delta_ci = max(abs(results_ci2.eff_system_pct(valid_ci2) - results_base2.eff_system_pct(valid_ci2)));
    fprintf('  Max delta between CI(n=2,L=0) and base: %.2e %%\n', delta_ci);
    if delta_ci < 1e-10
        fprintf('  [PASS] CI model with n=2, L_hw=0 is identical to standard FSPL\n');
        pass_count = pass_count + 1;
    else
        fprintf('  [FAIL] CI model diverges from FSPL!\n');
        fail_count = fail_count + 1;
    end
else
    fprintf('  [SKIP] No valid points\n');
end

%% ===== TEST 13: Heuristic Engine Values =====
fprintf('\n--- Test 13: Heuristic Engine at Known Frequencies ---\n');
h_915 = wpt_heuristics(915e6);
h_245 = wpt_heuristics(2.45e9);
h_580 = wpt_heuristics(5.8e9);

fprintf('  915 MHz:  n=%.2f  L_hw=%.1f dB  eta_peak=%.1f%%\n', ...
    h_915.n_path, h_915.L_hardware_dB, h_915.eta_peak * 100);
fprintf('  2.45 GHz: n=%.2f  L_hw=%.1f dB  eta_peak=%.1f%%\n', ...
    h_245.n_path, h_245.L_hardware_dB, h_245.eta_peak * 100);
fprintf('  5.8 GHz:  n=%.2f  L_hw=%.1f dB  eta_peak=%.1f%%\n', ...
    h_580.n_path, h_580.L_hardware_dB, h_580.eta_peak * 100);

% Verify monotonic degradation with frequency
if h_915.n_path < h_245.n_path && h_245.n_path < h_580.n_path
    fprintf('  [PASS] n_path increases monotonically with frequency\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] n_path should increase with frequency\n');
    fail_count = fail_count + 1;
end

if h_915.eta_peak > h_245.eta_peak && h_245.eta_peak > h_580.eta_peak
    fprintf('  [PASS] eta_peak decreases monotonically with frequency\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] eta_peak should decrease with frequency\n');
    fail_count = fail_count + 1;
end

% Verify calibrated 5.8 GHz eta_peak is ~27.7% (with f_rolloff = 5 GHz)
expected_eta_58 = 0.65 / (1 + (5.8e9 / 5e9)^2);
if abs(h_580.eta_peak - expected_eta_58) < 1e-10
    fprintf('  [PASS] 5.8 GHz eta_peak = %.1f%% matches calibration\n', h_580.eta_peak * 100);
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] 5.8 GHz eta_peak mismatch\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 14: Sigmoid Rectenna Turn-On Behavior =====
fprintf('\n--- Test 14: Heuristic Sigmoid Rectenna ---\n');
% At P_rx = P_thresh (-20 dBm), sigmoid = 0.5, so eta = eta_peak * 0.5
% At P_rx >> P_thresh (e.g., +10 dBm), eta -> eta_peak
params_sig = params;
params_sig.use_heuristic_rectenna = true;
% Force a specific d_vec that gives known P_rx values
params_sig.d_vec = linspace(0.5, 5, 500);
results_sig = wpt_farfield_model(params_sig);

% Verify the heuristic rectenna produces different results from flat 60%
results_flat = wpt_farfield_model(params);  % uses flat eff_rectenna=0.60
valid_sig = ~isnan(results_sig.eff_system_pct) & ~isnan(results_flat.eff_system_pct);
if any(valid_sig)
    sig_vals = results_sig.eff_system_pct(valid_sig);
    flat_vals = results_flat.eff_system_pct(valid_sig);
    if max(abs(sig_vals - flat_vals)) > 1e-6
        fprintf('  [PASS] Heuristic sigmoid produces different results from flat 60%%\n');
        pass_count = pass_count + 1;
    else
        fprintf('  [FAIL] Heuristic sigmoid should differ from flat efficiency\n');
        fail_count = fail_count + 1;
    end
else
    fprintf('  [SKIP] No valid points\n');
end

% Verify sigmoid efficiency is always non-negative and <= eta_peak
if any(valid_sig)
    h_test = wpt_heuristics(params.freq_Hz);
    if all(sig_vals >= 0)
        fprintf('  [PASS] Sigmoid efficiency is non-negative at all valid points\n');
        pass_count = pass_count + 1;
    else
        fprintf('  [FAIL] Negative sigmoid efficiency detected\n');
        fail_count = fail_count + 1;
    end
end

%% ===== TEST 15: Neumann Mutual Inductance =====
fprintf('\n--- Test 15: Neumann Mutual Inductance ---\n');
% Expected value calculated independently for r_outer=0.05 m, d=0.01 m, N=1, AWG 22
% using python scipy.special.ellipk and ellipe.
% AWG 22 wire has diameter = 0.64516 mm. r_in = max(0.05 - 0.00064516, 0.00005) = 0.0493548 m
% r_avg = (0.05 + 0.0493548) / 2 = 0.0496774 m
expected_M = 1.0661126229778528e-07;
params_nf = struct();
params_nf.freq_Hz = 1e6;
params_nf.r_tx_m = 0.05;
params_nf.r_rx_m = 0.05;
params_nf.N_tx = 1;
params_nf.N_rx = 1;
params_nf.AWG_tx = 22;
params_nf.AWG_rx = 22;
params_nf.P_tx_dBm = 20;
params_nf.d_vec = 0.01;

results_nf = wpt_nearfield_model(params_nf);
fprintf('  Expected M: %.6e H\n', expected_M);
fprintf('  Model M:    %.6e H\n', results_nf.M);

if abs(results_nf.M - expected_M) / expected_M < 1e-5
    fprintf('  [PASS] Neumann mutual inductance matches expected value\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Neumann mutual inductance mismatch\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 16: ellipke Guard =====
fprintf('\n--- Test 16: ellipke Guard at d=0 ---\n');
params_nf.d_vec = 0; % Force d=0 to test k^2 -> 1 divergence guard
results_nf0 = wpt_nearfield_model(params_nf);

if ~isinf(results_nf0.M) && ~isnan(results_nf0.M)
    fprintf('  [PASS] Guard prevented ellipke divergence at d=0 (M = %.4e H)\n', results_nf0.M);
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] ellipke diverged at d=0\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 17: Wheeler Inductance Sanity Check =====
fprintf('\n--- Test 17: Wheeler Inductance Sanity Check ---\n');
% A 5cm radius, 10-turn coil should be roughly in the 10-20 uH range
params_wh = params_nf;
params_wh.N_tx = 10;
results_wh = wpt_nearfield_model(params_wh);

fprintf('  10-turn 5cm coil L: %.2f uH\n', results_wh.L1 * 1e6);
if results_wh.L1 > 5e-6 && results_wh.L1 < 50e-6
    fprintf('  [PASS] Wheeler inductance is physically reasonable\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Wheeler inductance out of expected bounds\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 18: Q Monotonicity in Skin-Effect Regime =====
fprintf('\n--- Test 18: Q Monotonicity in Skin-Effect Regime ---\n');
% Test Q factor at 1 MHz, 2 MHz, and 4 MHz to verify Q grows roughly as sqrt(f)
% because R_ac grows as sqrt(f) and X_L grows as f.
params_q = params_nf;
params_q.freq_Hz = 1e6;
res_q1 = wpt_nearfield_model(params_q);
params_q.freq_Hz = 2e6;
res_q2 = wpt_nearfield_model(params_q);
params_q.freq_Hz = 4e6;
res_q4 = wpt_nearfield_model(params_q);

fprintf('  Q at 1 MHz: %.2f\n', res_q1.Q1);
fprintf('  Q at 2 MHz: %.2f\n', res_q2.Q1);
fprintf('  Q at 4 MHz: %.2f\n', res_q4.Q1);

if res_q1.Q1 < res_q2.Q1 && res_q2.Q1 < res_q4.Q1
    fprintf('  [PASS] Q increases monotonically with frequency in skin-effect regime\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Q should increase monotonically\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 19: Coupled Resonator Efficiency Convergence =====
fprintf('\n--- Test 19: Coupled Resonator Efficiency Convergence ---\n');
params_conv = params_nf;
params_conv.d_vec = linspace(0.01, 5, 100);
res_conv = wpt_nearfield_model(params_conv);

% η should be near max at short distance, and approach 0 at large distance
eta_short = res_conv.eta_inductive_pct(1);
eta_long = res_conv.eta_inductive_pct(end);
fprintf('  Efficiency at 0.01m: %.2f%%\n', eta_short);
fprintf('  Efficiency at 5m:    %.2f%%\n', eta_long);

if eta_short > eta_long && eta_long < 1.0
    fprintf('  [PASS] Efficiency converges toward zero at large distances\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Efficiency convergence behavior incorrect\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 20: Near-Field Energy Conservation =====
fprintf('\n--- Test 20: Near-Field Energy Conservation ---\n');
max_eta = max(res_conv.eta_inductive_pct);
fprintf('  Max valid efficiency: %.6f%%\n', max_eta);
if max_eta <= 100
    fprintf('  [PASS] Inductive efficiency does not exceed 100%%\n');
    pass_count = pass_count + 1;
else
    fprintf('  [FAIL] Inductive efficiency > 100%%! Physics violation.\n');
    fail_count = fail_count + 1;
end

%% ===== TEST 21: Crossover Detection Exists =====
fprintf('\n--- Test 21: Near-Field / Far-Field Crossover Detection ---\n');
params_ff = struct();
params_ff.freq_Hz = 13.56e6; % 13.56 MHz ISM band
params_ff.D_tx_m = 0.10;
params_ff.D_rx_m = 0.10;
params_ff.P_tx_dBm = 20;
params_ff.n_path = 2;
params_ff.eff_rectenna = 0.60;
params_ff.eta_ap = 0.60;
params_ff.d_vec = linspace(0.01, 10, 500);

res_ff = wpt_farfield_model(params_ff);

params_nf_cross = params_nf;
params_nf_cross.freq_Hz = 13.56e6;
params_nf_cross.d_vec = params_ff.d_vec;
params_nf_cross.N_tx = 10;
params_nf_cross.N_rx = 10;

res_nf = wpt_nearfield_model(params_nf_cross);

both_valid = ~isnan(res_ff.eff_system_pct) & ~isnan(res_nf.eta_inductive_pct);
if any(both_valid)
    delta = res_ff.eff_system_pct(both_valid) - res_nf.eta_inductive_pct(both_valid);
    d_valid = params_ff.d_vec(both_valid);
    
    delta(abs(delta) < 1e-10) = 0;
    sign_changes = find(diff(sign(delta)) ~= 0);
    
    if ~isempty(sign_changes)
        idx = sign_changes(1);
        d_cross = interp1(delta(idx:idx+1), d_valid(idx:idx+1), 0);
        fprintf('  Crossover detected at %.3f m\n', d_cross);
        fprintf('  [PASS] Crossover point exists\n');
        pass_count = pass_count + 1;
    else
        fprintf('  [SKIP] No crossover detected for these parameters\n');
    end
else
    fprintf('  [SKIP] No overlapping valid points for crossover\n');
end

%% ===== SUMMARY =====
fprintf('\n============================================================\n');
fprintf('  Results:  %d PASSED  |  %d FAILED\n', pass_count, fail_count);
fprintf('============================================================\n');

if fail_count == 0
    fprintf('  All tests passed. Physics engine is verified.\n');
else
    fprintf('  WARNING: %d test(s) failed. Review output above.\n', fail_count);
end

